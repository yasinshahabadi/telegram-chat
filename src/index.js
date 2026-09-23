// src/index.js - Guysgram Backend Worker Entrypoint (With Test Diagnostic Endpoint)

import { Router } from "./core/router.js";
import { jsonResponse, errorResponse } from "./core/response.js";
import { handleVerifyDevice, handleGetMe, handleLogout } from "./auth/authController.js";
import { handleGetMessages } from "./chat/messagesController.js";
import { handleSyncEvents, handleGetLatestCursor } from "./sync/syncController.js";
import { handleMediaUpload, handleMediaDownload } from "./media/mediaController.js";
import { handleRegisterFcmToken, handleUnregisterFcmToken } from "./notifications/notificationController.js";
import { handleTelegramWebhook } from "./telegram/webhookHandler.js";
import { handleWebSocketUpgrade } from "./realtime/wsHandler.js";
import { dispatchNewMessagePush } from "./notifications/fcmService.js";
import { handleGetUserAvatar } from "./users/avatarController.js";

export { ChatRoom } from "./realtime/ChatRoom.js";

const router = new Router();

// اندپوینت‌های احراز هویت
router.post("/api/auth/verify-device", (req, env) => handleVerifyDevice(req, env));
router.get("/api/auth/me", (req, env) => handleGetMe(req, env));
router.post("/api/auth/logout", (req, env) => handleLogout(req, env));

// اندپوینت‌های چت و سینک
router.get("/api/messages", (req, env) => handleGetMessages(req, env));
router.get("/api/sync", (req, env) => handleSyncEvents(req, env));
router.get("/api/sync/latest-cursor", (req, env) => handleGetLatestCursor(req, env));

// ارتقای وب‌سوکت
router.get("/api/ws", (req, env) => handleWebSocketUpgrade(req, env));

// وب‌هوک تلگرام
router.post("/api/telegram-webhook", (req, env, ctx) => handleTelegramWebhook(req, env, ctx));

// مدیا
router.post("/api/media/upload", (req, env) => handleMediaUpload(req, env));
router.post("/api/upload", (req, env) => handleMediaUpload(req, env));
router.get("/api/media/file", (req, env) => handleMediaDownload(req, env));
router.get("/api/media", (req, env) => handleMediaDownload(req, env));
router.get("/api/users/avatar", (req, env) => handleGetUserAvatar(req, env));

// نوتیفیکیشن
router.post("/api/notifications/register-token", (req, env) => handleRegisterFcmToken(req, env));
router.post("/api/notifications/unregister-token", (req, env) => handleUnregisterFcmToken(req, env));

// اندپوینت اختصاصی تست و دیباگ مستقیم پوشی از سرور
router.get("/api/test-push", async (req, env) => {
  const result = await dispatchNewMessagePush(env, {
    id: crypto.randomUUID(),
    senderName: "تست اختصاصی سرور Guysgram",
    text: "این یک پیام تست مستقیم از کلودفلر با FCM است!",
    createdAt: Date.now()
  });

  return jsonResponse({
    endpoint: "test-push",
    result
  });
});

export default {
  async fetch(request, env, ctx) {
    return await router.handle(request, env, ctx);
  },

  async scheduled(event, env, ctx) {
    const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
    await env.DB.prepare("DELETE FROM messages WHERE created_at < ?").bind(oneDayAgo).run().catch(() => {});
  }
};
