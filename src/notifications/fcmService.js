/**
 * Native Android Firebase Cloud Messaging (FCM v1 HTTP API) Service
 * Implements pure Web Crypto Google Service Account JWT signing and high-priority delivery.
 */

let cachedAccessToken = null;
let tokenExpiresAt = 0;

// تبدیل کلید خصوصی PEM به باینری جهت وارد کردن در Web Crypto
function pemToBinary(pem) {
  const cleanPem = pem
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const binaryDer = atob(cleanPem);
  const bytes = new Uint8Array(binaryDer.length);
  for (let i = 0; i < binaryDer.length; i++) {
    bytes[i] = binaryDer.charCodeAt(i);
  }
  return bytes.buffer;
}

// انکود Base64Url استاندارد بدون کاراکترهای padding
function base64UrlEncode(strOrBuffer) {
  let base64;
  if (typeof strOrBuffer === "string") {
    base64 = btoa(unescape(encodeURIComponent(strOrBuffer)));
  } else {
    let binary = "";
    const bytes = new Uint8Array(strOrBuffer);
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    base64 = btoa(binary);
  }
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * تولید توکن دسترسی OAuth2 برای احراز هویت در FCM v1 API گوگل
 */
async function getGoogleAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && now < tokenExpiresAt - 300) {
    return cachedAccessToken;
  }

  const clientEmail = env.FIREBASE_CLIENT_EMAIL;
  const privateKeyPem = env.FIREBASE_PRIVATE_KEY;

  if (!clientEmail || !privateKeyPem) {
    return null;
  }

  try {
    const keyBuffer = pemToBinary(privateKeyPem);
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      keyBuffer,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const header = { alg: "RS256", typ: "JWT" };
    const claims = {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now
    };

    const unsignedToken = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claims))}`;
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      privateKey,
      new TextEncoder().encode(unsignedToken)
    );

    const signedJwt = `${unsignedToken}.${base64UrlEncode(signature)}`;

    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`
    });

    const tokenData = await tokenRes.json();
    if (tokenData.access_token) {
      cachedAccessToken = tokenData.access_token;
      tokenExpiresAt = now + (tokenData.expires_in || 3600);
      return cachedAccessToken;
    }
  } catch (err) {
    console.error("[FCM OAuth Error]:", err.message);
  }

  return null;
}

/**
 * ارسال یک پیام اولویت‌دار به یک توکن دستگاه خاص در اندروید
 */
async function sendSingleFcmMessage(env, token, payload, accessToken) {
  const projectId = env.FIREBASE_PROJECT_ID;
  if (!projectId || !accessToken) return;

  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const body = {
    message: {
      token,
      data: {
        type: "new_message",
        messageId: String(payload.messageId || ""),
        senderId: String(payload.senderId || ""),
        senderName: String(payload.senderName || ""),
        text: String(payload.text || ""),
        mediaType: String(payload.mediaType || ""),
        createdAt: String(payload.createdAt || Date.now())
      },
      android: {
        priority: "high",
        ttl: "86400s"
      }
    }
  };

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    // در صورتی که توکن منقضی یا برنامه حذف شده باشد، توکن را از دیتابیس پاک کن
    if (res.status === 404 || res.status === 410) {
      await env.DB.prepare(
        "DELETE FROM device_fcm_tokens WHERE fcm_token = ?"
      ).bind(token).run().catch(() => {});
    } else if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      if (errData.error?.status === "NOT_FOUND" || errData.error?.details?.[0]?.errorCode === "UNREGISTERED") {
        await env.DB.prepare(
          "DELETE FROM device_fcm_tokens WHERE fcm_token = ?"
        ).bind(token).run().catch(() => {});
      }
    }
  } catch (err) {
    // خطای شبکه تاثیری در کارایی سیستم اصلی نخواهد داشت
  }
}

/**
 * توزیع اعلان پیام جدید به تمام دستگاه‌های ثبت‌شده (به جز فرستنده)
 */
export async function dispatchNewMessagePush(env, messagePayload, excludeUserId = null) {
  try {
    const accessToken = await getGoogleAccessToken(env);
    if (!accessToken) {
      return; // تنظیمات فایربیس هنوز کامل نیست
    }

    // واکشی تمام توکن‌های ثبت‌شده فعال به جز دستگاه فرستنده
    const query = excludeUserId
      ? "SELECT fcm_token FROM device_fcm_tokens WHERE user_id != ? OR user_id IS NULL"
      : "SELECT fcm_token FROM device_fcm_tokens";

    const stmt = excludeUserId
      ? env.DB.prepare(query).bind(excludeUserId)
      : env.DB.prepare(query);

    const { results: tokens } = await stmt.all();
    if (!tokens || tokens.length === 0) return;

    // ارسال موازی با Promise.allSettled
    await Promise.allSettled(
      tokens.map(t => sendSingleFcmMessage(env, t.fcm_token, messagePayload, accessToken))
    );
  } catch (err) {
    console.error("[FCM Dispatch Error]:", err.message);
  }
}
