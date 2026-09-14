/**
 * Secure Telegram Webhook Handler (Integrated with Asynchronous Job Queue)
 * Enforces X-Telegram-Bot-Api-Secret-Token validation and offloads heavy tasks to background queue.
 */

import { escapeXml, sendTelegramMessage, editTelegramMessageText } from "./telegramClient.js";
import {
  normalizeIncomingTelegramMessage,
  normalizeTelegramEdit,
  normalizeTelegramReaction,
  normalizeTelegramPin
} from "./normalizer.js";
import { processTelegramAuthStart } from "../auth/authController.js";
import { enqueueJob } from "../queue/jobQueue.js";

/**
 * متد اصلی پردازش درخواست‌های وب‌هوک تلگرام
 * POST /api/telegram-webhook
 */
export async function handleTelegramWebhook(request, env, ctx) {
  // ۱. اعتبارسنجی امنیتی سکرت توکن تلگرام (رفع آسیب‌پذیری بحرانی C-01)
  const secretHeader = request.headers.get("X-Telegram-Bot-Api-Secret-Token");
  if (env.TELEGRAM_WEBHOOK_SECRET && secretHeader !== env.TELEGRAM_WEBHOOK_SECRET) {
    return new Response("Forbidden: Invalid Webhook Secret Token", { status: 403 });
  }

  let update;
  try {
    update = await request.json();
  } catch (err) {
    return new Response("Bad Request: Invalid JSON", { status: 400 });
  }

  try {
    // ۲. پردازش دکمه‌های اینلاین شیشه‌ای (Callback Queries)
    if (update.callback_query) {
      return await handleCallbackQuery(update.callback_query, env);
    }

    // ۳. پردازش دستورات مدیریتی ربات (مثل /admin)
    if (update.message && update.message.text === "/admin") {
      return await handleAdminCommand(update.message, env);
    }

    // ۴. پردازش جریان ورود و ثبت‌نام با دیپ‌لینک (/start auth_<token>)
    if (update.message && update.message.text && update.message.text.startsWith("/start auth_")) {
      return await handleAuthStart(update.message, env);
    }

    // ۵. پردازش پیام‌های پین‌شده تلگرام
    if (update.message && update.message.pinned_message) {
      const pinResult = await normalizeTelegramPin(env.DB, update.message.pinned_message.message_id);
      if (pinResult) {
        enqueueJob(ctx, env, {
          type: "BROADCAST_PIN",
          payload: { type: "message_pinned", message: pinResult.payload },
          handler: async (p, e) => broadcastToChatRoom(e, p)
        });
      }
      return new Response("OK");
    }

    // ۶. پردازش رویدادهای ری‌اکشن به پیام‌ها
    if (update.message_reaction && update.message_reaction.chat) {
      const isTargetChat = checkIsTargetGroup(update.message_reaction.chat.id, env.TELEGRAM_GROUP_ID);
      if (isTargetChat) {
        const rxResult = await normalizeTelegramReaction(env.DB, update.message_reaction);
        if (rxResult) {
          enqueueJob(ctx, env, {
            type: "BROADCAST_REACTION",
            payload: {
              type: "reaction_updated",
              messageId: rxResult.payload.messageId,
              reactions: rxResult.payload.reactions
            },
            handler: async (p, e) => broadcastToChatRoom(e, p)
          });
        }
      }
      return new Response("OK");
    }

    // ۷. پردازش رویداد ویرایش پیام
    if (update.edited_message && update.edited_message.chat) {
      const isTargetChat = checkIsTargetGroup(update.edited_message.chat.id, env.TELEGRAM_GROUP_ID);
      if (isTargetChat) {
        const editResult = await normalizeTelegramEdit(env.DB, update.edited_message);
        if (editResult) {
          enqueueJob(ctx, env, {
            type: "BROADCAST_EDIT",
            payload: {
              type: "message_edited",
              messageId: editResult.payload.messageId,
              tgMsgId: editResult.payload.telegramMessageId,
              text: editResult.payload.text
            },
            handler: async (p, e) => broadcastToChatRoom(e, p)
          });
        }
      }
      return new Response("OK");
    }

    // ۸. پردازش پیام‌های جدید از سوپرگروه اختصاصی
    if (update.message && update.message.chat) {
      const isTargetChat = checkIsTargetGroup(update.message.chat.id, env.TELEGRAM_GROUP_ID);
      if (isTargetChat && !update.message.from?.is_bot) {
        const normalized = await normalizeIncomingTelegramMessage(env.DB, update.message);
        if (normalized && normalized.message) {
          // واگذاری برودکست و ارسال نوتیفیکیشن به صف پس‌زمینه با تلاش مجدد خودکار
          enqueueJob(ctx, env, {
            type: "BROADCAST_NEW_MESSAGE",
            payload: {
              type: "new_message",
              message: normalized.message
            },
            handler: async (p, e) => broadcastToChatRoom(e, p)
          });
        }
      }
      return new Response("OK");
    }
  } catch (err) {
    return new Response("OK");
  }

  return new Response("OK");
}

// بررسی تطابق شناسه چت ورودی با شناسه سوپرگروه مجاز
function checkIsTargetGroup(chatId, targetGroupId) {
  if (!chatId || !targetGroupId) return false;
  const cId = chatId.toString();
  const tId = targetGroupId.toString();

  return (
    cId === tId ||
    cId === tId.replace("-", "-100") ||
    cId.replace("-100", "-") === tId
  );
}

// برودکست رویداد به Durable Object اتاق چت
async function broadcastToChatRoom(env, payload) {
  const roomId = env.CHAT_ROOM.idFromName("global_room");
  await env.CHAT_ROOM.get(roomId).fetch("https://internal/broadcast", {
    method: "POST",
    body: JSON.stringify(payload)
  });
}

// هندلر دکمه‌های اینلاین ادمین
async function handleCallbackQuery(cb, env) {
  const data = cb.data || "";
  if (cb.from.id.toString() !== env.ADMIN_TELEGRAM_ID.toString()) {
    return new Response("Unauthorized", { status: 403 });
  }

  if (data === "admin_users_list") {
    const { results: users } = await env.DB.prepare("SELECT * FROM users WHERE is_approved = 1").all();
    const buttons = (users || []).map(u => [{
      text: `👤 ${u.full_name} (${u.username !== "ندارد" ? '@' + u.username : u.telegram_id})`,
      callback_data: `manage_u:${u.id}`
    }]);
    buttons.push([{ text: "🔄 رفرش لیست", callback_data: "admin_users_list" }]);

    await editTelegramMessageText(env.TELEGRAM_BOT_TOKEN, {
      chatId: cb.message.chat.id,
      messageId: cb.message.message_id,
      text: `⚙️ <b>داشبورد مدیریت کاربران اپلیکیشن</b>\n\n👥 تعداد کل تاییدشده: <b>${users ? users.length : 0}</b> نفر:`,
      replyMarkup: { inline_keyboard: buttons }
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

    await editTelegramMessageText(env.TELEGRAM_BOT_TOKEN, {
      chatId: cb.message.chat.id,
      messageId: cb.message.message_id,
      text,
      replyMarkup: { inline_keyboard: buttons }
    });
    return new Response("OK");
  }

  if (data.startsWith("del_u:")) {
    const targetUserId = data.replace("del_u:", "");
    const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(targetUserId).first();
    if (u) {
      await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(targetUserId).run();
      await env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(targetUserId).run();

      await broadcastToChatRoom(env, { type: "user_kicked", userId: targetUserId, tgId: u.telegram_id });

      await editTelegramMessageText(env.TELEGRAM_BOT_TOKEN, {
        chatId: cb.message.chat.id,
        messageId: cb.message.message_id,
        text: `✅ کاربر <b>${escapeXml(u.full_name)}</b> با موفقیت حذف شد.`,
        replyMarkup: { inline_keyboard: [[{ text: "🔙 بازگشت به لیست", callback_data: "admin_users_list" }]] }
      });
    }
    return new Response("OK");
  }

  const [action, userId] = data.split(":");
  if (action === "approve") {
    await env.DB.prepare("UPDATE users SET is_approved = 1, updated_at = ? WHERE id = ?").bind(Date.now(), userId).run();
    await editTelegramMessageText(env.TELEGRAM_BOT_TOKEN, {
      chatId: cb.message.chat.id,
      messageId: cb.message.message_id,
      text: `${cb.message.text}\n\n✅ دسترسی تایید شد.`
    });
  } else if (action === "reject") {
    await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId).run();
    await editTelegramMessageText(env.TELEGRAM_BOT_TOKEN, {
      chatId: cb.message.chat.id,
      messageId: cb.message.message_id,
      text: `${cb.message.text}\n\n❌ رد شد.`
    });
  }
  return new Response("OK");
}

// هندلر دستور /admin
async function handleAdminCommand(msg, env) {
  if (msg.from.id.toString() !== env.ADMIN_TELEGRAM_ID.toString()) {
    return new Response("Unauthorized", { status: 403 });
  }

  const { results: users } = await env.DB.prepare("SELECT * FROM users WHERE is_approved = 1").all();
  const buttons = (users || []).map(u => [{
    text: `👤 ${u.full_name} (${u.username !== "ندارد" ? '@' + u.username : u.telegram_id})`,
    callback_data: `manage_u:${u.id}`
  }]);
  buttons.push([{ text: "🔄 رفرش لیست", callback_data: "admin_users_list" }]);

  await sendTelegramMessage(env.TELEGRAM_BOT_TOKEN, {
    chatId: env.ADMIN_TELEGRAM_ID,
    text: `⚙️ <b>داشبورد مدیریت کاربران اپلیکیشن</b>\n\n👥 تعداد کل: <b>${users ? users.length : 0}</b> نفر:`,
    replyMarkup: { inline_keyboard: buttons }
  });

  return new Response("OK");
}

// هندلر ثبت‌نام و اتصال ورود دیپ‌لینک (/start auth_)
async function handleAuthStart(msg, env) {
  const token = msg.text.split(" ")[1].replace("auth_", "");
  const tgUser = msg.from;

  const authResult = await processTelegramAuthStart(env, tgUser, token);

  if (!authResult.isAdmin && !authResult.isApproved) {
    await sendTelegramMessage(env.TELEGRAM_BOT_TOKEN, {
      chatId: env.ADMIN_TELEGRAM_ID,
      text: `🔔 <b>درخواست عضویت جدید اپلیکیشن</b>\n\n👤 نام: ${escapeXml(tgUser.first_name || "")}\n🆔 آیدی: @${tgUser.username || "ندارد"}\n🔢 شناسه: <code>${tgUser.id}</code>`,
      replyMarkup: { inline_keyboard: [[{ text: "✅ تایید دسترسی", callback_data: `approve:${authResult.userId}` }, { text: "❌ رد", callback_data: `reject:${authResult.userId}` }]] }
    });
  }

  await sendTelegramMessage(env.TELEGRAM_BOT_TOKEN, {
    chatId: tgUser.id,
    text: authResult.isAdmin
      ? "شما مدیر هستید. دسترسی به اپلیکیشن تایید شد!"
      : "درخواست برای مدیر ارسال شد. پس از تایید مدیر، اپلیکیشن شما فعال خواهد شد."
  });

  return new Response("OK");
}
