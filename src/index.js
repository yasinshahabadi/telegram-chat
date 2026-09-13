// src/index.js - Telegram Chat Worker Entrypoint (Modular Architecture v2)

import { DurableObject } from "cloudflare:workers";
import { buildPushPayload } from "@block65/webcrypto-web-push";

import { Router } from "./core/router.js";
import { jsonResponse, errorResponse } from "./core/response.js";
import { handleVerifyDevice, handleGetMe, handleLogout, processTelegramAuthStart } from "./auth/authController.js";
import { handleGetMessages } from "./chat/messagesController.js";

const MAX_FILE_SIZE = 20 * 1024 * 1024;

export function escapeXml(str) {
  return String(str || "").replace(/[&<>"']/g, m => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[m]));
}

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

// ۳. اندپوینت ارتقا به وب‌سوکت بلادرنگ
router.get("/api/ws", (req, env) => {
  if (req.headers.get("Upgrade") !== "websocket") {
    return new Response("Expected WebSocket", { status: 426 });
  }
  const id = env.CHAT_ROOM.idFromName("global_room");
  return env.CHAT_ROOM.get(id).fetch(req);
});

// ۴. وب‌هوک تلگرام
router.post("/api/telegram-webhook", async (req, env, ctx) => {
  try {
    const update = await req.json();
    return await handleTelegramUpdate(update, env, ctx);
  } catch (e) {
    return new Response("OK");
  }
});

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

// ۸. اندپوینت‌های وب‌پوش قدیمی (حفظ جهت سازگاری تا پیاده‌سازی کامل FCM در فاز ۱۱)
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

    // در صورتی که روتر مسیر را پیدا نکرد، فایل‌های استاتیک وب را بررسی کن (اگر وجود داشته باشد)
    if (res.status === 404 && env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return res;
  },

  async scheduled(event, env, ctx) {
    // پاکسازی خودکار پیام‌های قدیمی‌تر از ۲۴ ساعت در جدول messages
    const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
    await env.DB.prepare("DELETE FROM messages WHERE created_at < ?").bind(oneDayAgo).run().catch(() => {});
  }
};

// ==========================================
// هندلر آپدیت‌های تلگرام
// ==========================================
async function handleTelegramUpdate(update, env, ctx) {
  if (update.callback_query) {
    const cb = update.callback_query;
    const data = cb.data || "";
    if (cb.from.id.toString() !== env.ADMIN_TELEGRAM_ID.toString()) return new Response("Unauthorized");

    if (data === "admin_users_list") {
      const { results: users } = await env.DB.prepare("SELECT * FROM users WHERE is_approved = 1").all();
      const buttons = (users || []).map(u => [{
        text: `👤 ${u.full_name} (${u.username !== "ندارد" ? '@' + u.username : u.telegram_id})`,
        callback_data: `manage_u:${u.id}`
      }]);
      buttons.push([{ text: "🔄 رفرش لیست", callback_data: "admin_users_list" }]);

      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/editMessageText`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: cb.message.chat.id, message_id: cb.message.message_id,
          text: `⚙️ <b>داشبورد مدیریت کاربران اپلیکیشن</b>\n\n👥 تعداد کل تاییدشده: <b>${users ? users.length : 0}</b> نفر:`,
          parse_mode: "HTML", reply_markup: { inline_keyboard: buttons }
        })
      });
      return new Response("OK");
    }

    if (data.startsWith("manage_u:")) {
      const targetUserId = data.replace("manage_u:", "");
      const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(targetUserId).first();
      if (!u) return new Response("OK");

      const text = `👤 <b>مشخصات کاربر:</b>\n\n` +
                   `• نام: ${escapeXml(u.full_name)}\n` +
                   `• یوزرنیم: @${escapeXml(u.username)}\n` +
                   `• شناسه تلگرام: <code>${u.telegram_id}</code>`;

      const buttons = [
        [{ text: "❌ حذف کامل کاربر", callback_data: `del_u:${u.id}` }],
        [{ text: "🔙 بازگشت به لیست", callback_data: "admin_users_list" }]
      ];

      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/editMessageText`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: cb.message.chat.id, message_id: cb.message.message_id, text, parse_mode: "HTML", reply_markup: { inline_keyboard: buttons } })
      });
      return new Response("OK");
    }

    if (data.startsWith("del_u:")) {
      const targetUserId = data.replace("del_u:", "");
      const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(targetUserId).first();
      if (u) {
        await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(targetUserId).run();
        await env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(targetUserId).run();

        const roomId = env.CHAT_ROOM.idFromName("global_room");
        await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
          method: "POST", body: JSON.stringify({ type: "user_kicked", userId: targetUserId, tgId: u.telegram_id })
        });

        await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/editMessageText`, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            chat_id: cb.message.chat.id, message_id: cb.message.message_id,
            text: `✅ کاربر <b>${escapeXml(u.full_name)}</b> با موفقیت حذف شد.`,
            parse_mode: "HTML", reply_markup: { inline_keyboard: [[{ text: "🔙 بازگشت به لیست", callback_data: "admin_users_list" }]] }
          })
        });
      }
      return new Response("OK");
    }

    const [action, userId] = data.split(":");
    if (action === "approve") {
      await env.DB.prepare("UPDATE users SET is_approved = 1, updated_at = ? WHERE id = ?").bind(Date.now(), userId).run();
      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/editMessageText`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: cb.message.chat.id, message_id: cb.message.message_id, text: `${cb.message.text}\n\n✅ دسترسی تایید شد.` })
      });
    } else if (action === "reject") {
      await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId).run();
      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/editMessageText`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: cb.message.chat.id, message_id: cb.message.message_id, text: `${cb.message.text}\n\n❌ رد شد.` })
      });
    }
    return new Response("OK");
  }

  if (update.message && update.message.text === "/admin") {
    if (update.message.from.id.toString() !== env.ADMIN_TELEGRAM_ID.toString()) return new Response("Unauthorized");
    const { results: users } = await env.DB.prepare("SELECT * FROM users WHERE is_approved = 1").all();
    const buttons = (users || []).map(u => [{
      text: `👤 ${u.full_name} (${u.username !== "ندارد" ? '@' + u.username : u.telegram_id})`,
      callback_data: `manage_u:${u.id}`
    }]);
    buttons.push([{ text: "🔄 رفرش لیست", callback_data: "admin_users_list" }]);

    await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: env.ADMIN_TELEGRAM_ID,
        text: `⚙️ <b>داشبورد مدیریت کاربران اپلیکیشن</b>\n\n👥 تعداد کل: <b>${users ? users.length : 0}</b> نفر:`,
        parse_mode: "HTML", reply_markup: { inline_keyboard: buttons }
      })
    });
    return new Response("OK");
  }

  // فرآیند استارت و ورود عمیق (/start auth_<token>)
  if (update.message && update.message.text && update.message.text.startsWith("/start auth_")) {
    const token = update.message.text.split(" ")[1].replace("auth_", "");
    const tgUser = update.message.from;

    const authResult = await processTelegramAuthStart(env, tgUser, token);

    if (!authResult.isAdmin && !authResult.isApproved) {
      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: env.ADMIN_TELEGRAM_ID,
          text: `🔔 <b>درخواست عضویت جدید اپلیکیشن</b>\n\n👤 نام: ${escapeXml(tgUser.first_name || "")}\n🆔 آیدی: @${tgUser.username || "ندارد"}\n🔢 شناسه: <code>${tgUser.id}</code>`,
          parse_mode: "HTML", reply_markup: { inline_keyboard: [[{ text: "✅ تایید دسترسی", callback_data: `approve:${authResult.userId}` }, { text: "❌ رد", callback_data: `reject:${authResult.userId}` }]] }
        })
      });
    }

    await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: tgUser.id,
        text: authResult.isAdmin
          ? "شما مدیر هستید. دسترسی به اپلیکیشن تایید شد!"
          : "درخواست برای مدیر ارسال شد. پس از تایید مدیر، اپلیکیشن شما فعال خواهد شد."
      })
    });
    return new Response("OK");
  }

  // پیام جدید از سوپرگروه تلگرام
  if (update.message && update.message.chat) {
    const incomingChatId = update.message.chat.id.toString();
    const targetGroupId = env.TELEGRAM_GROUP_ID.toString();

    const isMatch = (
      incomingChatId === targetGroupId ||
      incomingChatId === targetGroupId.replace("-", "-100") ||
      incomingChatId.replace("-100", "-") === targetGroupId
    );

    if (isMatch && !update.message.from.is_bot) {
      const msg = update.message;
      const msgId = crypto.randomUUID();
      const senderName = `${msg.from.first_name || ""} ${msg.from.last_name || ""}`.trim();
      const timestamp = Date.now();
      const text = msg.text || msg.caption || "";

      let mediaType = null, fileId = null, fileName = null, fileSize = null, thumbId = null, duration = 0;

      if (msg.photo && msg.photo.length > 0) {
        mediaType = "photo"; fileId = msg.photo[msg.photo.length - 1].file_id; fileSize = msg.photo[msg.photo.length - 1].file_size; fileName = "photo.jpg";
      } else if (msg.video) {
        mediaType = "video"; fileId = msg.video.file_id; fileSize = msg.video.file_size; fileName = msg.video.file_name || "video.mp4"; duration = msg.video.duration || 0;
        const th = msg.video.thumbnail || msg.video.thumb;
        if (th) thumbId = th.file_id;
      } else if (msg.voice) {
        mediaType = "voice"; fileId = msg.voice.file_id; fileSize = msg.voice.file_size; fileName = "voice.ogg"; duration = msg.voice.duration || 0;
      } else if (msg.audio) {
        mediaType = "audio"; fileId = msg.audio.file_id; fileSize = msg.audio.file_size; fileName = msg.audio.file_name || "audio.mp3"; duration = msg.audio.duration || 0;
      } else if (msg.document) {
        mediaType = "document"; fileId = msg.document.file_id; fileSize = msg.document.file_size; fileName = msg.document.file_name || "file";
      }

      if (text || mediaType) {
        // ثبت در جدول پیام‌های استاندارد D1
        await env.DB.prepare(`
          INSERT INTO messages (id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id)
          VALUES (?, ?, ?, 1, ?, ?, ?)
        `).bind(msgId, msg.from.id.toString(), text, timestamp, timestamp, msg.message_id).run();

        if (fileId) {
          await env.DB.prepare(`
            INSERT INTO attachments (id, message_id, media_type, telegram_file_id, file_name, file_size, duration, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).bind(crypto.randomUUID(), msgId, mediaType, fileId, fileName, fileSize, duration, timestamp).run();
        }

        const roomId = env.CHAT_ROOM.idFromName("global_room");
        await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
          method: "POST",
          body: JSON.stringify({
            type: "new_message",
            message: {
              id: msgId, sender_id: msg.from.id.toString(), sender_name: senderName, text, is_from_telegram: 1,
              timestamp, tg_msg_id: msg.message_id, is_read: 0, read_at: null, is_edited: 0, media_type: mediaType,
              media_file_id: fileId, media_file_name: fileName, media_file_size: fileSize, media_thumb_id: thumbId,
              media_duration: duration, reactions: "{}"
            }
          })
        });
      }
    }
  }

  return new Response("OK");
}

// ==========================================
// کلاس بلادرنگ Durable Object (ChatRoom)
// ==========================================
export class ChatRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/broadcast") {
      this.broadcast(await request.json());
      return new Response("OK");
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    try {
      const data = JSON.parse(message);

      if (data.type === "identify") {
        ws.serializeAttachment({ 
          userName: data.userName, 
          userId: data.userId, 
          tgId: data.tgId, 
          isOnline: data.isOnline !== false 
        });
        this.broadcastOnline();
        return;
      }

      if (data.type === "presence") {
        const att = ws.deserializeAttachment() || {};
        att.isOnline = (data.status === "online");
        ws.serializeAttachment(att);
        this.broadcastOnline();
        return;
      }

      if (data.type === "typing") {
        const user = ws.deserializeAttachment();
        if (user) {
          this.broadcast({ type: "typing", userName: user.userName }, ws);
        }
      }
    } catch (e) {}
  }

  async webSocketClose(ws) {
    try {
      const att = ws.deserializeAttachment() || {};
      att.isOnline = false;
      ws.serializeAttachment(att);
    } catch (e) {}
    this.broadcastOnline();
  }

  async webSocketError(ws, error) {
    try {
      const att = ws.deserializeAttachment() || {};
      att.isOnline = false;
      ws.serializeAttachment(att);
    } catch (e) {}
    this.broadcastOnline();
  }

  broadcast(data, excludeWs = null) {
    const str = JSON.stringify(data);
    for (const ws of this.ctx.getWebSockets()) {
      if (ws !== excludeWs) {
        try { ws.send(str); } catch (e) {}
      }
    }
  }

  broadcastOnline() {
    const online = [];
    for (const ws of this.ctx.getWebSockets()) {
      try {
        const att = ws.deserializeAttachment();
        if (att && att.userName && att.isOnline === true) {
          online.push(att.userName);
        }
      } catch (e) {}
    }
    this.broadcast({ type: "online_users", users: Array.from(new Set(online)) });
  }
}
