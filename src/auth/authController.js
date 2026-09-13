import {
  authenticateRequest,
  registerOrUpdateDevice,
  revokeSession,
  generateId
} from "./sessionService.js";

/**
 * اندپوینت تایید و ثبت دستگاه و بررسی وضعیت نشست
 * POST /api/auth/verify-device
 */
export async function handleVerifyDevice(request, env) {
  try {
    const body = await request.json();
    const { sessionToken, fingerprint, deviceIdentifier, deviceName, platform = 'android', appVersion = '1.0.0' } = body;

    // پشتیبانی هم‌زمان از شناسه جدید deviceIdentifier یا fingerprint نسخه قبلی
    const finalDeviceIdentifier = deviceIdentifier || fingerprint;

    if (!sessionToken || !finalDeviceIdentifier) {
      return Response.json({
        status: "error",
        error: "missing_fields",
        message: "توکن نشست و شناسه سخت‌افزاری دستگاه الزامی است."
      }, { status: 400 });
    }

    // واکشی نشست و کاربر متناظر
    const session = await env.DB.prepare(`
      SELECT s.token, s.user_id, s.device_id, s.expires_at, s.revoked_at,
             u.id AS user_id, u.telegram_id, u.full_name, u.username, u.is_approved, u.is_admin
      FROM sessions s
      JOIN users u ON s.user_id = u.id
      WHERE s.token = ?
    `).bind(sessionToken).first();

    if (!session) {
      return Response.json({ status: "not_found", message: "نشست یافت نشد." }, { status: 401 });
    }

    if (session.revoked_at !== null) {
      return Response.json({ status: "revoked", message: "این نشست باطل شده است." }, { status: 401 });
    }

    if (session.expires_at && session.expires_at < Date.now()) {
      return Response.json({ status: "expired", message: "اعتبار این نشست منقضی شده است." }, { status: 401 });
    }

    // اگر کاربر هنوز توسط ادمین تایید نشده باشد
    if (!session.is_approved) {
      return Response.json({
        status: "pending",
        message: "حساب شما در انتظار تایید ادمین در تلگرام است."
      }, { status: 403 });
    }

    // ثبت یا بروزرسانی دستگاه در جدول devices
    const deviceId = await registerOrUpdateDevice(env.DB, {
      userId: session.user_id,
      deviceIdentifier: finalDeviceIdentifier,
      deviceName: deviceName || "Android Phone",
      platform,
      appVersion
    });

    // در صورتی که نشست به این دستگاه متصل نشده باشد، آن را متصل و زمان انقضا (۹۰ روزه) تنظیم می‌کنیم
    const ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;
    const expiresAt = session.expires_at || (Date.now() + ninetyDaysMs);

    await env.DB.prepare(`
      UPDATE sessions 
      SET device_id = ?, expires_at = ?
      WHERE token = ?
    `).bind(deviceId, expiresAt, sessionToken).run();

    return Response.json({
      status: "ok",
      user: {
        id: session.user_id,
        telegramId: session.telegram_id,
        fullName: session.full_name,
        username: session.username,
        isAdmin: Boolean(session.is_admin)
      },
      device: {
        id: deviceId,
        identifier: finalDeviceIdentifier,
        platform
      },
      session: {
        token: sessionToken,
        expiresAt
      }
    });
  } catch (error) {
    return Response.json({ status: "error", message: error.message }, { status: 500 });
  }
}

/**
 * اندپوینت بررسی اعتبار نشست جاری و دریافت مشخصات کاربر
 * GET /api/auth/me
 */
export async function handleGetMe(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return Response.json({
      status: "error",
      error: auth.error,
      message: auth.message
    }, { status: auth.status });
  }

  return Response.json({
    status: "ok",
    user: auth.user,
    device: auth.device,
    session: auth.session
  });
}

/**
 * اندپوینت خروج و ابطال نشست جاری
 * POST /api/auth/logout
 */
export async function handleLogout(request, env) {
  const auth = await authenticateRequest(env.DB, request);
  if (!auth.authenticated) {
    return Response.json({
      status: "error",
      error: auth.error,
      message: auth.message
    }, { status: auth.status });
  }

  await revokeSession(env.DB, auth.session.token);

  return Response.json({
    status: "ok",
    message: "نشست جاری با موفقیت باطل و خروج انجام شد."
  });
}

/**
 * پردازش رویداد شروع ورود تلگرام (/start auth_<token>)
 * ثبت یا اتصال کاربر تلگرام به نشست ایجاد شده
 */
export async function processTelegramAuthStart(env, tgUser, token) {
  const now = Date.now();
  const isAdmin = tgUser.id.toString() === env.ADMIN_TELEGRAM_ID.toString();

  // ۱. بررسی اینکه آیا کاربر قبلاً در جدول users وجود داشته است؟
  let user = await env.DB.prepare(
    "SELECT id, is_approved, is_admin FROM users WHERE telegram_id = ?"
  ).bind(tgUser.id.toString()).first();

  let userId;
  if (user) {
    userId = user.id;
    // بروزرسانی نام و یوزرنیم کاربر موجود
    await env.DB.prepare(`
      UPDATE users 
      SET full_name = ?, username = ?, updated_at = ?
      WHERE id = ?
    `).bind(
      `${tgUser.first_name || ""} ${tgUser.last_name || ""}`.trim(),
      tgUser.username || "ندارد",
      now,
      userId
    ).run();
  } else {
    // ایجاد رکورد جدید برای کاربر نخستین‌بار
    userId = generateId();
    await env.DB.prepare(`
      INSERT INTO users (id, telegram_id, full_name, username, is_approved, is_admin, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      userId,
      tgUser.id.toString(),
      `${tgUser.first_name || ""} ${tgUser.last_name || ""}`.trim(),
      tgUser.username || "ندارد",
      isAdmin ? 1 : 0,
      isAdmin ? 1 : 0,
      now,
      now
    ).run();
  }

  // ۲. ایجاد دستگاه اولیه موقت در صورت لزوم جهت رعایت کلید خارجی (تا زمان تایید کلاینت)
  const tempDeviceId = generateId();
  await env.DB.prepare(`
    INSERT OR IGNORE INTO devices (id, user_id, device_identifier, device_name, platform, app_version, created_at, last_seen_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(tempDeviceId, userId, `pending_${token.substring(0, 8)}`, "Mobile Client", "android", "1.0.0", now, now).run();

  // ۳. درج نشست جدید در جدول sessions با ارجاع به دستگاه و کاربر
  const defaultTtl = 90 * 24 * 60 * 60 * 1000;
  await env.DB.prepare(`
    INSERT OR REPLACE INTO sessions (token, user_id, device_id, expires_at, created_at, revoked_at)
    VALUES (?, ?, ?, ?, ?, NULL)
  `).bind(token, userId, tempDeviceId, now + defaultTtl, now).run();

  return {
    userId,
    isAdmin,
    isApproved: user ? Boolean(user.is_approved) : isAdmin
  };
}
