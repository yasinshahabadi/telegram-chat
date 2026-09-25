/**
 * Firebase Cloud Messaging (FCM) HTTP v1 API Service
 * جایگزین کامل Pushy با استفاده از Service Account و FCM HTTP v1
 */

let cachedAccessToken = null;
let cachedTokenExpiry = 0;

function pemToArrayBuffer(pem) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(b64);
  const buffer = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    buffer[i] = binary.charCodeAt(i);
  }
  return buffer.buffer;
}

function base64UrlEncode(input) {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * ✅ تابع داخلی برای pre-warm کردن token
 * در ChatRoom constructor فراخوانی می‌شود
 */
export async function _internalWarmToken(env) {
  try {
    const serviceAccountJson = env.FIREBASE_SERVICE_ACCOUNT;
    if (!serviceAccountJson) return;
    const serviceAccount = typeof serviceAccountJson === "string"
      ? JSON.parse(serviceAccountJson)
      : serviceAccountJson;
    await getAccessToken(serviceAccount);
    console.log("[FCM] Token pre-warmed successfully");
  } catch (e) {
    console.error("[FCM] Pre-warm failed:", e);
  }
}

async function getAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);

  if (cachedAccessToken && cachedTokenExpiry > now + 60) {
    console.log("[FCM] Using cached token (expires in", cachedTokenExpiry - now, "s)");
    return cachedAccessToken;
  }

  const startTime = Date.now();
  console.log("[FCM] Generating new OAuth2 token...");

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const privateKeyBuffer = pemToArrayBuffer(serviceAccount.private_key);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const signatureB64 = base64UrlEncode(new Uint8Array(signature));
  const jwt = `${signingInput}.${signatureB64}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenData.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`);
  }

  cachedAccessToken = tokenData.access_token;
  cachedTokenExpiry = now + (tokenData.expires_in || 3600);

  console.log(`[FCM] Token generated in ${Date.now() - startTime}ms`);
  return cachedAccessToken;
}

async function sendToToken(accessToken, projectId, token, notification) {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const body = {
    message: {
      token: token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      android: {
        priority: "high",
        // ✅ نگه‌داری ۴ هفته در صف FCM (حداکثر مجاز)
        ttl: "2419200s",
        collapse_key: "chat_messages",
        notification: {
          channel_id: "guysgram_default_channel_v2",
          sound: "default",
          default_vibrate_timings: true,
          notification_priority: "PRIORITY_MAX",
          visibility: "PUBLIC",
          notification_count: 1,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
          "apns-expiration": "2419200",
        },
      },
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}

export async function dispatchNewMessagePush(env, messagePayload, excludeUserId = null) {
  const startTotal = Date.now();

  const serviceAccountJson = env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountJson) {
    console.error("[FCM] FIREBASE_SERVICE_ACCOUNT missing");
    return { ok: false, error: "FIREBASE_SERVICE_ACCOUNT is missing in worker environment" };
  }

  let serviceAccount;
  try {
    serviceAccount = typeof serviceAccountJson === "string"
      ? JSON.parse(serviceAccountJson)
      : serviceAccountJson;
  } catch (e) {
    console.error("[FCM] Invalid service account JSON:", e.message);
    return { ok: false, error: `Invalid FIREBASE_SERVICE_ACCOUNT JSON: ${e.message}` };
  }

  if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
    return { ok: false, error: "FIREBASE_SERVICE_ACCOUNT is missing required fields" };
  }

  try {
    // ۱. واکشی توکن‌های دستگاه
    const startDb = Date.now();
    let query = "SELECT id, fcm_token, user_id FROM device_fcm_tokens";
    let stmt;
    if (excludeUserId) {
      stmt = env.DB.prepare(`${query} WHERE user_id != ?`).bind(excludeUserId);
    } else {
      stmt = env.DB.prepare(query);
    }

    const { results: rows } = await stmt.all();
    const dbTime = Date.now() - startDb;
    console.log(`[FCM] DB query: ${dbTime}ms, found ${rows?.length || 0} tokens`);

    if (!rows || rows.length === 0) {
      return { ok: false, error: "No device tokens found in database" };
    }

    // ۲. دریافت Access Token
    const startToken = Date.now();
    const accessToken = await getAccessToken(serviceAccount);
    const tokenTime = Date.now() - startToken;
    console.log(`[FCM] Token fetch: ${tokenTime}ms`);

    // ۳. آماده‌سازی محتوای اعلان
    const sender = messagePayload.senderName || "Guysgram";
    const bodyText = messagePayload.text || "پیام جدید دریافت شد";

    const notification = {
      title: sender,
      body: bodyText,
      data: {
        title: sender,
        message: bodyText,
        messageId: String(messagePayload.id || ""),
        senderName: sender,
        senderId: String(messagePayload.senderId || ""),
      },
    };

    // ۴. ارسال موازی
    const startFcm = Date.now();
    const results = await Promise.all(
      rows.map(async (row) => {
        try {
          const result = await sendToToken(
            accessToken,
            serviceAccount.project_id,
            row.fcm_token,
            notification
          );

          if (!result.ok) {
            const errorCode =
              result.data?.error?.details?.[0]?.errorCode ||
              result.data?.error?.status ||
              "";

            if (
              errorCode === "UNREGISTERED" ||
              errorCode === "NOT_FOUND" ||
              errorCode === "INVALID_ARGUMENT" ||
              result.status === 404
            ) {
              await env.DB.prepare("DELETE FROM device_fcm_tokens WHERE id = ?")
                .bind(row.id)
                .run()
                .catch(() => {});
              return { ok: false, cleaned: true, errorCode };
            }
          }

          return { ok: result.ok, status: result.status };
        } catch (err) {
          return { ok: false, error: err.message };
        }
      })
    );

    const fcmTime = Date.now() - startFcm;
    const totalTime = Date.now() - startTotal;

    const successCount = results.filter((r) => r.ok).length;
    const cleanedCount = results.filter((r) => r.cleaned).length;

    console.log(`[FCM] Timing: DB=${dbTime}ms, Token=${tokenTime}ms, FCM=${fcmTime}ms, Total=${totalTime}ms`);
    console.log(`[FCM] Result: ${successCount}/${results.length} succeeded, ${cleanedCount} cleaned`);

    return {
      ok: true,
      total: results.length,
      successCount,
      cleanedCount,
      failedCount: results.length - successCount,
      timings: { db: dbTime, token: tokenTime, fcm: fcmTime, total: totalTime },
    };
  } catch (err) {
    console.error("[FCM] Error:", err.message);
    return { ok: false, error: err.message };
  }
}