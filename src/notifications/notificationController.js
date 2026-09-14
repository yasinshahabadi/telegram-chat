import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";

/**
 * Notification Controller for Android FCM Device Tokens
 */

/**
 * ثبت یا بروزرسانی توکن FCM دستگاه کاربر
 * POST /api/notifications/register-token
 */
export async function handleRegisterFcmToken(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const { fcmToken, deviceId } = await request.json();
    if (!fcmToken || typeof fcmToken !== "string") {
      return errorResponse("توکن FCM معتبر الزامی است.", 400);
    }

    const targetDeviceId = deviceId || auth.device.id;
    const now = Date.now();
    const tokenId = crypto.randomUUID();

    // درج یا جایگزینی توکن در جدول device_fcm_tokens
    await env.DB.prepare(`
      INSERT OR REPLACE INTO device_fcm_tokens (id, device_id, user_id, fcm_token, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(tokenId, targetDeviceId, auth.user.id, fcmToken.trim(), now).run();

    return jsonResponse({
      ok: true,
      message: "توکن اعلان دستگاه با موفقیت ثبت شد."
    });
  } catch (err) {
    return errorResponse("خطا در ثبت توکن اعلان.", 500, "FCM_REGISTER_ERROR", err.message);
  }
}

/**
 * حذف توکن FCM دستگاه (هنگام خروج از حساب)
 * POST /api/notifications/unregister-token
 */
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
      message: "توکن اعلان دستگاه با موفقیت حذف شد."
    });
  } catch (err) {
    return errorResponse("خطا در حذف توکن اعلان.", 500, "FCM_UNREGISTER_ERROR", err.message);
  }
}
