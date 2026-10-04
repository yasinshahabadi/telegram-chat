import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";
import { emitSyncEvent } from "../telegram/normalizer.js";
import { escapeXml } from "../telegram/telegramClient.js";

const MAX_FILE_SIZE = 20 * 1024 * 1024;
const MAX_FILES_PER_MESSAGE = 10;
const MAX_ALBUM_SIZE = 10; // محدودیت Bot API

const IMAGE_EXTS = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'];
const VIDEO_EXTS = ['mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v'];
const AUDIO_EXTS = ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'];

function detectMediaType(fileName, mimeType, customType) {
  const name = (fileName || '').toLowerCase();
  const ext = name.includes('.') ? name.split('.').pop() : '';
  const mime = (mimeType || '').toLowerCase();

  if (customType === 'voice') return 'voice';
  if (customType === 'photo' || customType === 'image') return 'photo';
  if (customType === 'video') return 'video';
  if (customType === 'audio') return 'audio';
  if (customType === 'document') return 'document';

  if (name.includes('voice_') || name.endsWith('_voice.m4a') || name.endsWith('_voice.ogg')) {
    return 'voice';
  }
  if (IMAGE_EXTS.includes(ext) || mime.startsWith('image/')) return 'photo';
  if (VIDEO_EXTS.includes(ext) || mime.startsWith('video/')) return 'video';
  if (AUDIO_EXTS.includes(ext) || mime.startsWith('audio/')) return 'audio';
  return 'document';
}

function endpointFor(mediaType) {
  switch (mediaType) {
    case 'photo': return { tgEndpoint: 'sendPhoto', fileField: 'photo' };
    case 'video': return { tgEndpoint: 'sendVideo', fileField: 'video' };
    case 'voice': return { tgEndpoint: 'sendVoice', fileField: 'voice' };
    case 'audio': return { tgEndpoint: 'sendAudio', fileField: 'audio' };
    default:      return { tgEndpoint: 'sendDocument', fileField: 'document' };
  }
}

async function uploadOneToTelegram(env, file, mediaType, caption, tgReplyMsgId) {
  const { tgEndpoint, fileField } = endpointFor(mediaType);

  const tgFormData = new FormData();
  tgFormData.append("chat_id", env.TELEGRAM_GROUP_ID);
  if (caption) {
    tgFormData.append("caption", caption);
    tgFormData.append("parse_mode", "HTML");
  }
  tgFormData.append(fileField, file, file.name);
  if (tgReplyMsgId) {
    tgFormData.append("reply_parameters", JSON.stringify({ message_id: tgReplyMsgId }));
  }

  const tgRes = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${tgEndpoint}`, {
    method: "POST",
    body: tgFormData,
  });
  const tgData = await tgRes.json();
  if (!tgData.ok) {
    throw new Error(tgData.description || "خطا در ارسال فایل به تلگرام");
  }

  const resMsg = tgData.result;
  let tgFileId = "";
  let duration = 0;
  if (resMsg.photo && resMsg.photo.length > 0) tgFileId = resMsg.photo[resMsg.photo.length - 1].file_id;
  else if (resMsg.video) { tgFileId = resMsg.video.file_id; duration = resMsg.video.duration || 0; }
  else if (resMsg.voice) { tgFileId = resMsg.voice.file_id; duration = resMsg.voice.duration || 0; }
  else if (resMsg.audio) { tgFileId = resMsg.audio.file_id; duration = resMsg.audio.duration || 0; }
  else if (resMsg.document) tgFileId = resMsg.document.file_id;

  return { telegramMessageId: resMsg.message_id, telegramFileId: tgFileId, duration };
}

/**
 * ✅ Stage 15: ارسال آلبوم با sendMediaGroup.
 *
 * شرایط استفاده:
 *   - حداقل ۲ فایل
 *   - همه photo یا video
 *   - حداکثر ۱۰ فایل
 *
 * اگر شرایط برقرار نباشد، `null` برمی‌گرداند و caller به ارسال جدا fallback می‌کند.
 */
async function uploadMediaGroupToTelegram(env, files, mediaTypes, originalNames, caption, tgReplyMsgId) {
  if (files.length < 2 || files.length > MAX_ALBUM_SIZE) return null;

  const allPhotoOrVideo = mediaTypes.every(t => t === 'photo' || t === 'video');
  if (!allPhotoOrVideo) return null;

  const formData = new FormData();
  formData.append("chat_id", env.TELEGRAM_GROUP_ID);

  const media = [];
  for (let i = 0; i < files.length; i++) {
    const type = mediaTypes[i] === 'video' ? 'video' : 'photo';
    const fieldName = `file${i}`;
    const item = { type, media: `attach://${fieldName}` };
    if (i === 0 && caption) {
      item.caption = caption;
      item.parse_mode = "HTML";
    }
    media.push(item);
    formData.append(fieldName, files[i], originalNames[i]);
  }

  formData.append("media", JSON.stringify(media));
  if (tgReplyMsgId) {
    formData.append("reply_parameters", JSON.stringify({ message_id: tgReplyMsgId }));
  }

  const tgRes = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMediaGroup`, {
    method: "POST",
    body: formData,
  });
  const tgData = await tgRes.json();
  if (!tgData.ok) {
    throw new Error(tgData.description || "خطا در ارسال آلبوم به تلگرام");
  }

  console.log(`[Media] Album sent: ${tgData.result.length} items`);
  return tgData.result.map((msg) => {
    let tgFileId = "";
    let duration = 0;
    if (msg.photo && msg.photo.length > 0) tgFileId = msg.photo[msg.photo.length - 1].file_id;
    else if (msg.video) { tgFileId = msg.video.file_id; duration = msg.video.duration || 0; }
    return { telegramMessageId: msg.message_id, telegramFileId: tgFileId, duration };
  });
}

function attachmentToApi(a) {
  return {
    id: a.id,
    messageId: a.message_id ?? a.messageId,
    mediaType: a.media_type ?? a.mediaType,
    telegramFileId: a.telegram_file_id ?? a.telegramFileId,
    fileName: a.file_name ?? a.fileName,
    fileSize: a.file_size ?? a.fileSize,
    mimeType: a.mime_type ?? a.mimeType,
    duration: a.duration ?? 0,
    createdAt: a.created_at ?? a.createdAt,
  };
}

export async function handleMediaUpload(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const formData = await request.formData();

    let files = formData.getAll("files").filter(f => f instanceof File);
    if (files.length === 0) {
      const single = formData.get("file");
      if (single instanceof File) files = [single];
    }

    if (files.length === 0) {
      return errorResponse("هیچ فایلی برای آپلود یافت نشد.", 400);
    }
    if (files.length > MAX_FILES_PER_MESSAGE) {
      return errorResponse(`حداکثر ${MAX_FILES_PER_MESSAGE} فایل در هر پیام مجاز است.`, 400);
    }

    let totalSize = 0;
    for (const f of files) totalSize += f.size;
    if (totalSize > MAX_FILE_SIZE) {
      return errorResponse("مجموع حجم فایل‌های ارسالی بیش از ۲۰ مگابایت است.", 400);
    }

    const caption = (formData.get("caption") || "").toString().trim();
    const replyToRaw = formData.get("replyTo");
    const clientMessageId = (formData.get("clientMessageId") || "").toString() || null;

    let fileMeta = [];
    const fileMetaRaw = formData.get("fileMeta");
    if (fileMetaRaw) {
      try { fileMeta = JSON.parse(fileMetaRaw); } catch (_) { fileMeta = []; }
    }

    let replyTo = null;
    if (replyToRaw) {
      try { replyTo = JSON.parse(replyToRaw); } catch (_) {}
    }

    if (clientMessageId) {
      const existing = await env.DB.prepare(
        "SELECT id FROM messages WHERE client_message_id = ?"
      ).bind(clientMessageId).first();
      if (existing) {
        const { results: atts } = await env.DB.prepare(
          "SELECT id, message_id, media_type, telegram_file_id, file_name, file_size, mime_type, duration, created_at FROM attachments WHERE message_id = ?"
        ).bind(existing.id).all();
        return jsonResponse({
          ok: true,
          duplicate: true,
          messageId: existing.id,
          clientMessageId,
          attachments: (atts || []).map(attachmentToApi),
        });
      }
    }

    // reply metadata
    let tgReplyMsgId = null;
    let replyToName = null;
    let replyToText = null;
    let replyToMediaType = null;
    let replyToAttachmentId = null;
    let replyToTelegramFileId = null;
    let replyToFileName = null;
    let replyToDuration = null;

    if (replyTo && replyTo.id) {
      const replyRow = await env.DB.prepare(`
        SELECT m.telegram_message_id, m.text, u.full_name AS sender_name,
               a.id AS att_id, a.media_type, a.telegram_file_id,
               a.file_name, a.duration
        FROM messages m
        LEFT JOIN users u ON m.sender_id = u.id
        LEFT JOIN attachments a ON a.message_id = m.id
        WHERE m.id = ?
        ORDER BY a.created_at ASC
        LIMIT 1
      `).bind(replyTo.id).first();

      if (replyRow) {
        tgReplyMsgId = replyRow.telegram_message_id;
        replyToName = replyRow.sender_name || null;
        replyToText = replyRow.text || null;
        replyToMediaType = replyRow.media_type || null;
        replyToAttachmentId = replyRow.att_id || null;
        replyToTelegramFileId = replyRow.telegram_file_id || null;
        replyToFileName = replyRow.file_name || null;
        replyToDuration = replyRow.duration ?? null;
      }
    }

    // media types
    const resolvedTypes = [];
    for (let i = 0; i < files.length; i++) {
      const meta = fileMeta[i] || {};
      resolvedTypes.push(detectMediaType(meta.fileName || files[i].name, files[i].type, meta.mediaType));
    }

    // ✅ Stage 15: تلاش برای ارسال به صورت آلبوم
    let uploadedResults = [];
    try {
      const albumResult = await uploadMediaGroupToTelegram(
        env, files, resolvedTypes, files.map(f => f.name), caption ? `🌐 <b>[Guysgram]</b>\n👤 <b>فرستنده:</b> ${escapeXml(auth.user.fullName)}${caption ? `\n💬 ${escapeXml(caption)}` : ''}` : `🌐 <b>[Guysgram]</b>\n👤 <b>فرستنده:</b> ${escapeXml(auth.user.fullName)}`,
        tgReplyMsgId
      );
      if (albumResult) {
        uploadedResults = albumResult.map((r, i) => ({
          file: files[i],
          mediaType: resolvedTypes[i],
          telegramMessageId: r.telegramMessageId,
          telegramFileId: r.telegramFileId,
          duration: r.duration,
        }));
      }
    } catch (e) {
      console.warn("[Media] Album send failed, falling back:", e.message);
      uploadedResults = [];
    }

    // fallback: ارسال جدا
    if (uploadedResults.length === 0) {
      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const mediaType = resolvedTypes[i];

        let fileCaption = null;
        if (i === 0) {
          fileCaption = `🌐 <b>[Guysgram]</b>\n👤 <b>فرستنده:</b> ${escapeXml(auth.user.fullName)}`;
          if (replyTo && !tgReplyMsgId) {
            fileCaption += `\n↩️ <i>پاسخ به ${escapeXml(replyTo.name)}:</i> «${escapeXml((replyTo.text || "").substring(0, 30))}»`;
          }
          if (caption) fileCaption += `\n💬 ${escapeXml(caption)}`;
        }

        const uploaded = await uploadOneToTelegram(
          env, file, mediaType, fileCaption, i === 0 ? tgReplyMsgId : null
        );

        uploadedResults.push({
          file,
          mediaType,
          telegramMessageId: uploaded.telegramMessageId,
          telegramFileId: uploaded.telegramFileId,
          duration: uploaded.duration,
        });
      }
    }

    const now = Date.now();
    const msgId = crypto.randomUUID();
    const replyId = replyTo ? replyTo.id : null;
    const firstTgMsgId = uploadedResults[0]?.telegramMessageId || null;

    await env.DB.prepare(`
      INSERT INTO messages (id, client_message_id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id, reply_to_message_id)
      VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?)
    `).bind(
      msgId, clientMessageId, auth.user.id, caption, now, now, firstTgMsgId, replyId
    ).run();

    const attachmentRecords = [];
    for (const r of uploadedResults) {
      const attachmentId = crypto.randomUUID();
      await env.DB.prepare(`
        INSERT INTO attachments (id, message_id, media_type, telegram_file_id, file_name, file_size, mime_type, duration, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(
        attachmentId, msgId, r.mediaType, r.telegramFileId,
        r.file.name, r.file.size, r.file.type || "application/octet-stream",
        r.duration, now
      ).run();

      attachmentRecords.push({
        id: attachmentId,
        messageId: msgId,
        mediaType: r.mediaType,
        telegramFileId: r.telegramFileId,
        fileName: r.file.name,
        fileSize: r.file.size,
        mimeType: r.file.type || "application/octet-stream",
        duration: r.duration,
        createdAt: now,
      });
    }

    const normalizedMessage = {
      id: msgId,
      clientMessageId,
      senderId: auth.user.id,
      senderName: auth.user.fullName,
      text: caption,
      isFromTelegram: false,
      createdAt: now,
      telegramMessageId: firstTgMsgId,
      replyToId: replyId,
      replyToName,
      replyToText,
      replyToMediaType,
      replyToAttachmentId,
      replyToTelegramFileId,
      replyToFileName,
      replyToDuration,
      attachments: attachmentRecords,
    };

    await emitSyncEvent(env.DB, "message_created", msgId, normalizedMessage);

    try {
      const roomId = env.CHAT_ROOM.idFromName("global_room");
      await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
        method: "POST",
        body: JSON.stringify({ type: "new_message", message: normalizedMessage }),
      });
    } catch (_) {}

    try {
      const { dispatchNewMessagePush } = await import("../notifications/fcmService.js");
      await dispatchNewMessagePush(env, normalizedMessage, auth.user.id);
    } catch (_) {}

    return jsonResponse({
      ok: true,
      messageId: msgId,
      clientMessageId,
      attachments: attachmentRecords,
    });
  } catch (err) {
    return errorResponse("خطا در پردازش رسانه.", 500, "UPLOAD_ERROR", err.message);
  }
}

export async function handleMediaDownload(request, env) {
  const url = new URL(request.url);
  const fileId = url.searchParams.get("fileId") || url.searchParams.get("key");
  const isDownload = url.searchParams.get("download") === "1";

  if (!fileId) return errorResponse("شناسه فایل الزامی است.", 400);

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
        headers: resHeaders,
      });
    }
  } catch (_) {}

  return errorResponse("فایل در فضای ابری تلگرام یافت نشد.", 404);
}