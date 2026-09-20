import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";

/**
 * Notification Controller for Android Device Tokens
 */
export async function handleRegisterFcmToken(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const { fcmToken, deviceId } = await request.json();
    if (!fcmToken || typeof fcmToken !== "string") {
      return errorResponse("توکن اعلان معتبر الزامی است.", 400);
    }

    // استخراج و تضمین شناسه معتبر دستگاه تاییدشده جهت رعایت کلید خارجی دیتابیس
    let validDeviceId = auth.device.id;
    if (deviceId && deviceId !== auth.device.id) {
      const dev = await env.DB.prepare(
        "SELECT id FROM devices WHERE user_id = ? AND (id = ? OR device_identifier = ?)"
      ).bind(auth.user.id, deviceId, deviceId).first();
      if (dev) validDeviceId = dev.id;
    }

    const now = Date.now();
    const tokenId = crypto.randomUUID();

    // درج یا جایگزینی توکن در جدول device_fcm_tokens
    await env.DB.prepare(`
      INSERT OR REPLACE INTO device_fcm_tokens (id, device_id, user_id, fcm_token, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(tokenId, validDeviceId, auth.user.id, fcmToken.trim(), now).run();

    return jsonResponse({
      ok: true,
      message: "توکن اعلان دستگاه با موفقیت در دیتابیس ذخیره شد."
    });
  } catch (err) {
    return errorResponse("خطا در ثبت توکن اعلان.", 500, "REGISTER_ERROR", err.message);
  }
}

export async function handleUnregisterFcmToken(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const { fcmToken } = await request.json();
    if (fcmToken) {
      await env.DB.prepare(`
        DELETE FROM device_fcm_tokens WHERE fcm_token = ? AND user_id = ?
      `).bind(fcmToken.trim(), auth.user.id).run();
    }

    return jsonResponse({
      ok: true,
      message: "توکن با موفقیت حذف شد."
    });
  } catch (err) {
    return errorResponse("خطا در حذف توکن.", 500, "UNREGISTER_ERROR", err.message);
  }
}
