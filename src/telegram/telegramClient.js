/**
 * Resilient Telegram Bot API Client
 */

const TELEGRAM_API_BASE = "https://api.telegram.org";
const DEFAULT_TIMEOUT_MS = 10000;

export function escapeXml(str) {
  return String(str || "").replace(/[&<>"']/g, m => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[m]));
}

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

export async function deleteTelegramMessage(token, { chatId, messageId }) {
  return await callTelegramApi(token, "deleteMessage", {
    chat_id: chatId,
    message_id: messageId
  });
}

export async function pinTelegramChatMessage(token, { chatId, messageId }) {
  return await callTelegramApi(token, "pinChatMessage", {
    chat_id: chatId,
    message_id: messageId
  });
}

export async function unpinTelegramChatMessage(token, { chatId }) {
  return await callTelegramApi(token, "unpinChatMessage", {
    chat_id: chatId
  });
}

export async function setTelegramMessageReaction(token, { chatId, messageId, reaction = [] }) {
  return await callTelegramApi(token, "setMessageReaction", {
    chat_id: chatId,
    message_id: messageId,
    reaction
  });
}

export async function getTelegramFile(token, fileId) {
  return await callTelegramApi(token, "getFile", { file_id: fileId });
}

export async function getTelegramUserProfilePhotos(token, userId, limit = 1) {
  return await callTelegramApi(token, "getUserProfilePhotos", {
    user_id: userId,
    limit
  });
}