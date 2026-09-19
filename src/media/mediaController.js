import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";
import { emitSyncEvent } from "../telegram/normalizer.js";
import { escapeXml } from "../telegram/telegramClient.js";

const MAX_FILE_SIZE = 20 * 1024 * 1024; // حداکثر ۲۰ مگابایت استاندارد تلگرام

/**
 * آپلود فایل چندرسانه‌ای به فضای ابری تلگرام و ثبت متادیتا در D1
 * POST /api/media/upload
 */
export async function handleMediaUpload(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const formData = await request.formData();
    const file = formData.get("file");
    const caption = (formData.get("caption") || "").trim();
    const replyToRaw = formData.get("replyTo");
    const customType = formData.get("mediaType");

    if (!file || !(file instanceof File) || file.size > MAX_FILE_SIZE) {
      return errorResponse("فایل ارسالی نامعتبر است یا حجم آن بیش از ۲۰ مگابایت است.", 400);
    }

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

    // ۱. ارسال مستقیم فایل به سوپرگروه تلگرام جهت ذخیره‌سازی ابری رایگان و دائمی
    const tgFormData = new FormData();
    tgFormData.append("chat_id", env.TELEGRAM_GROUP_ID);

    let tgCaption = `🌐 <b>[Guysgram]</b>\n👤 <b>فرستنده:</b> ${escapeXml(auth.user.fullName)}`;
    if (replyTo && !replyTo.tgMsgId) tgCaption += `\n↩️ <i>پاسخ به ${escapeXml(replyTo.name)}:</i> «${escapeXml((replyTo.text || "").substring(0, 30))}»`;
    if (caption) tgCaption += `\n💬 ${escapeXml(caption)}`;

    tgFormData.append("caption", tgCaption);
    tgFormData.append("parse_mode", "HTML");
    tgFormData.append(fileField, file, file.name);

    if (replyTo && replyTo.tgMsgId) {
      tgFormData.append("reply_parameters", JSON.stringify({ message_id: replyTo.tgMsgId }));
    }

    const tgRes = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${tgEndpoint}`, {
      method: "POST",
      body: tgFormData
    });
    const tgData = await tgRes.json();
    if (!tgData.ok) {
      return errorResponse(tgData.description || "خطا در ارسال فایل به تلگرام", 500);
    }

    let tgFileId = "";
    let duration = 0;
    const resMsg = tgData.result;
    
    if (resMsg.photo && resMsg.photo.length > 0) tgFileId = resMsg.photo[resMsg.photo.length - 1].file_id;
    else if (resMsg.video) { tgFileId = resMsg.video.file_id; duration = resMsg.video.duration || 0; }
    else if (resMsg.voice) { tgFileId = resMsg.voice.file_id; duration = resMsg.voice.duration || 0; }
    else if (resMsg.audio) { tgFileId = resMsg.audio.file_id; duration = resMsg.audio.duration || 0; }
    else if (resMsg.document) tgFileId = resMsg.document.file_id;

    const now = Date.now();
    const msgId = crypto.randomUUID();
    const replyId = replyTo ? replyTo.id : null;

    // ۲. ثبت رکورد پیام در جدول messages
    await env.DB.prepare(`
      INSERT INTO messages (
        id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id, reply_to_message_id
      )
      VALUES (?, ?, ?, 0, ?, ?, ?, ?)
    `).bind(msgId, auth.user.id, caption, now, now, resMsg.message_id, replyId).run();

    // ۳. ثبت مشخصات فایل در جدول attachments با کلید تلگرام
    const attachmentId = crypto.randomUUID();
    const attachmentData = {
      id: attachmentId,
      messageId: msgId,
      mediaType,
      telegramFileId: tgFileId,
      fileName: file.name,
      fileSize: file.size,
      mimeType: file.type || "application/octet-stream",
      duration,
      createdAt: now
    };

    await env.DB.prepare(`
      INSERT INTO attachments (
        id, message_id, media_type, telegram_file_id, file_name, file_size, mime_type, duration, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      attachmentId, msgId, mediaType, tgFileId, file.name, file.size, file.type, duration, now
    ).run();

    const normalizedMessage = {
      id: msgId,
      senderId: auth.user.id,
      senderName: auth.user.fullName,
      text: caption,
      isFromTelegram: false,
      createdAt: now,
      telegramMessageId: resMsg.message_id,
      replyToId: replyId,
      attachment: attachmentData
    };

    // ۴. ثبت رویداد در جدول sync_events
    await emitSyncEvent(env.DB, "message_created", msgId, normalizedMessage);

    // ۵. برودکست به سوکت
    try {
      const roomId = env.CHAT_ROOM.idFromName("global_room");
      await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
        method: "POST",
        body: JSON.stringify({
          type: "new_message",
          message: normalizedMessage
        })
      });
    } catch (_) {}

    return jsonResponse({
      ok: true,
      messageId: msgId,
      fileId: tgFileId,
      mediaUrl: `/api/media/file?fileId=${encodeURIComponent(tgFileId)}`
    });
  } catch (err) {
    return errorResponse("خطا در پردازش رسانه.", 500, "UPLOAD_ERROR", err.message);
  }
}

/**
 * دریافت و استریم فایل از تلگرام با پشتیبانی از کش و Range Requests
 * GET /api/media/file?fileId=...
 */
export async function handleMediaDownload(request, env) {
  const url = new URL(request.url);
  const fileId = url.searchParams.get("fileId") || url.searchParams.get("key");
  const isDownload = url.searchParams.get("download") === "1";

  if (!fileId) {
    return errorResponse("شناسه فایل الزامی است.", 400);
  }

  try {
    const fileRes = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${fileId}`
    );
    const fileData = await fileRes.json();

    if (fileData.ok && fileData.result.file_path) {
      const filePath = fileData.result.file_path;
      const mediaRes = await fetch(
        `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${filePath}`,
        { headers: request.headers }
      );

      const resHeaders = new Headers(mediaRes.headers);
      resHeaders.set("Cache-Control", "public, max-age=31536000, immutable");
      resHeaders.set("Accept-Ranges", "bytes");
      resHeaders.set("Content-Disposition", isDownload ? "attachment" : "inline");

      return new Response(mediaRes.body, {
        status: mediaRes.status,
        headers: resHeaders
      });
    }
  } catch (_) {}

  return errorResponse("فایل در فضای ابری تلگرام یافت نشد.", 404);
}
