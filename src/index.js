// src/index.js - Telegram Chat Worker Entrypoint (Modular Architecture v2)

import { Router } from "./core/router.js";
import { jsonResponse, errorResponse } from "./core/response.js";
import { handleVerifyDevice, handleGetMe, handleLogout } from "./auth/authController.js";
import { handleGetMessages } from "./chat/messagesController.js";
import { handleTelegramWebhook } from "./telegram/webhookHandler.js";
import { handleWebSocketUpgrade } from "./realtime/wsHandler.js";
import { escapeXml } from "./telegram/telegramClient.js";

// اکسپورت رسمی کلاس Durable Object جهت شناختن در زیرساخت کلودفلر
export { ChatRoom } from "./realtime/ChatRoom.js";

const MAX_FILE_SIZE = 20 * 1024 * 1024;

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

// ۳. اندپوینت ارتقا به وب‌سوکت بلادرنگ با احراز هویت الزامی (فاز ۷ - رفع آسیب‌پذیری C-02)
router.get("/api/ws", (req, env) => handleWebSocketUpgrade(req, env));

// ۴. وب‌هوک امن تلگرام (فاز ۶ - اعتبارسنجی Secret Token و Group Guard)
router.post("/api/telegram-webhook", (req, env, ctx) => handleTelegramWebhook(req, env, ctx));

// ۵. دریافت آواتار تلگرام
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

// ۶. دریافت مدیا از تلگرام (پروکسی موقت تا زمان استقرار باکت R2 در فاز ۹)
router.get("/api/media", async (req, env) => {
  const url = new URL(req.url);
  const fileId = url.searchParams.get("fileId");
  const customName = url.searchParams.get("name");
  const isDownload = url.searchParams.get("download") === "1";
  if (!fileId) return errorResponse("شناسه فایل الزامی است.", 400);

  try {
    const fileRes = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${fileId}`
    );
    const fileData = await fileRes.json();

    if (fileData.ok && fileData.result.file_path) {
      if (fileData.result.file_size && fileData.result.file_size > MAX_FILE_SIZE) {
        return errorResponse("حجم فایل بیش از ۲۰ مگابایت است.", 413);
      }

      const filePath = fileData.result.file_path;
      const ext = filePath.includes(".") ? filePath.split(".").pop().toLowerCase() : "bin";
      const fileName = customName || `file_${fileId.substring(0, 8)}.${ext}`;

      const rangeHeader = req.headers.get("Range") || req.headers.get("range");
      const tgHeaders = {};
      if (rangeHeader) tgHeaders["Range"] = rangeHeader;

      const mediaRes = await fetch(
        `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${filePath}`,
        { headers: tgHeaders }
      );

      let contentType = mediaRes.headers.get("Content-Type") || "application/octet-stream";
      if (ext === "mp4") contentType = "video/mp4";
      else if (ext === "jpg" || ext === "jpeg") contentType = "image/jpeg";
      else if (ext === "png") contentType = "image/png";
      else if (ext === "webp") contentType = "image/webp";
      else if (ext === "mp3") contentType = "audio/mpeg";
      else if (ext === "ogg") contentType = "audio/ogg";
      else if (ext === "m4a") contentType = "audio/mp4";

      const resHeaders = new Headers();
      resHeaders.set("Content-Type", contentType);
      resHeaders.set("Content-Disposition", `${isDownload ? "attachment" : "inline"}; filename="${encodeURIComponent(fileName)}"`);
      resHeaders.set("Cache-Control", "public, max-age=604800, immutable");
      resHeaders.set("Accept-Ranges", "bytes");

      if (mediaRes.headers.has("Content-Range")) {
        resHeaders.set("Content-Range", mediaRes.headers.get("Content-Range"));
      }
      if (mediaRes.headers.has("Content-Length")) {
        resHeaders.set("Content-Length", mediaRes.headers.get("Content-Length"));
      }

      return new Response(mediaRes.body, {
        status: mediaRes.status,
        headers: resHeaders
      });
    }
  } catch (e) {}
  return errorResponse("فایل یافت نشد.", 404);
});

// ۷. آپلود موقت مدیا (تا زمان اتصال Presigned URL در R2 در فاز ۹)
router.post("/api/upload", async (req, env) => {
  try {
    const formData = await req.formData();
    const file = formData.get("file");
    const caption = (formData.get("caption") || "").trim();
    const sessionToken = formData.get("sessionToken");
    const replyToRaw = formData.get("replyTo");
    const customType = formData.get("mediaType");

    if (!file || !(file instanceof File) || file.size > MAX_FILE_SIZE) {
      return errorResponse("فایل نامعتبر است یا حجم آن بیش از ۲۰ مگابایت است.", 400);
    }

    const user = await env.DB.prepare(`
      SELECT u.* FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.token = ?
    `).bind(sessionToken).first();

    if (!user || !user.is_approved) return errorResponse("دسترسی غیرمجاز است.", 401);

    let replyTo = null;
    if (replyToRaw) {
      try { replyTo = JSON.parse(replyToRaw); } catch (e) {}
    }

    let mediaType = "document";
    let tgEndpoint = "sendDocument";
    let fileField = "document";

    if (customType === "voice" || file.name.includes("voice") || file.name.endsWith("_voice.m4a") || file.name.endsWith("_voice.ogg")) {
      mediaType = "voice"; tgEndpoint = "sendVoice"; fileField = "voice";
    } else if (file.type.startsWith("image/")) {
      mediaType = "photo"; tgEndpoint = "sendPhoto"; fileField = "photo";
    } else if (file.type.startsWith("video/")) {
      mediaType = "video"; tgEndpoint = "sendVideo"; fileField = "video";
    } else if (file.type.startsWith("audio/")) {
      mediaType = "audio"; tgEndpoint = "sendAudio"; fileField = "audio";
    }

    const tgFormData = new FormData();
    tgFormData.append("chat_id", env.TELEGRAM_GROUP_ID);

    let tgCaption = `🌐 <b>[برنامه اندروید]</b>\n👤 <b>فرستنده:</b> ${escapeXml(user.full_name)}`;
    if (replyTo && !replyTo.tgMsgId) tgCaption += `\n↩️ <i>پاسخ به ${escapeXml(replyTo.name)}:</i> «${escapeXml(replyTo.text.substring(0, 30))}»`;
    if (caption) {
      tgCaption += `\n💬 ${escapeXml(caption)}`;
    }
    tgFormData.append("caption", tgCaption);
    tgFormData.append("parse_mode", "HTML");
    tgFormData.append(fileField, file, file.name);

    if (replyTo && replyTo.tgMsgId) {
      tgFormData.append("reply_parameters", JSON.stringify({ message_id: replyTo.tgMsgId }));
    }

    const tgRes = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${tgEndpoint}`, {
      method: "POST", body: tgFormData
    });
    const tgData = await tgRes.json();
    if (!tgData.ok) return errorResponse(tgData.description, 500);

    let fileId = "";
    let thumbId = null;
    let duration = 0;
    const resMsg = tgData.result;
    
    if (resMsg.photo && resMsg.photo.length > 0) fileId = resMsg.photo[resMsg.photo.length - 1].file_id;
    else if (resMsg.video) {
      fileId = resMsg.video.file_id;
      duration = resMsg.video.duration || 0;
      const th = resMsg.video.thumbnail || resMsg.video.thumb;
      if (th) thumbId = th.file_id;
    } else if (resMsg.voice) {
      fileId = resMsg.voice.file_id;
      duration = resMsg.voice.duration || 0;
    } else if (resMsg.audio) {
      fileId = resMsg.audio.file_id;
      duration = resMsg.audio.duration || 0;
    } else if (resMsg.document) fileId = resMsg.document.file_id;

    const msgId = crypto.randomUUID();
    const timestamp = Date.now();
    const replyId = replyTo ? replyTo.id : null;

    await env.DB.prepare(`
      INSERT INTO messages (id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id, reply_to_message_id)
      VALUES (?, ?, ?, 0, ?, ?, ?, ?)
    `).bind(msgId, user.id, caption, timestamp, timestamp, resMsg.message_id, replyId).run();

    if (fileId) {
      await env.DB.prepare(`
        INSERT INTO attachments (id, message_id, media_type, telegram_file_id, file_name, file_size, duration, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(crypto.randomUUID(), msgId, mediaType, fileId, file.name, file.size, duration, timestamp).run();
    }

    const roomId = env.CHAT_ROOM.idFromName("global_room");
    await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
      method: "POST",
      body: JSON.stringify({
        type: "new_message",
        message: {
          id: msgId, sender_id: user.id, sender_name: user.full_name, text: caption,
          is_from_telegram: 0, timestamp, reply_to_name: replyTo ? replyTo.name : null, reply_to_text: replyTo ? replyTo.text : null,
          reply_to_id: replyId, tg_msg_id: resMsg.message_id, is_read: 0, read_at: null, is_edited: 0, media_type: mediaType,
          media_file_id: fileId, media_file_name: file.name, media_file_size: file.size, media_thumb_id: thumbId, media_duration: duration, reactions: "{}"
        }
      })
    });

    return jsonResponse({ ok: true, fileId, messageId: msgId });
  } catch (err) {
    return errorResponse(err.message, 500);
  }
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
