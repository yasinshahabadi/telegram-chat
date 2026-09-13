// src/index.js - Telegram Chat Worker Entrypoint (Modular Architecture v2)

import { Router } from "./core/router.js";
import { jsonResponse, errorResponse } from "./core/response.js";
import { handleVerifyDevice, handleGetMe, handleLogout } from "./auth/authController.js";
import { handleGetMessages } from "./chat/messagesController.js";
import { handleSyncEvents, handleGetLatestCursor } from "./sync/syncController.js";
import { handleMediaUpload, handleMediaDownload } from "./media/mediaController.js";
import { handleTelegramWebhook } from "./telegram/webhookHandler.js";
import { handleWebSocketUpgrade } from "./realtime/wsHandler.js";

// اکسپورت رسمی کلاس Durable Object جهت شناسایی در زیرساخت کلودفلر
export { ChatRoom } from "./realtime/ChatRoom.js";

// ==========================================
// تعریف روتر ماژولار API
// ==========================================
const router = new Router();

// ۱. اندپوینت‌های احراز هویت و مدیریت نشست‌ها (فاز ۴)
router.post("/api/auth/verify-device", (req, env) => handleVerifyDevice(req, env));
router.get("/api/auth/me", (req, env) => handleGetMe(req, env));
router.post("/api/auth/logout", (req, env) => handleLogout(req, env));

// ۲. اندپوینت پیام‌ها و تاریخچه چت (فاز ۵)
router.get("/api/messages", (req, env) => handleGetMessages(req, env));

// ۳. اندپوینت‌های موتور همگام‌سازی آفلاین (فاز ۸ - دلتا سینک بر پایه Cursor)
router.get("/api/sync", (req, env) => handleSyncEvents(req, env));
router.get("/api/sync/latest-cursor", (req, env) => handleGetLatestCursor(req, env));

// ۴. اندپوینت ارتقا به وب‌سوکت بلادرنگ با احراز هویت الزامی (فاز ۷ - رفع آسیب‌پذیری C-02)
router.get("/api/ws", (req, env) => handleWebSocketUpgrade(req, env));

// ۵. وب‌هوک امن تلگرام (فاز ۶ - اعتبارسنجی Secret Token و Group Guard)
router.post("/api/telegram-webhook", (req, env, ctx) => handleTelegramWebhook(req, env, ctx));

// ۶. اندپوینت‌های چندرسانه‌ای مبتنی بر استریم ابری R2 (فاز ۹)
router.post("/api/media/upload", (req, env) => handleMediaUpload(req, env));
router.post("/api/upload", (req, env) => handleMediaUpload(req, env)); // حفظ جهت سازگاری کلاینت قبلی
router.get("/api/media/file", (req, env) => handleMediaDownload(req, env));
router.get("/api/media", (req, env) => handleMediaDownload(req, env)); // حفظ جهت سازگاری کلاینت قبلی

// ۷. دریافت آواتار تلگرام
router.get("/api/avatar", async (req, env) => {
  const url = new URL(req.url);
  const userId = url.searchParams.get("userId");
  if (!userId) return errorResponse("شناسه کاربر الزامی است.", 400);

  try {
    const photosRes = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getUserProfilePhotos?user_id=${userId}&limit=1`
    );
    const photosData = await photosRes.json();

    if (photosData.ok && photosData.result.total_count > 0) {
      const fileId = (photosData.result.photos[0][1] || photosData.result.photos[0][0]).file_id;
      const fileRes = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${fileId}`);
      const fileData = await fileRes.json();

      if (fileData.ok && fileData.result.file_path) {
        const imgRes = await fetch(`https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${fileData.result.file_path}`);
        return new Response(imgRes.body, {
          headers: { "Content-Type": "image/jpeg", "Cache-Control": "public, max-age=86400" }
        });
      }
    }
  } catch (e) {}
  return errorResponse("آواتار یافت نشد.", 404);
});

// ۸. اندپوینت‌های وب‌پوش قدیمی (حفظ موقت تا زمان اتصال کامل FCM در فاز ۱۱)
router.get("/api/vapid-public-key", (req, env) => jsonResponse({ publicKey: env.VAPID_PUBLIC_KEY || null }));
router.post("/api/push-subscribe", async (req, env) => {
  try {
    const { endpoint, p256dh, auth, sessionToken } = await req.json();
    let userId = null;
    if (sessionToken) {
      const user = await env.DB.prepare("SELECT user_id FROM sessions WHERE token = ?").bind(sessionToken).first();
      if (user) userId = user.user_id;
    }

    await env.DB.prepare(`
      INSERT OR REPLACE INTO push_subscriptions (endpoint, p256dh, auth, user_id)
      VALUES (?, ?, ?, ?)
    `).bind(endpoint, p256dh, auth, userId).run().catch(() => {});

    return jsonResponse({ ok: true });
  } catch (e) {
    return errorResponse("خطا در ثبت اشتراک پوش", 500);
  }
});

// ==========================================
// اکسپورت ورکر و مدیریت رویدادها
// ==========================================
export default {
  async fetch(request, env, ctx) {
    const res = await router.handle(request, env, ctx);

    if (res.status === 404 && env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return res;
  },

  async scheduled(event, env, ctx) {
    const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
    await env.DB.prepare("DELETE FROM messages WHERE created_at < ?").bind(oneDayAgo).run().catch(() => {});
  }
};
