/**
 * Pushy Notification Service with Verbose Diagnostics
 */
export async function dispatchNewMessagePush(env, messagePayload, excludeUserId = null) {
  const apiKey = env.PUSHY_SECRET_API_KEY;
  if (!apiKey) {
    return { ok: false, error: "PUSHY_SECRET_API_KEY is missing in worker environment" };
  }

  try {
    // واکشی توکن‌های دستگاه‌های ثبت‌شده
    const { results: rows } = await env.DB.prepare(
      "SELECT fcm_token FROM device_fcm_tokens"
    ).all();

    if (!rows || rows.length === 0) {
      return { ok: false, error: "No device tokens found in database" };
    }

    const tokens = rows.map(r => r.fcm_token).filter(Boolean);
    const sender = messagePayload.senderName || "Guysgram";
    const bodyText = messagePayload.text || "پیام جدید دریافت شد";

    const pushPayload = {
      to: tokens.length === 1 ? tokens[0] : tokens,
      data: {
        title: sender,
        message: bodyText,
        senderName: sender,
        text: bodyText,
        messageId: String(messagePayload.id || ""),
      },
      notification: {
        title: sender,
        body: bodyText,
        badge: 1,
        sound: "default"
      }
    };

    const res = await fetch(`https://api.pushy.me/push?api_key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(pushPayload)
    });

    const data = await res.json().catch(() => ({}));
    return {
      ok: res.ok,
      status: res.status,
      tokensCount: tokens.length,
      response: data
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}
