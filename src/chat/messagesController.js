import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";

/**
 * کنترلر ماژولار تاریخچه و پیام‌های چت
 */

/**
 * اندپوینت دریافت تاریخچه پیام‌ها با صفحه‌بندی
 * GET /api/messages?since=...&before=...&limit=...
 */
export async function handleGetMessages(request, env) {
  // ۱. اعتبارسنجی نشست طبق اصل Zero-Trust
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  const url = new URL(request.url);
  const messageId = url.searchParams.get("id");
  const since = url.searchParams.get("since");
  const before = url.searchParams.get("before");
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit")) || 35, 1), 50);

  try {
    let messages = [];

    // کوئری پایه با اتصال به جدول کاربران برای استخراج نام واقعی و عکس
    const baseQuery = `
      SELECT 
        m.id, m.client_message_id, m.sender_id, m.telegram_message_id,
        m.reply_to_message_id, m.text, m.is_from_telegram, m.is_pinned,
        m.is_edited, m.created_at, m.updated_at, m.deleted_at,
        u.full_name AS sender_name, u.username AS sender_username
      FROM messages m
      LEFT JOIN users u ON m.sender_id = u.id
      WHERE m.deleted_at IS NULL
    `;

    if (messageId) {
      const msg = await env.DB.prepare(`${baseQuery} AND m.id = ? LIMIT 1`).bind(messageId).first();
      messages = msg ? [msg] : [];
    } else if (since && !isNaN(Number(since))) {
      const stmt = await env.DB.prepare(
        `${baseQuery} AND m.created_at > ? ORDER BY m.created_at ASC LIMIT ?`
      ).bind(Number(since), limit).all();
      messages = stmt.results || [];
    } else if (before && !isNaN(Number(before))) {
      const stmt = await env.DB.prepare(
        `${baseQuery} AND m.created_at < ? ORDER BY m.created_at DESC LIMIT ?`
      ).bind(Number(before), limit).all();
      messages = stmt.results ? stmt.results.reverse() : [];
    } else {
      // حالت پیش‌فرض: آخرین پیام‌ها
      const stmt = await env.DB.prepare(
        `${baseQuery} ORDER BY m.created_at DESC LIMIT ?`
      ).bind(limit).all();
      messages = stmt.results ? stmt.results.reverse() : [];
    }

    // واکشی پیام پین‌شده فعلی
    const pinned = await env.DB.prepare(
      `${baseQuery} AND m.is_pinned = 1 ORDER BY m.created_at DESC LIMIT 1`
    ).first();

    return jsonResponse({
      ok: true,
      messages,
      pinned: pinned || null
    });
  } catch (err) {
    return errorResponse("خطا در دریافت پیام‌ها از پایگاه داده.", 500, "DB_ERROR", err.message);
  }
}
