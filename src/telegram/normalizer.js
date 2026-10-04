/**
 * Telegram Event Normalizer & D1 Ingestion Engine
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

/**
 * استخراج forward metadata — Bot API 7+ و legacy.
 */
export function extractForwardInfo(msg) {
  if (msg.forward_origin) {
    const origin = msg.forward_origin;
    const type = origin.type || null;

    if (type === 'channel' || type === 'chat') {
      const chat = origin.chat || {};
      return {
        type,
        chatId: chat.id != null ? chat.id.toString() : null,
        chatUsername: chat.username || null,
        chatTitle: chat.title || null,
        messageId: origin.message_id != null ? origin.message_id : null,
      };
    }

    if (type === 'user') {
      const user = origin.sender_user || {};
      const name = `${user.first_name || ""} ${user.last_name || ""}`.trim() || 'کاربر';
      return {
        type: 'user',
        chatId: user.id != null ? user.id.toString() : null,
        chatUsername: user.username || null,
        chatTitle: name,
        messageId: null,
      };
    }

    if (type === 'hidden_user') {
      return {
        type: 'hidden_user',
        chatId: null,
        chatUsername: null,
        chatTitle: origin.sender_user_name || 'کاربر',
        messageId: null,
      };
    }
  }

  // ─── Legacy fallback ───
  if (msg.forward_from_chat) {
    const chat = msg.forward_from_chat;
    return {
      type: chat.type === 'channel' ? 'channel' : 'chat',
      chatId: chat.id != null ? chat.id.toString() : null,
      chatUsername: chat.username || null,
      chatTitle: chat.title || null,
      messageId: msg.forward_from_message_id != null ? msg.forward_from_message_id : null,
    };
  }

  if (msg.forward_from) {
    const user = msg.forward_from;
    const name = `${user.first_name || ""} ${user.last_name || ""}`.trim() || 'کاربر';
    return {
      type: 'user',
      chatId: user.id != null ? user.id.toString() : null,
      chatUsername: user.username || null,
      chatTitle: name,
      messageId: null,
    };
  }

  if (msg.forward_sender_name) {
    return {
      type: 'hidden_user',
      chatId: null,
      chatUsername: null,
      chatTitle: msg.forward_sender_name,
      messageId: null,
    };
  }

  return null;
}

/**
 * استخراج فایل از یک پیام (اولین مدیای موجود).
 */
function extractMedia(msg) {
  if (msg.photo && msg.photo.length > 0) {
    const best = msg.photo[msg.photo.length - 1];
    return { mediaType: 'photo', fileId: best.file_id, fileSize: best.file_size, fileName: 'photo.jpg', duration: 0 };
  }
  if (msg.video) {
    return { mediaType: 'video', fileId: msg.video.file_id, fileSize: msg.video.file_size,
             fileName: msg.video.file_name || 'video.mp4', duration: msg.video.duration || 0 };
  }
  if (msg.voice) {
    return { mediaType: 'voice', fileId: msg.voice.file_id, fileSize: msg.voice.file_size,
             fileName: 'voice.ogg', duration: msg.voice.duration || 0 };
  }
  if (msg.audio) {
    return { mediaType: 'audio', fileId: msg.audio.file_id, fileSize: msg.audio.file_size,
             fileName: msg.audio.file_name || 'audio.mp3', duration: msg.audio.duration || 0 };
  }
  if (msg.document) {
    return { mediaType: 'document', fileId: msg.document.file_id, fileSize: msg.document.file_size,
             fileName: msg.document.file_name || 'file', duration: 0 };
  }
  return null;
}

/**
 * ✅ Stage 17: استخراج entities از پیام و تبدیل به JSON string برای ذخیره در DB.
 *
 * Bot API: `msg.entities` برای متن، `msg.caption_entities` برای کپشن مدیا.
 */
function extractEntitiesJson(msg) {
  const entities = msg.entities || msg.caption_entities || null;
  if (!entities || !Array.isArray(entities) || entities.length === 0) return null;
  try {
    return JSON.stringify(entities);
  } catch (_) {
    return null;
  }
}

async function resolveReplyInfo(db, msg) {
  if (!msg.reply_to_message) return { replyToId: null };
  const parentRow = await db.prepare(`
    SELECT m.id, m.text, u.full_name AS sender_name,
           a.id AS att_id, a.media_type, a.telegram_file_id,
           a.file_name, a.duration
    FROM messages m
    LEFT JOIN users u ON m.sender_id = u.id
    LEFT JOIN attachments a ON a.message_id = m.id
    WHERE m.telegram_message_id = ?
    ORDER BY a.created_at ASC
    LIMIT 1
  `).bind(msg.reply_to_message.message_id).first();

  if (!parentRow) return { replyToId: null };
  return {
    replyToId: parentRow.id,
    replyToName: parentRow.sender_name || null,
    replyToText: parentRow.text || null,
    replyToMediaType: parentRow.media_type || null,
    replyToAttachmentId: parentRow.att_id || null,
    replyToTelegramFileId: parentRow.telegram_file_id || null,
    replyToFileName: parentRow.file_name || null,
    replyToDuration: parentRow.duration ?? null,
  };
}

async function insertAttachment(db, messageId, media, timestamp) {
  if (!media) return null;
  const attachmentId = crypto.randomUUID();
  await db.prepare(`
    INSERT INTO attachments (
      id, message_id, media_type, telegram_file_id, file_name, file_size, duration, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(attachmentId, messageId, media.mediaType, media.fileId,
          media.fileName, media.fileSize, media.duration, timestamp).run();
  return attachmentId;
}

/**
 * پیام تک‌رسانه یا متنی incoming.
 * شامل: forward metadata + text entities (Stage 17).
 */
export async function normalizeIncomingTelegramMessage(db, msg) {
  const msgId = crypto.randomUUID();
  const senderId = await ensureTelegramUser(db, msg.from);
  const senderName = `${msg.from.first_name || ""} ${msg.from.last_name || ""}`.trim() || "Telegram User";
  const timestamp = Date.now();
  const text = msg.text || msg.caption || "";

  const forward = extractForwardInfo(msg);
  const replyInfo = await resolveReplyInfo(db, msg);

  // ✅ Stage 17: entities
  const textEntitiesJson = extractEntitiesJson(msg);

  await db.prepare(`
    INSERT INTO messages (
      id, sender_id, text, is_from_telegram, created_at, updated_at,
      telegram_message_id, reply_to_message_id,
      forward_from_type, forward_from_chat_id, forward_from_chat_username,
      forward_from_chat_title, forward_from_message_id,
      telegram_media_group_id, text_entities
    )
    VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    msgId, senderId, text, timestamp, timestamp,
    msg.message_id, replyInfo.replyToId,
    forward?.type ?? null, forward?.chatId ?? null, forward?.chatUsername ?? null,
    forward?.chatTitle ?? null, forward?.messageId ?? null,
    msg.media_group_id || null,
    textEntitiesJson,
  ).run();

  const media = extractMedia(msg);
  let attachmentRecord = null;
  if (media) {
    const attachmentId = await insertAttachment(db, msgId, media, timestamp);
    attachmentRecord = {
      id: attachmentId,
      messageId: msgId,
      mediaType: media.mediaType,
      telegramFileId: media.fileId,
      fileName: media.fileName,
      fileSize: media.fileSize,
      duration: media.duration,
    };
  }

  const normalizedMessage = {
    id: msgId,
    senderId,
    senderName,
    text,
    isFromTelegram: true,
    createdAt: timestamp,
    telegramMessageId: msg.message_id,
    replyToId: replyInfo.replyToId,
    replyToName: replyInfo.replyToName ?? null,
    replyToText: replyInfo.replyToText ?? null,
    replyToMediaType: replyInfo.replyToMediaType ?? null,
    replyToAttachmentId: replyInfo.replyToAttachmentId ?? null,
    replyToTelegramFileId: replyInfo.replyToTelegramFileId ?? null,
    replyToFileName: replyInfo.replyToFileName ?? null,
    replyToDuration: replyInfo.replyToDuration ?? null,
    attachment: attachmentRecord,
    forwardFromType: forward?.type ?? null,
    forwardFromChatId: forward?.chatId ?? null,
    forwardFromChatUsername: forward?.chatUsername ?? null,
    forwardFromChatTitle: forward?.chatTitle ?? null,
    forwardFromMessageId: forward?.messageId ?? null,
    // ✅ Stage 17
    textEntities: textEntitiesJson ? JSON.parse(textEntitiesJson) : null,
  };

  const cursor = await emitSyncEvent(db, "message_created", msgId, normalizedMessage);

  return { message: normalizedMessage, cursor };
}

// ═══════════════════════════════════════════════════════════════
//  Media Group Buffering (Stage 14)
// ═══════════════════════════════════════════════════════════════

/**
 * پردازش یک item از media group (album).
 *
 * - اولین item: ساخت message + اولین attachment + ردیف pending_media_groups
 * - item های بعدی: افزودن attachment به همان message
 */
export async function normalizeMediaGroupItem(db, msg) {
  const groupId = msg.media_group_id;
  const now = Date.now();

  if (!groupId) {
    return { isFirst: false, messageId: null, groupId: null };
  }

  // ── item بعدی ──
  const existing = await db.prepare(
    "SELECT message_id, sender_id, sender_name FROM pending_media_groups WHERE group_id = ?"
  ).bind(groupId).first();

  if (existing) {
    const media = extractMedia(msg);
    if (media) {
      await insertAttachment(db, existing.message_id, media, now);
    }
    await db.prepare(
      "UPDATE pending_media_groups SET updated_at = ? WHERE group_id = ?"
    ).bind(now, groupId).run();
    return { isFirst: false, messageId: existing.message_id, groupId };
  }

  // ── اولین item ──
  const msgId = crypto.randomUUID();
  const senderId = await ensureTelegramUser(db, msg.from);
  const senderName = `${msg.from.first_name || ""} ${msg.from.last_name || ""}`.trim() || "Telegram User";
  const text = msg.caption || "";
  const forward = extractForwardInfo(msg);
  const replyInfo = await resolveReplyInfo(db, msg);

  // ✅ Stage 17: entities (از caption_entities)
  const textEntitiesJson = extractEntitiesJson(msg);

  await db.prepare(`
    INSERT INTO messages (
      id, sender_id, text, is_from_telegram, created_at, updated_at,
      telegram_message_id, reply_to_message_id,
      forward_from_type, forward_from_chat_id, forward_from_chat_username,
      forward_from_chat_title, forward_from_message_id,
      telegram_media_group_id, text_entities
    )
    VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    msgId, senderId, text, now, now,
    msg.message_id, replyInfo.replyToId,
    forward?.type ?? null, forward?.chatId ?? null, forward?.chatUsername ?? null,
    forward?.chatTitle ?? null, forward?.messageId ?? null,
    groupId,
    textEntitiesJson,
  ).run();

  const media = extractMedia(msg);
  if (media) {
    await insertAttachment(db, msgId, media, now);
  }

  await db.prepare(`
    INSERT OR IGNORE INTO pending_media_groups
      (group_id, message_id, sender_id, sender_name, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `).bind(groupId, msgId, senderId, senderName, now, now).run();

  console.log(`[Normalizer] Media group started: groupId=${groupId} msgId=${msgId}`);
  return { isFirst: true, messageId: msgId, senderId, senderName, groupId };
}

/**
 * نهایی‌سازی media group:
 *   - خواندن message + همه attachments + entities
 *   - ساخت payload کامل
 *   - emitSyncEvent
 *   - حذف ردیف pending
 */
export async function finalizeMediaGroup(db, groupId) {
  const entry = await db.prepare(
    "SELECT message_id, sender_id, sender_name FROM pending_media_groups WHERE group_id = ?"
  ).bind(groupId).first();

  if (!entry) return null;

  const msgRow = await db.prepare(
    "SELECT * FROM messages WHERE id = ?"
  ).bind(entry.message_id).first();

  if (!msgRow) {
    await db.prepare("DELETE FROM pending_media_groups WHERE group_id = ?")
      .bind(groupId).run();
    return null;
  }

  const { results: attachments } = await db.prepare(
    "SELECT * FROM attachments WHERE message_id = ? ORDER BY created_at ASC"
  ).bind(entry.message_id).all();

  let replyToName = null, replyToText = null, replyToMediaType = null;
  let replyToAttachmentId = null, replyToTelegramFileId = null;
  let replyToFileName = null, replyToDuration = null;

  if (msgRow.reply_to_message_id) {
    const replyRow = await db.prepare(`
      SELECT m.text, u.full_name AS sender_name,
             a.id AS att_id, a.media_type, a.telegram_file_id,
             a.file_name, a.duration
      FROM messages m
      LEFT JOIN users u ON m.sender_id = u.id
      LEFT JOIN attachments a ON a.message_id = m.id
      WHERE m.id = ?
      ORDER BY a.created_at ASC LIMIT 1
    `).bind(msgRow.reply_to_message_id).first();

    if (replyRow) {
      replyToName = replyRow.sender_name || null;
      replyToText = replyRow.text || null;
      replyToMediaType = replyRow.media_type || null;
      replyToAttachmentId = replyRow.att_id || null;
      replyToTelegramFileId = replyRow.telegram_file_id || null;
      replyToFileName = replyRow.file_name || null;
      replyToDuration = replyRow.duration ?? null;
    }
  }

  // ✅ Stage 17: parse entities از DB
  let textEntities = null;
  if (msgRow.text_entities) {
    try {
      textEntities = JSON.parse(msgRow.text_entities);
    } catch (_) {
      textEntities = null;
    }
  }

  const normalizedMessage = {
    id: entry.message_id,
    senderId: entry.sender_id,
    senderName: entry.sender_name,
    text: msgRow.text || "",
    isFromTelegram: true,
    createdAt: msgRow.created_at,
    telegramMessageId: msgRow.telegram_message_id,
    replyToId: msgRow.reply_to_message_id,
    replyToName,
    replyToText,
    replyToMediaType,
    replyToAttachmentId,
    replyToTelegramFileId,
    replyToFileName,
    replyToDuration,
    attachments: (attachments || []).map(a => ({
      id: a.id,
      messageId: a.message_id,
      mediaType: a.media_type,
      telegramFileId: a.telegram_file_id,
      fileName: a.file_name,
      fileSize: a.file_size,
      mimeType: a.mime_type,
      duration: a.duration,
      createdAt: a.created_at,
    })),
    forwardFromType: msgRow.forward_from_type,
    forwardFromChatId: msgRow.forward_from_chat_id,
    forwardFromChatUsername: msgRow.forward_from_chat_username,
    forwardFromChatTitle: msgRow.forward_from_chat_title,
    forwardFromMessageId: msgRow.forward_from_message_id,
    // ✅ Stage 17
    textEntities,
  };

  const cursor = await emitSyncEvent(db, "message_created", entry.message_id, normalizedMessage);

  await db.prepare("DELETE FROM pending_media_groups WHERE group_id = ?")
    .bind(groupId).run();

  console.log(`[Normalizer] Media group finalized: groupId=${groupId} msgId=${entry.message_id} attachments=${attachments?.length ?? 0}`);
  return { message: normalizedMessage, cursor };
}

export async function normalizeTelegramEdit(db, editMsg) {
  const newText = editMsg.text || editMsg.caption || "";
  const now = Date.now();

  const msgRow = await db.prepare(
    "SELECT id FROM messages WHERE telegram_message_id = ?"
  ).bind(editMsg.message_id).first();

  if (!msgRow) return null;

  // ✅ Stage 17: entities روی edit هم می‌تواند بیاید
  const entitiesJson = extractEntitiesJson(editMsg);

  if (entitiesJson) {
    await db.prepare(`
      UPDATE messages
      SET text = ?, is_edited = 1, updated_at = ?, text_entities = ?
      WHERE id = ?
    `).bind(newText, now, entitiesJson, msgRow.id).run();
  } else {
    await db.prepare(`
      UPDATE messages
      SET text = ?, is_edited = 1, updated_at = ?
      WHERE id = ?
    `).bind(newText, now, msgRow.id).run();
  }

  const payload = {
    messageId: msgRow.id,
    telegramMessageId: editMsg.message_id,
    text: newText,
    updatedAt: now,
    // ✅ Stage 17: entities در payload هم
    textEntities: entitiesJson ? JSON.parse(entitiesJson) : null,
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

  if (reactionUpdate.new_reaction && Array.isArray(reactionUpdate.new_reaction)) {
    for (const r of reactionUpdate.new_reaction) {
      if (r.type === "emoji" && r.emoji) {
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
    reactions: allReactions || [],
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
    pinnedAt: now,
  };

  const cursor = await emitSyncEvent(db, "message_pinned", msgRow.id, payload);
  return { payload, cursor };
}