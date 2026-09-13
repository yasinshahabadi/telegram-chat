/**
 * Standard HTTP & JSON Response Utilities
 * Provides unified responses, error schemas, and CORS handling.
 */

// هدرهای استاندارد امنیتی CORS برای ارتباط کلاینت اندروید با ورکر
export function getCorsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With, X-Device-Identifier",
    "Access-Control-Max-Age": "86400",
  };
}

// تولید پاسخ موفق JSON با هدرهای استاندارد
export function jsonResponse(data, status = 200, customHeaders = {}) {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    ...getCorsHeaders(),
    ...customHeaders
  });

  return new Response(JSON.stringify(data), {
    status,
    headers
  });
}

// تولید پاسخ خطای ساختارمند JSON
export function errorResponse(message, status = 400, code = "BAD_REQUEST", details = null) {
  const payload = {
    ok: false,
    error: {
      code,
      message,
      ...(details ? { details } : {})
    }
  };

  return jsonResponse(payload, status);
}

// پاسخ سریع به درخواست‌های Preflight (OPTIONS)
export function handleCorsOptions() {
  return new Response(null, {
    status: 204,
    headers: getCorsHeaders()
  });
}
