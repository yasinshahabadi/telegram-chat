import { jsonResponse, errorResponse } from "../core/response.js";
import { authenticateRequest } from "../auth/sessionService.js";

/**
 * Sequential Sync Engine Controller
 * Manages incremental delta syncs using the sync_events cursor log.
 */

/**
 * دریافت دسته‌ای رویدادهای جدید پس از نشانگر مشخص‌شده
 * GET /api/sync?cursor=100&limit=50
 */
export async function handleSyncEvents(request, env) {
  // ۱. اعتبارسنجی نشست بر پایه اصل Zero-Trust
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  const url = new URL(request.url);
  const afterCursor = Math.max(Number(url.searchParams.get("cursor")) || 0, 0);
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit")) || 50, 1), 100);

  try {
    // ۲. واکشی رویدادهای بزرگتر از نشانگر کلاینت به ترتیب صعودی
    const { results: rawEvents } = await env.DB.prepare(`
      SELECT cursor, event_type, entity_id, payload_json, created_at
      FROM sync_events
      WHERE cursor > ?
      ORDER BY cursor ASC
      LIMIT ?
    `).bind(afterCursor, limit).all();

    // ۳. پارس کردن امن payload ذخیره‌شده برای هر رویداد
    const events = (rawEvents || []).map(row => {
      let payload = null;
      try {
        payload = JSON.parse(row.payload_json);
      } catch (err) {
        payload = { raw: row.payload_json };
      }

      return {
        cursor: row.cursor,
        eventType: row.event_type,
        entityId: row.entity_id,
        payload,
        createdAt: row.created_at
      };
    });

    // ۴. دریافت آخرین نشانگر ثبت‌شده در کل سیستم
    const maxRow = await env.DB.prepare(
      "SELECT MAX(cursor) AS max_cursor FROM sync_events"
    ).first();
    const systemMaxCursor = maxRow?.max_cursor || 0;

    const latestReturnedCursor = events.length > 0 
      ? events[events.length - 1].cursor 
      : afterCursor;

    const hasMore = latestReturnedCursor < systemMaxCursor;

    return jsonResponse({
      ok: true,
      events,
      latestCursor: latestReturnedCursor,
      systemMaxCursor,
      hasMore
    });
  } catch (err) {
    return errorResponse("خطا در واکشی رویدادهای همگام‌سازی.", 500, "SYNC_ERROR", err.message);
  }
}

/**
 * دریافت سریع آخرین شماره نشانگر سرور جهت بررسی وضعیت آفلاین
 * GET /api/sync/latest-cursor
 */
export async function handleGetLatestCursor(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return errorResponse(auth.message, auth.status, auth.error);
  }

  try {
    const row = await env.DB.prepare(
      "SELECT MAX(cursor) AS max_cursor FROM sync_events"
    ).first();

    return jsonResponse({
      ok: true,
      latestCursor: row?.max_cursor || 0
    });
  } catch (err) {
    return errorResponse("خطا در بررسی نشانگر سرور.", 500, "SYNC_ERROR", err.message);
  }
}
