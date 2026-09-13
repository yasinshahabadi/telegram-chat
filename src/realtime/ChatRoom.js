import { DurableObject } from "cloudflare:workers";
import {
  escapeXml,
  sendTelegramMessage,
  editTelegramMessageText,
  pinTelegramChatMessage,
  unpinTelegramChatMessage,
  setTelegramMessageReaction
} from "../telegram/telegramClient.js";
import { emitSyncEvent } from "../telegram/normalizer.js";

/**
 * ChatRoom Durable Object (Realtime Engine v2)
 * Features Cloudflare WebSocket Hibernation API, verified identity state, and D1 sync.
 */
export class ChatRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);

    // ۱. اندپوینت دریافت برودکست داخلی (از وب‌هوک تلگرام یا کنترلرها)
    if (url.pathname === "/broadcast") {
      const payload = await request.json();
      this.broadcast(payload);
      return new Response("OK");
    }

    // ۲. پذیرش اتصال وب‌سوکت با متادیتای احراز هویت شده
    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      // استخراج هویت تاییدشده از هدرهای داخلی
      const userMeta = {
        userId: request.headers.get("X-Auth-User-Id") || "anonymous",
        fullName: decodeURIComponent(request.headers.get("X-Auth-Full-Name") || "کاربر"),
        username: decodeURIComponent(request.headers.get("X-Auth-Username") || "ندارد"),
        telegramId: request.headers.get("X-Auth-Telegram-Id") || null,
        deviceId: request.headers.get("X-Auth-Device-Id") || null,
        isAdmin: request.headers.get("X-Auth-Is-Admin") === "true",
        isOnline: true
      };

      // تگ‌گذاری سوکت با شناسه کاربر برای مدیریت سریع
      const tags = [userMeta.userId];
      if (userMeta.deviceId) tags.push(`dev_${userMeta.deviceId}`);

      // فعال‌سازی WebSocket Hibernation API
      this.ctx.acceptWebSocket(server, tags);
      server.serializeAttachment(userMeta);

      this.broadcastOnline();

      return new Response(null, {
        status: 101,
        webSocket: client
      });
    }

    return new Response("Not Found", { status: 404 });
  }

  /**
   * پردازش پیام‌های دریافتی از کلاینت از طریق وب‌سوکت
   */
  async webSocketMessage(ws, message) {
    try {
      const user = ws.deserializeAttachment();
      if (!user || !user.userId || user.userId === "anonymous") {
        ws.close(4401, "Unauthorized");
        return;
      }

      const data = JSON.parse(message);
      const now = Date.now();

      // ۱. رویداد وضعیت آنلاین بودن (Presence)
      if (data.type === "presence") {
        user.isOnline = (data.status === "online");
        ws.serializeAttachment(user);
        this.broadcastOnline();
        return;
      }

      // ۲. وضعیت در حال تایپ (Typing Indicator)
      if (data.type === "typing") {
        this.broadcast({
          type: "typing",
          userId: user.userId,
          fullName: user.fullName
        }, ws);
        return;
      }

      // ۳. علامت‌گذاری پیام‌ها به عنوان خوانده‌شده (Mark as Read)
      if (data.type === "mark_read" && Array.isArray(data.messageIds) && data.messageIds.length > 0) {
        for (const mId of data.messageIds) {
          await this.env.DB.prepare(`
            INSERT OR IGNORE INTO message_reads (id, message_id, user_id, read_at)
            VALUES (?, ?, ?, ?)
          `).bind(crypto.randomUUID(), mId, user.userId, now).run().catch(() => {});
        }

        this.broadcast({
          type: "messages_read",
          messageIds: data.messageIds,
          userId: user.userId,
          readAt: now
        });
        return;
      }

      // ۴. ارسال پیام جدید متنی (Chat Message)
      if (data.type === "chat_message" && data.text) {
        const clientMessageId = data.clientMessageId || null;
        const msgId = crypto.randomUUID();

        // بررسی Idempotency برای جلوگیری از ثبت تکراری پیام در اختلالات اینترنت
        if (clientMessageId) {
          const existing = await this.env.DB.prepare(
            "SELECT id FROM messages WHERE client_message_id = ?"
          ).bind(clientMessageId).first();
          if (existing) return;
        }

        const replyToId = data.replyTo ? data.replyTo.id : null;
        let tgReplyMsgId = null;

        if (replyToId) {
          const replyRow = await this.env.DB.prepare(
            "SELECT telegram_message_id FROM messages WHERE id = ?"
          ).bind(replyToId).first();
          if (replyRow) tgReplyMsgId = replyRow.telegram_message_id;
        }

        // درج در جدول messages
        await this.env.DB.prepare(`
          INSERT INTO messages (
            id, client_message_id, sender_id, text, is_from_telegram, created_at, updated_at, reply_to_message_id
          )
          VALUES (?, ?, ?, ?, 0, ?, ?, ?)
        `).bind(msgId, clientMessageId, user.userId, data.text, now, now, replyToId).run();

        const messagePayload = {
          id: msgId,
          clientMessageId,
          senderId: user.userId,
          senderName: user.fullName,
          text: data.text,
          isFromTelegram: false,
          createdAt: now,
          replyToId,
          reactions: []
        };

        // ثبت رویداد ترتیبی همگام‌سازی آفلاین
        await emitSyncEvent(this.env.DB, "message_created", msgId, messagePayload);

        // برودکست پیام به تمام کلاینت‌های متصل
        this.broadcast({
          type: "new_message",
          message: messagePayload
        });

        // ارسال موازی پیام به سوپرگروه تلگرام
        try {
          let caption = `🌐 <b>[برنامه اندروید]</b>\n👤 <b>فرستنده:</b> ${escapeXml(user.fullName)}\n`;
          if (data.replyTo && !tgReplyMsgId) {
            caption += `↩️ <i>پاسخ به ${escapeXml(data.replyTo.name)}:</i> «${escapeXml((data.replyTo.text || "").substring(0, 35))}»\n`;
          }
          caption += `💬 ${escapeXml(data.text)}`;

          const tgRes = await sendTelegramMessage(this.env.TELEGRAM_BOT_TOKEN, {
            chatId: this.env.TELEGRAM_GROUP_ID,
            text: caption,
            replyParameters: tgReplyMsgId ? { message_id: tgReplyMsgId } : null
          });

          if (tgRes.ok && tgRes.result?.message_id) {
            await this.env.DB.prepare(
              "UPDATE messages SET telegram_message_id = ? WHERE id = ?"
            ).bind(tgRes.result.message_id, msgId).run();
          }
        } catch (tgErr) {}
        return;
      }

      // ۵. ویرایش متن پیام (Edit Message)
      if (data.type === "edit_message" && data.messageId && data.newText) {
        const msgRow = await this.env.DB.prepare(
          "SELECT sender_id, telegram_message_id FROM messages WHERE id = ?"
        ).bind(data.messageId).first();

        // بررسی اینکه کاربر مالک پیام است یا ادمین سیستم
        if (msgRow && (msgRow.sender_id === user.userId || user.isAdmin)) {
          await this.env.DB.prepare(
            "UPDATE messages SET text = ?, is_edited = 1, updated_at = ? WHERE id = ?"
          ).bind(data.newText, now, data.messageId).run();

          const editPayload = {
            messageId: data.messageId,
            text: data.newText,
            updatedAt: now
          };

          await emitSyncEvent(this.env.DB, "message_edited", data.messageId, editPayload);

          this.broadcast({
            type: "message_edited",
            ...editPayload
          });

          if (msgRow.telegram_message_id) {
            try {
              const newContent = `🌐 <b>[برنامه اندروید]</b>\n👤 <b>فرستنده:</b> ${escapeXml(user.fullName)}\n💬 ${escapeXml(data.newText)}`;
              await editTelegramMessageText(this.env.TELEGRAM_BOT_TOKEN, {
                chatId: this.env.TELEGRAM_GROUP_ID,
                messageId: msgRow.telegram_message_id,
                text: newContent
              });
            } catch (tgErr) {}
          }
        }
        return;
      }

      // ۶. تغییر وضعیت ری‌اکشن (Toggle Reaction)
      if (data.type === "toggle_reaction" && data.messageId && data.emoji) {
        const existing = await this.env.DB.prepare(
          "SELECT id FROM reactions WHERE message_id = ? AND user_id = ? AND emoji = ?"
        ).bind(data.messageId, user.userId, data.emoji).first();

        if (existing) {
          await this.env.DB.prepare("DELETE FROM reactions WHERE id = ?").bind(existing.id).run();
        } else {
          await this.env.DB.prepare(`
            INSERT OR IGNORE INTO reactions (id, message_id, user_id, telegram_user_id, emoji, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
          `).bind(crypto.randomUUID(), data.messageId, user.userId, user.telegramId, data.emoji, now).run();
        }

        const { results: allReactions } = await this.env.DB.prepare(`
          SELECT emoji, COUNT(*) AS count 
          FROM reactions 
          WHERE message_id = ? 
          GROUP BY emoji
        `).bind(data.messageId).all();

        const rxPayload = {
          messageId: data.messageId,
          reactions: allReactions || []
        };

        await emitSyncEvent(this.env.DB, "reaction_updated", data.messageId, rxPayload);

        this.broadcast({
          type: "reaction_updated",
          ...rxPayload
        });

        // همگام‌سازی ری‌اکشن با تلگرام
        const msgRow = await this.env.DB.prepare(
          "SELECT telegram_message_id FROM messages WHERE id = ?"
        ).bind(data.messageId).first();

        if (msgRow?.telegram_message_id) {
          try {
            await setTelegramMessageReaction(this.env.TELEGRAM_BOT_TOKEN, {
              chatId: this.env.TELEGRAM_GROUP_ID,
              messageId: msgRow.telegram_message_id,
              reaction: existing ? [] : [{ type: "emoji", emoji: data.emoji }]
            });
          } catch (tgErr) {}
        }
        return;
      }

      // ۷. پین یا حذف پین پیام (Pin / Unpin Message)
      if (data.type === "pin_message" && data.messageId) {
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 1, updated_at = ? WHERE id = ?")
          .bind(now, data.messageId).run();

        const pinPayload = {
          messageId: data.messageId,
          isPinned: true,
          pinnedAt: now
        };

        await emitSyncEvent(this.env.DB, "message_pinned", data.messageId, pinPayload);

        this.broadcast({
          type: "message_pinned",
          ...pinPayload
        });

        const msgRow = await this.env.DB.prepare(
          "SELECT telegram_message_id FROM messages WHERE id = ?"
        ).bind(data.messageId).first();

        if (msgRow?.telegram_message_id) {
          try {
            await pinTelegramChatMessage(this.env.TELEGRAM_BOT_TOKEN, {
              chatId: this.env.TELEGRAM_GROUP_ID,
              messageId: msgRow.telegram_message_id
            });
          } catch (tgErr) {}
        }
        return;
      }

      if (data.type === "unpin_message") {
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();

        await emitSyncEvent(this.env.DB, "message_unpinned", "global", { unpinnedAt: now });

        this.broadcast({ type: "message_unpinned" });

        try {
          await unpinTelegramChatMessage(this.env.TELEGRAM_BOT_TOKEN, {
            chatId: this.env.TELEGRAM_GROUP_ID
          });
        } catch (tgErr) {}
        return;
      }
    } catch (err) {}
  }

  async webSocketClose(ws, code, reason, wasClean) {
    try {
      const user = ws.deserializeAttachment() || {};
      user.isOnline = false;
      ws.serializeAttachment(user);
    } catch (e) {}
    this.broadcastOnline();
  }

  async webSocketError(ws, error) {
    try {
      const user = ws.deserializeAttachment() || {};
      user.isOnline = false;
      ws.serializeAttachment(user);
    } catch (e) {}
    this.broadcastOnline();
  }

  broadcast(data, excludeWs = null) {
    const str = JSON.stringify(data);
    for (const ws of this.ctx.getWebSockets()) {
      if (ws !== excludeWs) {
        try {
          ws.send(str);
        } catch (err) {}
      }
    }
  }

  broadcastOnline() {
    const onlineMap = new Map();
    for (const ws of this.ctx.getWebSockets()) {
      try {
        const att = ws.deserializeAttachment();
        if (att && att.userId && att.isOnline === true) {
          onlineMap.set(att.userId, {
            userId: att.userId,
            fullName: att.fullName,
            username: att.username
          });
        }
      } catch (err) {}
    }
    this.broadcast({
      type: "online_users",
      users: Array.from(onlineMap.values())
    });
  }
}
