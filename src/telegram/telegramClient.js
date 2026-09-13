/**
 * Resilient Telegram Bot API Client
 * Features request timeouts, error boundaries, and HTML escaping.
 */

const TELEGRAM_API_BASE = "https://api.telegram.org";
const DEFAULT_TIMEOUT_MS = 10000;

// گریزدهی کاراکترهای خاص HTML برای جلوگیری از خطای پارس تلگرام
export function escapeXml(str) {
  return String(str || "").replace(/[&<>"']/g, m => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[m]));
}

// تابع پایه ارسال درخواست به تلگرام با کنترل تایم‌اوت
async function callTelegramApi(token, method, payload = null, customHeaders = {}) {
  if (!token) {
    return { ok: false, description: "Telegram Bot Token is missing" };
  }

  const url = `${TELEGRAM_API_BASE}/bot${token}/${method}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const isFormData = payload instanceof FormData;
    const options = {
      method: "POST",
      signal: controller.signal,
      headers: isFormData ? customHeaders : { "Content-Type": "application/json", ...customHeaders },
      body: isFormData ? payload : (payload ? JSON.stringify(payload) : undefined)
    };

    const res = await fetch(url, options);
    const data = await res.json().catch(() => ({ ok: false, description: "Invalid JSON response from Telegram" }));
    return data;
  } catch (err) {
    const isTimeout = err.name === "AbortError";
    return {
      ok: false,
      description: isTimeout ? "Telegram request timed out after 10s" : err.message
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * ارسال پیام متنی به چت یا گروه تلگرام
 */
export async function sendTelegramMessage(token, { chatId, text, parseMode = "HTML", replyParameters = null, replyMarkup = null }) {
  const payload = {
    chat_id: chatId,
    text,
    parse_mode: parseMode,
    ...(replyParameters ? { reply_parameters: replyParameters } : {}),
    ...(replyMarkup ? { reply_markup: replyMarkup } : {})
  };
  return await callTelegramApi(token, "sendMessage", payload);
}

/**
 * ویرایش متن پیام قبلی در تلگرام
 */
export async function editTelegramMessageText(token, { chatId, messageId, text, parseMode = "HTML", replyMarkup = null }) {
  const payload = {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: parseMode,
    ...(replyMarkup ? { reply_markup: replyMarkup } : {})
  };
  return await callTelegramApi(token, "editMessageText", payload);
}

/**
 * پین کردن پیام در چت تلگرام
 */
export async function pinTelegramChatMessage(token, { chatId, messageId }) {
  return await callTelegramApi(token, "pinChatMessage", {
    chat_id: chatId,
    message_id: messageId
  });
}

/**
 * حذف پین پیام در چت تلگرام
 */
export async function unpinTelegramChatMessage(token, { chatId }) {
  return await callTelegramApi(token, "unpinChatMessage", {
    chat_id: chatId
  });
}

/**
 * تنظیم ایموجی ری‌اکشن روی پیام تلگرام
 */
export async function setTelegramMessageReaction(token, { chatId, messageId, reaction = [] }) {
  return await callTelegramApi(token, "setMessageReaction", {
    chat_id: chatId,
    message_id: messageId,
    reaction
  });
}

/**
 * دریافت اطلاعات مسیر فایل از تلگرام جهت دانلود
 */
export async function getTelegramFile(token, fileId) {
  return await callTelegramApi(token, "getFile", { file_id: fileId });
}

/**
 * دریافت عکس پروفایل کاربر تلگرام
 */
export async function getTelegramUserProfilePhotos(token, userId, limit = 1) {
  return await callTelegramApi(token, "getUserProfilePhotos", {
    user_id: userId,
    limit
  });
}
