import { errorResponse } from "../core/response.js";

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 ساعت

/**
 * دریافت و سرو آواتار کاربر از تلگرام
 * GET /api/users/avatar?userId=xxx
 */
export async function handleGetUserAvatar(request, env) {
  const url = new URL(request.url);
  const userId = url.searchParams.get("userId");

  if (!userId) return errorResponse("شناسه کاربر الزامی است.", 400);

  try {
    const user = await env.DB.prepare(
      "SELECT id, telegram_id, avatar_file_id, avatar_updated_at FROM users WHERE id = ?"
    ).bind(userId).first();

    if (!user || !user.telegram_id) {
      return errorResponse("کاربر یافت نشد.", 404);
    }

    let fileId = user.avatar_file_id;
    const isStale = !user.avatar_updated_at ||
      (Date.now() - user.avatar_updated_at) > CACHE_TTL_MS;

    // اگر file_id قدیمی است یا نداریم، دوباره از تلگرام بگیر
    if (!fileId || isStale) {
      try {
        const photosRes = await fetch(
          `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getUserProfilePhotos?user_id=${user.telegram_id}&limit=1`
        );
        const photosData = await photosRes.json();

        if (photosData.ok && photosData.result.total_count > 0) {
          const sizes = photosData.result.photos[0];
          // بزرگ‌ترین سایز را انتخاب کن
          const best = sizes[sizes.length - 1];
          fileId = best.file_id;

          await env.DB.prepare(
            "UPDATE users SET avatar_file_id = ?, avatar_updated_at = ? WHERE id = ?"
          ).bind(fileId, Date.now(), userId).run();
        } else {
          return errorResponse("آواتار یافت نشد.", 404);
        }
      } catch (_) {
        return errorResponse("خطا در دریافت آواتار.", 500);
      }
    }

    // دریافت مسیر فایل از تلگرام
    const fileRes = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${fileId}`
    );
    const fileData = await fileRes.json();

    if (!fileData.ok || !fileData.result.file_path) {
      return errorResponse("خطا در دریافت فایل.", 404);
    }

    // Stream مستقیم از تلگرام
    const mediaRes = await fetch(
      `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${fileData.result.file_path}`
    );

    const headers = new Headers(mediaRes.headers);
    headers.set("Cache-Control", "public, max-age=86400, immutable");

    return new Response(mediaRes.body, { status: 200, headers });
  } catch (err) {
    return errorResponse("خطای داخلی.", 500, "AVATAR_ERROR", err.message);
  }
}