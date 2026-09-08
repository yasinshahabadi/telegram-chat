import { DurableObject } from "cloudflare:workers";
import { buildPushPayload } from "@block65/webcrypto-web-push";

const MAX_FILE_SIZE = 20 * 1024 * 1024;

function escapeXml(str) {
  return String(str || "").replace(/[&<>"']/g, m => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[m]));
}

// تابع ارسال وب‌پوش به تمامی اعضای مشترک از طریق سرورهای گوگل/اپل
const PUSH_TTL_SECONDS = 60 * 60 * 24 * 28;

async function dispatchWebPush(env, { title, body, senderUserId = null, messageId = null }) {
  if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) {
    console.error("Web Push is not configured: missing VAPID keys");
    return;
  }

  const vapid = {
    subject: env.VAPID_SUBJECT || "mailto:admin@chat-app.com",
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY
  };

  try {
    const query = senderUserId
      ? "SELECT * FROM push_subscriptions WHERE user_id != ? OR user_id IS NULL"
      : "SELECT * FROM push_subscriptions";

    const stmt = senderUserId
      ? env.DB.prepare(query).bind(senderUserId)
      : env.DB.prepare(query);

    const { results: subs } = await stmt.all();
    if (!subs || subs.length === 0) return;

    const payloadData = JSON.stringify({
      title,
      body,
      url: '/',
      messageId: messageId || crypto.randomUUID()
    });

    const sendOne = async (sub) => {
      if (!sub.endpoint || !sub.p256dh || !sub.auth) return;

      try {
        const pushSub = {
          endpoint: sub.endpoint,
          keys: {
            p256dh: sub.p256dh,
            auth: sub.auth
          }
        };

        const payload = await buildPushPayload({
          data: payloadData,
          options: {
            // Keep the message at the push service while the device is offline.
            ttl: PUSH_TTL_SECONDS,
            // Chat messages should be delivered promptly when the device reconnects.
            urgency: "high"
          }
        }, pushSub, vapid);

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        let res;
        try {
          res = await fetch(sub.endpoint, { ...payload, signal: controller.signal });
        } finally {
          clearTimeout(timeoutId);
        }

        if (res.status === 404 || res.status === 410) {
          await env.DB
            .prepare("DELETE FROM push_subscriptions WHERE endpoint = ?")
            .bind(sub.endpoint)
            .run();
          return;
        }

        if (!res.ok) {
          console.error("Push service error:", res.status, await res.text().catch(() => ""));
          return;
        }

        console.log("Push sent:", res.status);
      } catch (e) {
        console.error("Push dispatch single error:", e);
      }
    };

    // Send to all devices in parallel so a slow endpoint cannot block the others.
    await Promise.allSettled(subs.map(sendOne));
  } catch (err) {
    console.error("Push dispatch all error:", err);
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    ctx.waitUntil(ensureDbSchema(env.DB));

    // ۱. دریافت کلید عمومی VAPID برای کلاینت
    if (url.pathname === "/api/vapid-public-key") {
      return Response.json({ publicKey: env.VAPID_PUBLIC_KEY || null });
    }

    // ۲. ثبت اشتراک وب‌پوش کلاینت
    if (url.pathname === "/api/push-subscribe" && request.method === "POST") {
      try {
        const { endpoint, p256dh, auth, sessionToken } = await request.json();
        let userId = null;
        if (sessionToken) {
          const user = await env.DB.prepare("SELECT user_id FROM sessions WHERE token = ?").bind(sessionToken).first();
          if (user) userId = user.user_id;
        }

        await env.DB.prepare(`
          INSERT OR REPLACE INTO push_subscriptions (endpoint, p256dh, auth, user_id)
          VALUES (?, ?, ?, ?)
        `).bind(endpoint, p256dh, auth, userId).run();

        return Response.json({ status: "ok" });
      } catch (e) {
        return Response.json({ status: "error" }, { status: 500 });
      }
    }

    // ۳. استریم مدیا
    if (url.pathname === "/api/media") {
      const fileId = url.searchParams.get("fileId");
      const customName = url.searchParams.get("name");
      const isDownload = url.searchParams.get("download") === "1";
      if (!fileId) return new Response("Missing fileId", { status: 400 });

      try {
        const fileRes = await fetch(
          `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${fileId}`
        );
        const fileData = await fileRes.json();

        if (fileData.ok && fileData.result.file_path) {
          if (fileData.result.file_size && fileData.result.file_size > MAX_FILE_SIZE) {
            return new Response("حجم بیش از ۲۰ مگابایت است.", { status: 413 });
          }

          const filePath = fileData.result.file_path;
          const ext = filePath.includes(".") ? filePath.split(".").pop() : "bin";
          const fileName = customName || `file_${fileId.substring(0, 8)}.${ext}`;

          const mediaRes = await fetch(
            `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${filePath}`
          );

          let contentType = mediaRes.headers.get("Content-Type") || "application/octet-stream";
          if (ext === "mp4") contentType = "video/mp4";
          else if (ext === "jpg" || ext === "jpeg") contentType = "image/jpeg";
          else if (ext === "png") contentType = "image/png";
          else if (ext === "mp3") contentType = "audio/mpeg";
          else if (ext === "ogg") contentType = "audio/ogg";

          return new Response(mediaRes.body, {
            headers: {
              "Content-Type": contentType,
              "Content-Disposition": `${isDownload ? "attachment" : "inline"}; filename="${encodeURIComponent(fileName)}"`,
              "Cache-Control": "public, max-age=604800, immutable"
            }
          });
        }
      } catch (e) {}
      return new Response("فایل یافت نشد", { status: 404 });
    }

    // ۴. خروج کاربر (Logout)
    if (url.pathname === "/api/auth/logout" && request.method === "POST") {
      try {
        const { sessionToken } = await request.json();
        if (sessionToken) {
          await env.DB.prepare("DELETE FROM sessions WHERE token = ?").bind(sessionToken).run();
        }
        return Response.json({ status: "ok" });
      } catch (e) {
        return Response.json({ status: "error" }, { status: 500 });
      }
    }

    // ۵. آپلود مدیا
    if (url.pathname === "/api/upload" && request.method === "POST") {
      try {
        const formData = await request.formData();
        const file = formData.get("file");
        const caption = (formData.get("caption") || "").trim();
        const sessionToken = formData.get("sessionToken");
        const replyToRaw = formData.get("replyTo");

        if (!file || !(file instanceof File) || file.size > MAX_FILE_SIZE) {
          return Response.json({ status: "error", message: "فایل نامعتبر یا بیش از ۲۰ مگابایت است." }, { status: 400 });
        }

        const user = await env.DB.prepare(`
          SELECT u.* FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.token = ?
        `).bind(sessionToken).first();

        if (!user || !user.is_approved) return Response.json({ status: "unauthorized" }, { status: 401 });

        let replyTo = null;
        if (replyToRaw) {
          try { replyTo = JSON.parse(replyToRaw); } catch (e) {}
        }

        let mediaType = "document";
        let tgEndpoint = "sendDocument";
        let fileField = "document";

        if (file.type.startsWith("image/")) {
          mediaType = "photo"; tgEndpoint = "sendPhoto"; fileField = "photo";
        } else if (file.type.startsWith("video/")) {
          mediaType = "video"; tgEndpoint = "sendVideo"; fileField = "video";
        } else if (file.type.startsWith("audio/")) {
          mediaType = "audio"; tgEndpoint = "sendAudio"; fileField = "audio";
        }

        const tgFormData = new FormData();
        tgFormData.append("chat_id", env.TELEGRAM_GROUP_ID);

        let tgCaption = `🌐 <b>[وب‌سایت]</b>\n👤 <b>فرستنده:</b> ${escapeXml(user.full_name)}`;
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
        if (!tgData.ok) return Response.json({ status: "error", message: tgData.description }, { status: 500 });

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
        } else if (resMsg.audio) {
          fileId = resMsg.audio.file_id;
          duration = resMsg.audio.duration || 0;
        } else if (resMsg.document) fileId = resMsg.document.file_id;

        const msgId = crypto.randomUUID();
        const timestamp = Date.now();
        const replyId = replyTo ? replyTo.id : null;

        await env.DB.prepare(`
          INSERT INTO messages (id, sender_id, sender_name, text, is_from_telegram, timestamp, reply_to_name, reply_to_text, reply_to_id, tg_msg_id, is_read, read_at, is_edited, media_type, media_file_id, media_file_name, media_file_size, media_thumb_id, media_duration, reactions)
          VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 0, NULL, 0, ?, ?, ?, ?, ?, ?, '{}')
        `).bind(
          msgId, user.id, user.full_name, caption, timestamp,
          replyTo ? replyTo.name : null, replyTo ? replyTo.text : null, replyId, resMsg.message_id,
          mediaType, fileId, file.name, file.size, thumbId, duration
        ).run();

        const roomId = env.CHAT_ROOM.idFromName("global_room");
        await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
          method: "POST",
          body: JSON.stringify({
            type: "new_message",
            message: {
              id: msgId, sender_id: user.telegram_id || user.id, sender_name: user.full_name, text: caption,
              is_from_telegram: 0, timestamp, reply_to_name: replyTo ? replyTo.name : null, reply_to_text: replyTo ? replyTo.text : null,
              reply_to_id: replyId, tg_msg_id: resMsg.message_id, is_read: 0, read_at: null, is_edited: 0, media_type: mediaType,
              media_file_id: fileId, media_file_name: file.name, media_file_size: file.size, media_thumb_id: thumbId, media_duration: duration, reactions: "{}"
            }
          })
        });

        // ارسال وب‌پوش واقعی به گوشی‌های خاموش
        ctx.waitUntil(dispatchWebPush(env, {
          title: `🌐 وب: ${user.full_name}`,
          body: caption || `[ارسال ${mediaType}]`,
          senderUserId: user.id,
          messageId: msgId
        }));

        return Response.json({ status: "ok", fileId });
      } catch (err) {
        return Response.json({ status: "error", message: err.message }, { status: 500 });
      }
    }

    // ۶. آواتار
    if (url.pathname === "/api/avatar") {
      const userId = url.searchParams.get("userId");
      if (!userId) return new Response("Missing userId", { status: 400 });

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
      return new Response("Not found", { status: 404 });
    }

    // ۷. وب‌هوک تلگرام
    if (url.pathname === "/api/telegram-webhook" && request.method === "POST") {
      try {
        const update = await request.json();
        return await handleTelegramUpdate(update, env, ctx);
      } catch (e) {
        return new Response("OK");
      }
    }

    // ۸. بررسی ورود
    if (url.pathname === "/api/auth/verify-device" && request.method === "POST") {
      try {
        const { sessionToken, fingerprint } = await request.json();
        const user = await env.DB.prepare(`
          SELECT u.* FROM users u JOIN sessions s ON u.id = s.user_id WHERE s.token = ?
        `).bind(sessionToken).first();

        if (!user) return Response.json({ status: "not_found" }, { status: 401 });
        if (!user.is_approved) return Response.json({ status: "pending" }, { status: 403 });

        if (user.device_fingerprint && user.device_fingerprint !== fingerprint) {
          return Response.json({ status: "hardware_mismatch" }, { status: 403 });
        }

        if (!user.device_fingerprint) {
          await env.DB.prepare("UPDATE users SET device_fingerprint = ? WHERE id = ?").bind(fingerprint, user.id).run();
        }

        return Response.json({ status: "ok", user });
      } catch (e) {
        return Response.json({ status: "error" }, { status: 500 });
      }
    }

    // ۹. وب‌سوکت
    if (url.pathname === "/api/ws") {
      if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected WebSocket", { status: 426 });
      const id = env.CHAT_ROOM.idFromName("global_room");
      return env.CHAT_ROOM.get(id).fetch(request);
    }

    // ۱۰. دریافت پیام‌ها
    if (url.pathname === "/api/messages") {
      try {
        const since = url.searchParams.get("since");
        const before = url.searchParams.get("before");
        const limit = Math.min(Number(url.searchParams.get("limit")) || 35, 50);

        let results;
        if (since && !isNaN(Number(since))) {
          const stmt = await env.DB.prepare(
            "SELECT * FROM messages WHERE timestamp > ? ORDER BY timestamp ASC LIMIT ?"
          ).bind(Number(since), limit).all();
          results = stmt.results;
        } else if (before && !isNaN(Number(before))) {
          const stmt = await env.DB.prepare(
            "SELECT * FROM messages WHERE timestamp < ? ORDER BY timestamp DESC LIMIT ?"
          ).bind(Number(before), limit).all();
          results = stmt.results ? stmt.results.reverse() : [];
        } else {
          const stmt = await env.DB.prepare(
            "SELECT * FROM messages ORDER BY timestamp DESC LIMIT ?"
          ).bind(limit).all();
          results = stmt.results ? stmt.results.reverse() : [];
        }

        const pinned = await env.DB.prepare("SELECT * FROM messages WHERE is_pinned = 1 ORDER BY timestamp DESC LIMIT 1").first();
        return Response.json({ messages: results || [], pinned: pinned || null });
      } catch (e) {
        return Response.json({ messages: [], pinned: null });
      }
    }

    return env.ASSETS ? env.ASSETS.fetch(request) : new Response("Not Found", { status: 404 });
  },

  async scheduled(event, env, ctx) {
    const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
    await env.DB.prepare("DELETE FROM messages WHERE timestamp < ?").bind(oneDayAgo).run();
  }
};

async function ensureDbSchema(db) {
  try { await db.prepare("ALTER TABLE messages ADD COLUMN reply_to_name TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN reply_to_text TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN reply_to_id TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN tg_msg_id INTEGER").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN is_read INTEGER DEFAULT 0").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN read_at INTEGER").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN is_edited INTEGER DEFAULT 0").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN is_pinned INTEGER DEFAULT 0").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN reactions TEXT DEFAULT '{}'").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_type TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_file_id TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_file_name TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_file_size INTEGER").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_thumb_id TEXT").run(); } catch (e) {}
  try { await db.prepare("ALTER TABLE messages ADD COLUMN media_duration INTEGER DEFAULT 0").run(); } catch (e) {}
  try { await db.prepare("CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp)").run(); } catch (e) {}
  // جدول ذخیره اشتراک‌های وب‌پوش
  try {
    await db.prepare(`
      CREATE TABLE IF NOT EXISTS push_subscriptions (
        endpoint TEXT PRIMARY KEY,
        p256dh TEXT,
        auth TEXT,
        user_id TEXT
      )
    `).run();
  } catch (e) {}
}

async function handleTelegramUpdate(update, env, ctx) {
  if (update.callback_query) {
    const cb = update.callback_query;
    const data = cb.data || "";
    if (cb.from.id.toString() !== env.ADMIN_TELEGRAM_ID) return new Response("Unauthorized");

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
          text: `⚙️ <b>داشبورد مدیریت کاربران</b>\n\n👥 تعداد کل: <b>${users ? users.length : 0}</b> نفر:`,
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
                   `• شناسه: <code>${u.telegram_id}</code>\n` +
                   `• سخت‌افزار: <code>${u.device_fingerprint || "ثبت نشده"}</code>`;

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
      await env.DB.prepare("UPDATE users SET is_approved = 1 WHERE id = ?").bind(userId).run();
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
    if (update.message.from.id.toString() !== env.ADMIN_TELEGRAM_ID) return new Response("Unauthorized");
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
        text: `⚙️ <b>داشبورد مدیریت کاربران وب‌سایت</b>\n\n👥 تعداد کل: <b>${users ? users.length : 0}</b> نفر:`,
        parse_mode: "HTML", reply_markup: { inline_keyboard: buttons }
      })
    });
    return new Response("OK");
  }

  // ری‌اکشن تلگرام به وب
  if (update.message_reaction && update.message_reaction.chat) {
    const mr = update.message_reaction;
    const tgMsgId = mr.message_id;
    const userName = mr.user ? `${mr.user.first_name || ""} ${mr.user.last_name || ""}`.trim() : "کاربر";

    const row = await env.DB.prepare("SELECT id, reactions FROM messages WHERE tg_msg_id = ?").bind(tgMsgId).first();
    if (row) {
      let reactions = {};
      try { reactions = JSON.parse(row.reactions || "{}"); } catch (e) {}

      for (const em in reactions) {
        reactions[em] = reactions[em].filter(u => u !== userName);
        if (reactions[em].length === 0) delete reactions[em];
      }

      if (mr.new_reaction && Array.isArray(mr.new_reaction)) {
        mr.new_reaction.forEach(r => {
          if (r.type === "emoji") {
            if (!reactions[r.emoji]) reactions[r.emoji] = [];
            if (!reactions[r.emoji].includes(userName)) reactions[r.emoji].push(userName);
          }
        });
      }

      const rxJson = JSON.stringify(reactions);
      await env.DB.prepare("UPDATE messages SET reactions = ? WHERE id = ?").bind(rxJson, row.id).run();

      const roomId = env.CHAT_ROOM.idFromName("global_room");
      await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
        method: "POST", body: JSON.stringify({ type: "reaction_updated", messageId: row.id, reactions: rxJson })
      });
    }
    return new Response("OK");
  }

  // ادیت پیام در تلگرام
  if (update.edited_message && update.edited_message.chat) {
    const editMsg = update.edited_message;
    const newText = editMsg.text || editMsg.caption || "";
    await env.DB.prepare("UPDATE messages SET text = ?, is_edited = 1 WHERE tg_msg_id = ?").bind(newText, editMsg.message_id).run();
    
    const roomId = env.CHAT_ROOM.idFromName("global_room");
    await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
      method: "POST", body: JSON.stringify({ type: "message_edited", tgMsgId: editMsg.message_id, text: newText })
    });
    return new Response("OK");
  }

  // پین پیام در تلگرام
  if (update.message && update.message.pinned_message) {
    const pinnedTgId = update.message.pinned_message.message_id;
    await env.DB.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();
    await env.DB.prepare("UPDATE messages SET is_pinned = 1 WHERE tg_msg_id = ?").bind(pinnedTgId).run();
    const pinnedMsg = await env.DB.prepare("SELECT * FROM messages WHERE tg_msg_id = ?").bind(pinnedTgId).first();

    if (pinnedMsg) {
      const roomId = env.CHAT_ROOM.idFromName("global_room");
      await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
        method: "POST", body: JSON.stringify({ type: "message_pinned", message: pinnedMsg })
      });
    }
    return new Response("OK");
  }

  // احراز هویت اولیه
  if (update.message && update.message.text && update.message.text.startsWith("/start auth_")) {
    const token = update.message.text.split(" ")[1].replace("auth_", "");
    const tgUser = update.message.from;
    const userId = crypto.randomUUID();
    const isAdmin = tgUser.id.toString() === env.ADMIN_TELEGRAM_ID;

    await env.DB.prepare(`
      INSERT OR REPLACE INTO users (id, telegram_id, full_name, username, is_approved, is_admin, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(userId, tgUser.id.toString(), `${tgUser.first_name || ""} ${tgUser.last_name || ""}`.trim(), tgUser.username || "ندارد", isAdmin ? 1 : 0, isAdmin ? 1 : 0, Date.now()).run();

    await env.DB.prepare("INSERT OR REPLACE INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)").bind(token, userId, Date.now()).run();

    if (!isAdmin) {
      await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: env.ADMIN_TELEGRAM_ID,
          text: `🔔 <b>درخواست عضویت جدید</b>\n\n👤 نام: ${escapeXml(tgUser.first_name || "")}\n🆔 آیدی: @${tgUser.username || "ندارد"}\n🔢 شناسه: <code>${tgUser.id}</code>`,
          parse_mode: "HTML", reply_markup: { inline_keyboard: [[{ text: "✅ تایید دسترسی", callback_data: `approve:${userId}` }, { text: "❌ رد", callback_data: `reject:${userId}` }]] }
        })
      });
    }

    await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: tgUser.id, text: isAdmin ? "شما مدیر هستید. دسترسی تایید شد!" : "درخواست برای مدیر ارسال شد. پس از تایید صفحه چت باز خواهد شد." })
    });
    return new Response("OK");
  }

  // پیام جدید از تلگرام
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

      let replyToName = null, replyToText = null, replyToId = null;
      if (msg.reply_to_message) {
        const rFrom = msg.reply_to_message.from;
        replyToName = rFrom ? `${rFrom.first_name || ""} ${rFrom.last_name || ""}`.trim() : "پیام";
        replyToText = msg.reply_to_message.text || msg.reply_to_message.caption || "مدیا";
        replyToId = `tg_${msg.reply_to_message.message_id}`;
      }

      let mediaType = null, fileId = null, fileName = null, fileSize = null, thumbId = null, duration = 0;

      if (msg.photo && msg.photo.length > 0) {
        mediaType = "photo"; fileId = msg.photo[msg.photo.length - 1].file_id; fileSize = msg.photo[msg.photo.length - 1].file_size; fileName = "photo.jpg";
      } else if (msg.video) {
        mediaType = "video"; fileId = msg.video.file_id; fileSize = msg.video.file_size; fileName = msg.video.file_name || "video.mp4"; duration = msg.video.duration || 0;
        const th = msg.video.thumbnail || msg.video.thumb;
        if (th) thumbId = th.file_id;
      } else if (msg.voice) {
        mediaType = "audio"; fileId = msg.voice.file_id; fileSize = msg.voice.file_size; fileName = "voice.ogg"; duration = msg.voice.duration || 0;
      } else if (msg.audio) {
        mediaType = "audio"; fileId = msg.audio.file_id; fileSize = msg.audio.file_size; fileName = "audio.mp3"; duration = msg.audio.duration || 0;
      } else if (msg.document) {
        mediaType = "document"; fileId = msg.document.file_id; fileSize = msg.document.file_size; fileName = msg.document.file_name || "file";
      }

      if (fileSize && fileSize > MAX_FILE_SIZE) mediaType = "oversized";

      if (text || mediaType) {
        await env.DB.prepare(`
          INSERT INTO messages (id, sender_id, sender_name, text, is_from_telegram, timestamp, reply_to_name, reply_to_text, reply_to_id, tg_msg_id, is_read, read_at, is_edited, media_type, media_file_id, media_file_name, media_file_size, media_thumb_id, media_duration, reactions)
          VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, 0, NULL, 0, ?, ?, ?, ?, ?, ?, '{}')
        `).bind(msgId, msg.from.id.toString(), senderName, text, timestamp, replyToName, replyToText, replyToId, msg.message_id, mediaType, fileId, fileName, fileSize, thumbId, duration).run();

        const roomId = env.CHAT_ROOM.idFromName("global_room");
        await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
          method: "POST",
          body: JSON.stringify({
            type: "new_message",
            message: {
              id: msgId, sender_id: msg.from.id.toString(), sender_name: senderName, text, is_from_telegram: 1,
              timestamp, reply_to_name: replyToName, reply_to_text: replyToText, reply_to_id: replyToId,
              tg_msg_id: msg.message_id, is_read: 0, read_at: null, is_edited: 0, media_type: mediaType,
              media_file_id: fileId, media_file_name: fileName, media_file_size: fileSize, media_thumb_id: thumbId,
              media_duration: duration, reactions: "{}"
            }
          })
        });

        // ارسال اعلان واقعی به گوشی‌های بسته هنگام ارسال پیام در تلگرام
        ctx.waitUntil(dispatchWebPush(env, {
          title: `📱 تلگرام: ${senderName}`,
          body: text || (mediaType ? `[ارسال ${mediaType}]` : 'پیام جدید'),
          messageId: msgId
        }));
      }
    }
  }

  return new Response("OK");
}

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
        ws.serializeAttachment({ userName: data.userName, userId: data.userId, tgId: data.tgId, isOnline: true });
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

      if (data.type === "mark_read" && Array.isArray(data.messageIds) && data.messageIds.length > 0) {
        const now = Date.now();
        const placeholders = data.messageIds.map(() => "?").join(",");
        await this.env.DB.prepare(
          `UPDATE messages SET is_read = 1, read_at = ? WHERE id IN (${placeholders})`
        ).bind(now, ...data.messageIds).run().catch(() => {});

        this.broadcast({ type: "messages_read", messageIds: data.messageIds, readAt: now });
        return;
      }

      if (data.type === "toggle_reaction") {
        const user = ws.deserializeAttachment();
        if (!user) return;

        const row = await this.env.DB.prepare("SELECT reactions, tg_msg_id FROM messages WHERE id = ?").bind(data.messageId).first();
        if (row) {
          let reactions = {};
          try { reactions = JSON.parse(row.reactions || "{}"); } catch (e) {}

          const emoji = data.emoji;
          let userRemoved = false;

          for (const em in reactions) {
            const uIdx = reactions[em].indexOf(user.userName);
            if (uIdx > -1) {
              reactions[em].splice(uIdx, 1);
              if (em === emoji) userRemoved = true;
              if (reactions[em].length === 0) delete reactions[em];
            }
          }

          if (!userRemoved) {
            if (!reactions[emoji]) reactions[emoji] = [];
            reactions[emoji].push(user.userName);
          }

          const rxJson = JSON.stringify(reactions);
          await this.env.DB.prepare("UPDATE messages SET reactions = ? WHERE id = ?").bind(rxJson, data.messageId).run();
          this.broadcast({ type: "reaction_updated", messageId: data.messageId, reactions: rxJson });

          if (row.tg_msg_id) {
            try {
              const tgReactionPayload = userRemoved ? [] : [{ type: "emoji", emoji }];
              await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/setMessageReaction`, {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ chat_id: this.env.TELEGRAM_GROUP_ID, message_id: row.tg_msg_id, reaction: tgReactionPayload })
              });
            } catch (e) {}
          }
        }
        return;
      }

      if (data.type === "edit_message") {
        const user = ws.deserializeAttachment();
        if (!user) return;

        const row = await this.env.DB.prepare("SELECT sender_name, tg_msg_id, media_type FROM messages WHERE id = ?").bind(data.messageId).first();
        if (row && row.sender_name === user.userName) {
          await this.env.DB.prepare("UPDATE messages SET text = ?, is_edited = 1 WHERE id = ?").bind(data.newText, data.messageId).run();
          this.broadcast({ type: "message_edited", messageId: data.messageId, text: data.newText });

          if (row.tg_msg_id) {
            try {
              const isMedia = !!row.media_type;
              const editEndpoint = isMedia ? "editMessageCaption" : "editMessageText";
              const editBody = { chat_id: this.env.TELEGRAM_GROUP_ID, message_id: row.tg_msg_id, parse_mode: "HTML" };
              const newContent = `🌐 <b>[وب‌سایت]</b>\n👤 <b>فرستنده:</b> ${escapeXml(user.userName)}\n💬 ${escapeXml(data.newText)}`;
              if (isMedia) editBody.caption = newContent;
              else editBody.text = newContent;

              await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/${editEndpoint}`, {
                method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(editBody)
              });
            } catch (e) {}
          }
        }
        return;
      }

      if (data.type === "pin_message") {
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 1 WHERE id = ?").bind(data.messageId).run();

        const pinnedMsg = await this.env.DB.prepare("SELECT * FROM messages WHERE id = ?").bind(data.messageId).first();
        this.broadcast({ type: "message_pinned", message: pinnedMsg });

        if (pinnedMsg && pinnedMsg.tg_msg_id) {
          try {
            await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/pinChatMessage`, {
              method: "POST", headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ chat_id: this.env.TELEGRAM_GROUP_ID, message_id: pinnedMsg.tg_msg_id })
            });
          } catch (e) {}
        }
        return;
      }

      if (data.type === "unpin_message") {
        await this.env.DB.prepare("UPDATE messages SET is_pinned = 0 WHERE is_pinned = 1").run();
        this.broadcast({ type: "message_unpinned" });
        try {
          await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/unpinChatMessage`, {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ chat_id: this.env.TELEGRAM_GROUP_ID })
          });
        } catch (e) {}
        return;
      }

      const user = ws.deserializeAttachment();
      if (!user) return;

      if (data.type === "typing") {
        this.broadcast({ type: "typing", userName: user.userName }, ws);
      }

      if (data.type === "chat_message" && data.text) {
        const msgId = crypto.randomUUID();
        const time = Date.now();
        const replyName = data.replyTo ? data.replyTo.name : null;
        const replyText = data.replyTo ? data.replyTo.text : null;
        const replyTgId = data.replyTo ? data.replyTo.tgMsgId : null;
        const replyId = data.replyTo ? data.replyTo.id : null;

        this.broadcast({
          type: "new_message",
          message: {
            id: msgId, sender_id: user.tgId || user.userId, sender_name: user.userName, text: data.text,
            is_from_telegram: 0, timestamp: time, reply_to_name: replyName, reply_to_text: replyText,
            reply_to_id: replyId, is_read: 0, read_at: null, is_edited: 0, media_type: null, reactions: "{}"
          }
        });

        await this.env.DB.prepare(`
          INSERT INTO messages (id, sender_id, sender_name, text, is_from_telegram, timestamp, reply_to_name, reply_to_text, reply_to_id, is_read, read_at, is_edited, reactions)
          VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, 0, NULL, 0, '{}')
        `).bind(msgId, user.userId, user.userName, data.text, time, replyName, replyText, replyId).run();

        // ارسال وب‌پوش واقعی به گوشی‌های بسته اعضا
        await dispatchWebPush(this.env, {
          title: `🌐 وب: ${user.userName}`,
          body: data.text,
          senderUserId: user.userId,
          messageId: msgId
        });

        try {
          const safeUser = escapeXml(user.userName);
          const safeText = escapeXml(data.text);
          let caption = `🌐 <b>[وب‌سایت]</b>\n👤 <b>فرستنده:</b> ${safeUser}\n`;
          if (replyName && !replyTgId) caption += `↩️ <i>پاسخ به ${escapeXml(replyName)}:</i> «${escapeXml(replyText.substring(0, 35))}»\n`;
          caption += `💬 ${safeText}`;

          const tgBody = { chat_id: this.env.TELEGRAM_GROUP_ID, text: caption, parse_mode: "HTML" };
          if (replyTgId) tgBody.reply_parameters = { message_id: replyTgId };

          await fetch(`https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(tgBody)
          });
        } catch (err) {}
      }
    } catch (e) {}
  }

  async webSocketClose(ws) { this.broadcastOnline(); }

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
        if (att && att.userName && att.isOnline === true) online.push(att.userName);
      } catch (e) {}
    }
    this.broadcast({ type: "online_users", users: Array.from(new Set(online)) });
  }
}