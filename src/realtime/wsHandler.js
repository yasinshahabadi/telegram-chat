import { authenticateRequest } from "../auth/sessionService.js";
import { errorResponse } from "../core/response.js";

/**
 * Secure WebSocket Handshake Handler
 * Enforces Zero-Trust session validation before upgrading to WebSocket.
 */
export async function handleWebSocketUpgrade(request, env) {
  // ۱. بررسی الزام هدر Upgrade: websocket
  if (request.headers.get("Upgrade") !== "websocket") {
    return new Response("Expected WebSocket Upgrade", { status: 426 });
  }

  // ۲. احراز هویت قطعی نشست کاربر (رفع آسیب‌پذیری بحرانی C-02)
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  // ۳. ایجاد هدرهای امن داخلی حاوی اطلاعات تاییدشده کاربر و دستگاه
  const forwardedHeaders = new Headers(request.headers);
  forwardedHeaders.set("X-Auth-User-Id", auth.user.id);
  forwardedHeaders.set("X-Auth-Full-Name", encodeURIComponent(auth.user.fullName));
  forwardedHeaders.set("X-Auth-Username", encodeURIComponent(auth.user.username || "ندارد"));
  forwardedHeaders.set("X-Auth-Telegram-Id", auth.user.telegramId || "");
  forwardedHeaders.set("X-Auth-Device-Id", auth.device.id);
  forwardedHeaders.set("X-Auth-Is-Admin", String(auth.user.isAdmin));

  // ۴. ارسال درخواست امن به دوریبل آبجکت اتاق چت
  const forwardedRequest = new Request(request, {
    headers: forwardedHeaders
  });

  const roomId = env.CHAT_ROOM.idFromName("global_room");
  return env.CHAT_ROOM.get(roomId).fetch(forwardedRequest);
}
