import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";
import { emitSyncEvent } from "../telegram/normalizer.js";
import { escapeXml } from "../telegram/telegramClient.js";

const MAX_FILE_SIZE = 20 * 1024 * 1024; // حداکثر ۲۰ مگابایت

/**
 * آپلود فایل چندرسانه‌ای، ذخیره در R2 و ثبت متادیتا در D1
 * POST /api/media/upload
 */
export async function handleMediaUpload(request, env) {
  // ۱. احراز هویت الزامی کلاینت طبق اصل Zero-Trust
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

    // تشخیص نوع رسانه و تنظیم پسوند
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

    const fileId = crypto.randomUUID();
    const fileExt = file.name.includes(".") ? file.name.split(".").pop().toLowerCase() : "bin";
    const r2Key = `media/${fileId}.${fileExt}`;

    // ۲. استریم مستقیم به باکت ابری R2 کلودفلر (بدون مصرف حافظه رم ورکر)
    if (env.MEDIA_BUCKET) {
      await env.MEDIA_BUCKET.put(r2Key, file.stream(), {
        httpMetadata: {
          contentType: file.type || "application/octet-stream"
        },
        customMetadata: {
          originalName: encodeURIComponent(file.name),
          uploaderId: auth.user.id
        }
      });
    }

    // ۳. ارسال هم‌زمان به سوپرگروه تلگرام جهت حفظ ارتباط دوسویه
    let tgMsgId = null;
    let tgFileId = null;
    let duration = 0;

    try {
      const tgFormData = new FormData();
      tgFormData.append("chat_id", env.TELEGRAM_GROUP_ID);

      let tgCaption = `🌐 <b>[برنامه اندروید]</b>\n👤 <b>فرستنده:</b> ${escapeXml(auth.user.fullName)}`;
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
      if (tgData.ok && tgData.result) {
        tgMsgId = tgData.result.message_id;
        const resMsg = tgData.result;
        if (resMsg.photo && resMsg.photo.length > 0) tgFileId = resMsg.photo[resMsg.photo.length - 1].file_id;
        else if (resMsg.video) { tgFileId = resMsg.video.file_id; duration = resMsg.video.duration || 0; }
        else if (resMsg.voice) { tgFileId = resMsg.voice.file_id; duration = resMsg.voice.duration || 0; }
        else if (resMsg.audio) { tgFileId = resMsg.audio.file_id; duration = resMsg.audio.duration || 0; }
        else if (resMsg.document) tgFileId = resMsg.document.file_id;
      }
    } catch (tgErr) {}

    const now = Date.now();
    const msgId = crypto.randomUUID();
    const replyId = replyTo ? replyTo.id : null;

    // ۴. درج رکورد پیام در جدول messages
    await env.DB.prepare(`
      INSERT INTO messages (
        id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id, reply_to_message_id
      )
      VALUES (?, ?, ?, 0, ?, ?, ?, ?)
    `).bind(msgId, auth.user.id, caption, now, now, tgMsgId, replyId).run();

    // ۵. درج اطلاعات فایل در جدول نرمال attachments
    const attachmentId = crypto.randomUUID();
    const attachmentData = {
      id: attachmentId,
      messageId: msgId,
      mediaType,
      r2Key,
      telegramFileId: tgFileId,
      fileName: file.name,
      fileSize: file.size,
      mimeType: file.type || "application/octet-stream",
      duration,
      createdAt: now
    };

    await env.DB.prepare(`
      INSERT INTO attachments (
        id, message_id, media_type, r2_key, telegram_file_id, file_name, file_size, mime_type, duration, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      attachmentId, msgId, mediaType, r2Key, tgFileId, file.name, file.size, file.type, duration, now
    ).run();

    const normalizedMessage = {
      id: msgId,
      senderId: auth.user.id,
      senderName: auth.user.fullName,
      text: caption,
      isFromTelegram: false,
      createdAt: now,
      telegramMessageId: tgMsgId,
      replyToId: replyId,
      attachment: attachmentData
    };

    // ۶. ثبت رویداد ترتیبی در sync_events
    await emitSyncEvent(env.DB, "message_created", msgId, normalizedMessage);

    // ۷. برودکست پیام به اتاق بلادرنگ سوکت
    try {
      const roomId = env.CHAT_ROOM.idFromName("global_room");
      await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
        method: "POST",
        body: JSON.stringify({
          type: "new_message",
          message: normalizedMessage
        })
      });
    } catch (brErr) {}

    return jsonResponse({
      ok: true,
      messageId: msgId,
      r2Key,
      mediaUrl: `/api/media/file?key=${encodeURIComponent(r2Key)}`
    });
  } catch (err) {
    return errorResponse("خطا در آپلود رسانه.", 500, "UPLOAD_ERROR", err.message);
  }
}

/**
 * دریافت و استریم فایل از R2 با پشتیبانی از HTTP Range Requests
 * GET /api/media/file?key=media/...
 */
export async function handleMediaDownload(request, env) {
  const url = new URL(request.url);
  const r2Key = url.searchParams.get("key");
  const telegramFileId = url.searchParams.get("fileId");
  const isDownload = url.searchParams.get("download") === "1";

  // ۱. بررسی واکشی مستقیم از باکت R2
  if (r2Key && env.MEDIA_BUCKET) {
    try {
      const rangeHeader = request.headers.get("Range") || request.headers.get("range");
      
      // فراخوانی شیء از R2 با پشتیبانی از بازه بایت‌ها (Range)
      const object = await env.MEDIA_BUCKET.get(r2Key, {
        range: rangeHeader ? request.headers : undefined
      });

      if (object) {
        const headers = new Headers();
        object.writeHttpMetadata(headers);
        headers.set("etag", object.httpEtag);
        headers.set("Accept-Ranges", "bytes");
        headers.set("Cache-Control", "public, max-age=31536000, immutable");

        const origName = object.customMetadata?.originalName 
          ? decodeURIComponent(object.customMetadata.originalName)
          : r2Key.split("/").pop();

        headers.set(
          "Content-Disposition",
          `${isDownload ? "attachment" : "inline"}; filename="${encodeURIComponent(origName)}"`
        );

        const status = object.range ? 206 : 200;
        return new Response(object.body, {
          status,
          headers
        });
      }
    } catch (r2Err) {}
  }

  // ۲. در صورتی که فایل هنوز فقط روی تلگرام باشد (فال‌بک موقت برای فایل‌های گذشته)
  if (telegramFileId) {
    return await proxyTelegramFile(request, env, telegramFileId, isDownload);
  }

  return errorResponse("فایل در باکت ذخیره‌سازی یافت نشد.", 404);
}

// تابع کمکی پروکسی استریم تلگرام برای پیام‌های قدیمی
async function proxyTelegramFile(request, env, fileId, isDownload) {
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
      resHeaders.set("Cache-Control", "public, max-age=604800, immutable");
      resHeaders.set("Accept-Ranges", "bytes");
      resHeaders.set("Content-Disposition", isDownload ? "attachment" : "inline");

      return new Response(mediaRes.body, {
        status: mediaRes.status,
        headers: resHeaders
      });
    }
  } catch (e) {}

  return errorResponse("فایل در سرور تلگرام یافت نشد.", 404);
}
