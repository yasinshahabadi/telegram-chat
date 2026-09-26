/**
 * Telegram Event Normalizer & D1 Ingestion Engine
 * Translates raw Telegram updates into normalized database entities and sync events.
 */

export async function ensureTelegramUser(db, fromUser) {
  if (!fromUser || !fromUser.id) return null;
  const tgId = fromUser.id.toString();
  const now = Date.now();

  const existing = await db.prepare("SELECT id FROM users WHERE telegram_id = ?").bind(tgId).first();
  if (existing) {
    return existing.id;
  }

  const newUserId = crypto.randomUUID();
  const fullName = `${fromUser.first_name || ""} ${fromUser.last_name || ""}`.trim() || "Telegram User";
  const username = fromUser.username || "ندارد";

  await db.prepare(`
    INSERT OR IGNORE INTO users (id, telegram_id, full_name, username, is_approved, is_admin, created_at, updated_at)
    VALUES (?, ?, ?, ?, 1, 0, ?, ?)
  `).bind(newUserId, tgId, fullName, username, now, now).run();

  return newUserId;
}

export async function emitSyncEvent(db, eventType, entityId, payload) {
  try {
    const result = await db.prepare(`
      INSERT INTO sync_events (event_type, entity_id, payload_json, created_at)
      VALUES (?, ?, ?, ?)
    `).bind(eventType, entityId, JSON.stringify(payload), Date.now()).run();

    return result.meta?.last_row_id || null;
  } catch (err) {
    return null;
  }
}

export async function normalizeIncomingTelegramMessage(db, msg) {
  const msgId = crypto.randomUUID();
  const senderId = await ensureTelegramUser(db, msg.from);
  const senderName = `${msg.from.first_name || ""} ${msg.from.last_name || ""}`.trim() || "Telegram User";
  const timestamp = Date.now();
  const text = msg.text || msg.caption || "";

  // ✅ کشف اطلاعات کامل ریپلای (id + name + text) از دیتابیس محلی سرور
  let replyToId = null;
  let replyToName = null;
  let replyToText = null;
  if (msg.reply_to_message) {
    const parentMsg = await db.prepare(`
      SELECT m.id, m.text, u.full_name AS sender_name
      FROM messages m
      LEFT JOIN users u ON m.sender_id = u.id
      WHERE m.telegram_message_id = ?
    `).bind(msg.reply_to_message.message_id).first();
    if (parentMsg) {
      replyToId = parentMsg.id;
      replyToName = parentMsg.sender_name || null;
      replyToText = parentMsg.text || null;
    }
  }

  let mediaType = null, fileId = null, fileName = null, fileSize = null, thumbId = null, duration = 0;

  if (msg.photo && msg.photo.length > 0) {
    mediaType = "photo";
    const bestPhoto = msg.photo[msg.photo.length - 1];
    fileId = bestPhoto.file_id;
    fileSize = bestPhoto.file_size;
    fileName = "photo.jpg";
  } else if (msg.video) {
    mediaType = "video";
    fileId = msg.video.file_id;
    fileSize = msg.video.file_size;
    fileName = msg.video.file_name || "video.mp4";
    duration = msg.video.duration || 0;
    const th = msg.video.thumbnail || msg.video.thumb;
    if (th) thumbId = th.file_id;
  } else if (msg.voice) {
    mediaType = "voice";
    fileId = msg.voice.file_id;
    fileSize = msg.voice.file_size;
    fileName = "voice.ogg";
    duration = msg.voice.duration || 0;
  } else if (msg.audio) {
    mediaType = "audio";
    fileId = msg.audio.file_id;
    fileSize = msg.audio.file_size;
    fileName = msg.audio.file_name || "audio.mp3";
    duration = msg.audio.duration || 0;
  } else if (msg.document) {
    mediaType = "document";
    fileId = msg.document.file_id;
    fileSize = msg.document.file_size;
    fileName = msg.document.file_name || "file";
  }

  await db.prepare(`
    INSERT INTO messages (
      id, sender_id, text, is_from_telegram, created_at, updated_at, telegram_message_id, reply_to_message_id
    )
    VALUES (?, ?, ?, 1, ?, ?, ?, ?)
  `).bind(msgId, senderId, text, timestamp, timestamp, msg.message_id, replyToId).run();

  let attachmentRecord = null;
  if (fileId) {
    const attachmentId = crypto.randomUUID();
    attachmentRecord = {
      id: attachmentId,
      messageId: msgId,
      mediaType,
      telegramFileId: fileId,
      fileName,
      fileSize,
      duration,
      thumbId
    };

    await db.prepare(`
      INSERT INTO attachments (
        id, message_id, media_type, telegram_file_id, file_name, file_size, duration, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(attachmentId, msgId, mediaType, fileId, fileName, fileSize, duration, timestamp).run();
  }

  const normalizedMessage = {
    id: msgId,
    senderId,
    senderName,
    text,
    isFromTelegram: true,
    createdAt: timestamp,
    telegramMessageId: msg.message_id,
    replyToId,
    replyToName,
    replyToText,
    attachment: attachmentRecord
  };

  const cursor = await emitSyncEvent(db, "message_created", msgId, normalizedMessage);

  return {
    message: normalizedMessage,
    cursor
  };
}

export async function normalizeTelegramEdit(db, editMsg) {
  const newText = editMsg.text || editMsg.caption || "";
  const now = Date.now();

  const msgRow = await db.prepare(
    "SELECT id FROM messages WHERE telegram_message_id = ?"
  ).bind(editMsg.message_id).first();

  if (!msgRow) return null;

  await db.prepare(`
    UPDATE messages 
    SET text = ?, is_edited = 1, updated_at = ? 
    WHERE id = ?
  `).bind(newText, now, msgRow.id).run();

  const payload = {
    messageId: msgRow.id,
    telegramMessageId: editMsg.message_id,
    text: newText,
    updatedAt: now
  };

  const cursor = await emitSyncEvent(db, "message_edited", msgRow.id, payload);

  return { payload, cursor };
}

export async function normalizeTelegramReaction(db, reactionUpdate) {
  const tgMsgId = reactionUpdate.message_id;
  const tgUserId = reactionUpdate.user?.id ? reactionUpdate.user.id.toString() : "anonymous";
  const now = Date.now();

  const msgRow = await db.prepare(
    "SELECT id FROM messages WHERE telegram_message_id = ?"
  ).bind(tgMsgId).first();

  if (!msgRow) return null;

  await db.prepare(
    "DELETE FROM reactions WHERE message_id = ? AND telegram_user_id = ?"
  ).bind(msgRow.id, tgUserId).run();

  const newEmojis = [];
  if (reactionUpdate.new_reaction && Array.isArray(reactionUpdate.new_reaction)) {
    for (const r of reactionUpdate.new_reaction) {
      if (r.type === "emoji" && r.emoji) {
        newEmojis.push(r.emoji);
        await db.prepare(`
          INSERT OR IGNORE INTO reactions (id, message_id, user_id, telegram_user_id, emoji, created_at)
          VALUES (?, ?, NULL, ?, ?, ?)
        `).bind(crypto.randomUUID(), msgRow.id, tgUserId, r.emoji, now).run();
      }
    }
  }

  const { results: allReactions } = await db.prepare(`
    SELECT emoji, COUNT(*) AS count 
    FROM reactions 
    WHERE message_id = ? 
    GROUP BY emoji
  `).bind(msgRow.id).all();

  const payload = {
    messageId: msgRow.id,
    telegramMessageId: tgMsgId,
    reactions: allReactions || []
  };

  const cursor = await emitSyncEvent(db, "reaction_updated", msgRow.id, payload);

  return { payload, cursor };
}

export async function normalizeTelegramPin(db, pinnedTgId) {
  const now = Date.now();

  const msgRow = await db.prepare(
    "SELECT id FROM messages WHERE telegram_message_id = ?"
  ).bind(pinnedTgId).first();

  if (!msgRow) return null;

  await db.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();
  await db.prepare("UPDATE messages SET is_pinned = 1, updated_at = ? WHERE id = ?").bind(now, msgRow.id).run();

  const payload = {
    messageId: msgRow.id,
    telegramMessageId: pinnedTgId,
    isPinned: true,
    pinnedAt: now
  };

  const cursor = await emitSyncEvent(db, "message_pinned", msgRow.id, payload);

  return { payload, cursor };
}