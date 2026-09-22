/**
 * Firebase Cloud Messaging (FCM) HTTP v1 API Service
 * جایگزین کامل Pushy با استفاده از Service Account و FCM HTTP v1
 */

// کش توکن دسترسی OAuth2 (درون isolate مشترک است)
let cachedAccessToken = null;
let cachedTokenExpiry = 0;

/**
 * تبدیل PEM private key به ArrayBuffer برای Web Crypto API
 */
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

/**
 * انکود Base64URL (استاندارد JWT)
 */
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
 * دریافت Access Token از Google OAuth2 با استفاده از Service Account
 * این توکن برای ارسال درخواست به FCM HTTP v1 API ضروری است.
 */
async function getAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);

  // اگر توکن کش‌شده هنوز معتبر است، همان را برگردان (۶۰ ثانیه حاشیه امن)
  if (cachedAccessToken && cachedTokenExpiry > now + 60) {
    return cachedAccessToken;
  }

  // ۱. ساخت JWT Header و Payload
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

  // ۲. وارد کردن Private Key و امضای JWT
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

  // ۳. تبادل JWT با Access Token
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
    throw new Error(
      `Failed to get access token: ${JSON.stringify(tokenData)}`
    );
  }

  cachedAccessToken = tokenData.access_token;
  cachedTokenExpiry = now + (tokenData.expires_in || 3600);

  return cachedAccessToken;
}

/**
 * ارسال اعلان به یک توکن مشخص با FCM HTTP v1
 */
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
        notification: {
          channel_id: "guysgram_default_channel",
          sound: "default",
          default_vibrate_timings: true,
          notification_count: 1,
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

/**
 * ارسال انبوه اعلان به تمام دستگاه‌های ثبت‌شده
 * (با پاکسازی خودکار توکن‌های نامعتبر)
 */
export async function dispatchNewMessagePush(env, messagePayload, excludeUserId = null) {
  const serviceAccountJson = env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountJson) {
    return {
      ok: false,
      error: "FIREBASE_SERVICE_ACCOUNT is missing in worker environment",
    };
  }

  let serviceAccount;
  try {
    serviceAccount =
      typeof serviceAccountJson === "string"
        ? JSON.parse(serviceAccountJson)
        : serviceAccountJson;
  } catch (e) {
    return {
      ok: false,
      error: `Invalid FIREBASE_SERVICE_ACCOUNT JSON: ${e.message}`,
    };
  }

  if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
    return {
      ok: false,
      error: "FIREBASE_SERVICE_ACCOUNT is missing required fields",
    };
  }

  try {
    // ۱. واکشی توکن‌های دستگاه (اختیاری: فیلتر بر اساس excludeUserId)
    let query = "SELECT id, fcm_token, user_id FROM device_fcm_tokens";
    let stmt;
    if (excludeUserId) {
      stmt = env.DB.prepare(`${query} WHERE user_id != ?`).bind(excludeUserId);
    } else {
      stmt = env.DB.prepare(query);
    }

    const { results: rows } = await stmt.all();

    if (!rows || rows.length === 0) {
      return { ok: false, error: "No device tokens found in database" };
    }

    // ۲. دریافت Access Token
    const accessToken = await getAccessToken(serviceAccount);

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

    // ۴. ارسال موازی به همه دستگاه‌ها
    const results = await Promise.all(
      rows.map(async (row) => {
        try {
          const result = await sendToToken(
            accessToken,
            serviceAccount.project_id,
            row.fcm_token,
            notification
          );

          // ۵. اگر توکن نامعتبر بود، از دیتابیس پاک کن
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
              return {
                token: row.fcm_token.substring(0, 20) + "...",
                ok: false,
                cleaned: true,
                errorCode,
              };
            }
          }

          return {
            token: row.fcm_token.substring(0, 20) + "...",
            ok: result.ok,
            status: result.status,
          };
        } catch (err) {
          return {
            token: row.fcm_token.substring(0, 20) + "...",
            ok: false,
            error: err.message,
          };
        }
      })
    );

    const successCount = results.filter((r) => r.ok).length;
    const cleanedCount = results.filter((r) => r.cleaned).length;

    return {
      ok: true,
      total: results.length,
      successCount,
      cleanedCount,
      failedCount: results.length - successCount,
      results,
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}