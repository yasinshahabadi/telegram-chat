/**
 * Asynchronous Job Queue & Resilient Task Runner
 * Features Exponential Backoff, jitter, and dual execution (ctx.waitUntil / Cloudflare Queues).
 */

// توقف زمان‌دار کمکی
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * اجرای یک تابع ناهمگام همراه با تلاش مجدد و فاصله نمایی
 * جهت مقاومت در برابر اختلالات موقت شبکه و پکت‌لاس
 */
export async function executeWithRetry(taskFn, { maxRetries = 3, initialDelayMs = 500, backoffFactor = 2 } = {}) {
  let attempt = 0;
  let delay = initialDelayMs;

  while (attempt < maxRetries) {
    try {
      return await taskFn(attempt);
    } catch (err) {
      attempt++;
      if (attempt >= maxRetries) {
        throw err;
      }

      // اضافه کردن مقدار تصادفی (Jitter) جهت جلوگیری از هجوم هم‌زمان تلاش‌های مجدد
      const jitter = Math.random() * 200;
      await sleep(delay + jitter);
      delay *= backoffFactor;
    }
  }
}

/**
 * افزودن تسک به صف اجرای پس‌زمینه
 * در صورتی که صف ابری کلودفلر فعال باشد به صف ارسال می‌شود؛
 * در غیر این صورت از طریق ctx.waitUntil (رایگان و سریع) در پس‌زمینه اجرا می‌گردد.
 */
export function enqueueJob(ctx, env, { type, payload, handler, maxRetries = 3 }) {
  // ۱. اگر صف ابری Cloudflare Queues تعریف شده باشد
  if (env.ASYNC_QUEUE && typeof env.ASYNC_QUEUE.send === "function") {
    ctx.waitUntil(
      env.ASYNC_QUEUE.send({ type, payload }).catch(() => {})
    );
    return;
  }

  // ۲. اجرای تاب‌آور در پس‌زمینه ورکر بدون مسدودسازی پاسخ به کلاینت (پلن رایگان)
  if (ctx && typeof ctx.waitUntil === "function") {
    ctx.waitUntil(
      executeWithRetry(async (attempt) => {
        if (typeof handler === "function") {
          await handler(payload, env, attempt);
        }
      }, { maxRetries }).catch(err => {
        // ثبت خطای پایانی بدون متوقف کردن ورکر
        console.error(`[Background Job Failed: ${type}]`, err.message || err);
      })
    );
  } else {
    // اجرای مستقیم در صورت عدم وجود زمینه ورکر
    executeWithRetry(async () => {
      if (typeof handler === "function") {
        await handler(payload, env, 0);
      }
    }, { maxRetries }).catch(() => {});
  }
}
