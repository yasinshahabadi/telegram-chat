import { jsonResponse, errorResponse, handleCorsOptions } from "./response.js";

/**
 * Lightweight Zero-Dependency Router for Cloudflare Workers
 * Supports HTTP method matching, middleware chains, and global error handling.
 */
export class Router {
  constructor() {
    this.routes = [];
    this.middlewares = [];
  }

  // ثبت میدلور سراسری
  use(middleware) {
    this.middlewares.push(middleware);
    return this;
  }

  // ثبت مسیر GET
  get(path, handler) {
    this.routes.push({ method: "GET", path, handler });
    return this;
  }

  // ثبت مسیر POST
  post(path, handler) {
    this.routes.push({ method: "POST", path, handler });
    return this;
  }

  // ثبت مسیر PUT
  put(path, handler) {
    this.routes.push({ method: "PUT", path, handler });
    return this;
  }

  // ثبت مسیر DELETE
  delete(path, handler) {
    this.routes.push({ method: "DELETE", path, handler });
    return this;
  }

  // پردازش و توزیع درخواست ورودی ورکر
  async handle(request, env, ctx) {
    // ۱. پاسخ خودکار به درخواست‌های OPTIONS برای هدرهای CORS
    if (request.method === "OPTIONS") {
      return handleCorsOptions();
    }

    const url = new URL(request.url);
    const pathname = url.pathname;
    const method = request.method;

    try {
      // ۲. اجرای میدلورهای سراسری
      for (const middleware of this.middlewares) {
        const result = await middleware(request, env, ctx);
        if (result instanceof Response) {
          return result;
        }
      }

      // ۳. تطبیق مسیر و متد
      for (const route of this.routes) {
        if (route.method === method && route.path === pathname) {
          return await route.handler(request, env, ctx);
        }
      }

      // ۴. در صورت عدم تطابق مسیر
      return errorResponse(`مسیر درخواستی '${pathname}' با متد ${method} یافت نشد.`, 404, "NOT_FOUND");
    } catch (err) {
      // ۵. خطایاب سراسری برای جلوگیری از قطعی کامل ورکر
      return errorResponse(
        "خطای داخلی در سرور رخ داد.",
        500,
        "INTERNAL_SERVER_ERROR",
        err.message || String(err)
      );
    }
  }
}
