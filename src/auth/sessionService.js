/**
 * Zero-Trust Session & Authentication Service
 * Implements cryptographically secure session management with multi-device support.
 */

// تولید توکن تصادفی و غیرقابل حدس با استاندارد ۲۵۶ بیتی Web Crypto
export function generateSecureToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

// تولید شناسه یکتای تصادفی UUIDv4
export function generateId() {
  return crypto.randomUUID();
}

/**
 * ثبت یا بروزرسانی دستگاه کاربر در جدول devices
 */
export async function registerOrUpdateDevice(db, { userId, deviceIdentifier, deviceName, platform = 'android', appVersion = '1.0.0' }) {
  const now = Date.now();
  
  // بررسی وجود قبلی دستگاه برای این کاربر
  const existingDevice = await db.prepare(
    "SELECT id FROM devices WHERE user_id = ? AND device_identifier = ?"
  ).bind(userId, deviceIdentifier).first();

  if (existingDevice) {
    await db.prepare(`
      UPDATE devices 
      SET device_name = ?, platform = ?, app_version = ?, last_seen_at = ?
      WHERE id = ?
    `).bind(deviceName, platform, appVersion, now, existingDevice.id).run();

    return existingDevice.id;
  }

  // ثبت دستگاه جدید در صورت عدم وجود
  const newDeviceId = generateId();
  await db.prepare(`
    INSERT INTO devices (id, user_id, device_identifier, device_name, platform, app_version, created_at, last_seen_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(newDeviceId, userId, deviceIdentifier, deviceName, platform, appVersion, now, now).run();

  return newDeviceId;
}

/**
 * ایجاد یک نشست کاربری جدید و امن با طول عمر مشخص
 */
export async function createSession(db, { userId, deviceId, ttlDays = 90 }) {
  const token = generateSecureToken();
  const now = Date.now();
  const expiresAt = now + (ttlDays * 24 * 60 * 60 * 1000);

  await db.prepare(`
    INSERT INTO sessions (token, user_id, device_id, expires_at, created_at, revoked_at)
    VALUES (?, ?, ?, ?, ?, NULL)
  `).bind(token, userId, deviceId, expiresAt, now).run();

  return {
    token,
    expiresAt,
    createdAt: now
  };
}

/**
 * احراز هویت درخواست ورودی (REST یا WebSocket) بر اساس توکن Bearer
 * تضمین اصل Zero-Trust: هویت کلاینت صرفاً از دیتابیس استخراج می‌شود نه از بدنه درخواست
 */
export async function authenticateRequest(db, request) {
  // ۱. استخراج توکن از هدر Authorization یا پارامتر URL (برای وب‌سوکت)
  let token = null;
  const authHeader = request.headers.get("Authorization");

  if (authHeader && authHeader.startsWith("Bearer ")) {
    token = authHeader.substring(7).trim();
  } else {
    // پشتیبانی از توکن در URL برای هندشیک اولیه وب‌سوکت
    const url = new URL(request.url);
    token = url.searchParams.get("token");
  }

  if (!token) {
    return {
      authenticated: false,
      status: 401,
      error: "missing_token",
      message: "توکن احراز هویت ارسال نشده است."
    };
  }

  // ۲. کوئری جامع برای واکشی نشست، کاربر و دستگاه مربوطه
  const sessionData = await db.prepare(`
    SELECT 
      s.token, s.expires_at, s.created_at AS session_created_at, s.revoked_at,
      u.id AS user_id, u.telegram_id, u.full_name, u.username, u.is_approved, u.is_admin,
      d.id AS device_id, d.device_identifier, d.device_name, d.platform, d.app_version
    FROM sessions s
    JOIN users u ON s.user_id = u.id
    JOIN devices d ON s.device_id = d.id
    WHERE s.token = ?
  `).bind(token).first();

  if (!sessionData) {
    return {
      authenticated: false,
      status: 401,
      error: "invalid_session",
      message: "نشست نامعتبر است یا وجود ندارد."
    };
  }

  // ۳. بررسی ابطال نشست (Revocation Check)
  if (sessionData.revoked_at !== null) {
    return {
      authenticated: false,
      status: 401,
      error: "session_revoked",
      message: "این نشست قبلاً باطل شده است."
    };
  }

  // ۴. بررسی انقضای زمانی نشست (Expiration Check)
  const now = Date.now();
  if (sessionData.expires_at < now) {
    return {
      authenticated: false,
      status: 401,
      error: "session_expired",
      message: "اعتبار نشست شما منقضی شده است. لطفاً مجدداً وارد شوید."
    };
  }

  // ۵. بررسی وضعیت تایید حساب کاربر
  if (!sessionData.is_approved) {
    return {
      authenticated: false,
      status: 403,
      error: "pending_approval",
      message: "حساب کاربری شما هنوز توسط مدیر سیستم تایید نشده است."
    };
  }

  // ۶. بروزرسانی زمان آخرین فعالیت دستگاه در پس‌زمینه
  try {
    await db.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?")
      .bind(now, sessionData.device_id).run();
  } catch (err) {
    // خطای بروزرسانی زمان تاثیری در مجاز بودن ریکوئست ندارد
  }

  return {
    authenticated: true,
    user: {
      id: sessionData.user_id,
      telegramId: sessionData.telegram_id,
      fullName: sessionData.full_name,
      username: sessionData.username,
      isAdmin: Boolean(sessionData.is_admin)
    },
    device: {
      id: sessionData.device_id,
      identifier: sessionData.device_identifier,
      name: sessionData.device_name,
      platform: sessionData.platform
    },
    session: {
      token: sessionData.token,
      expiresAt: sessionData.expires_at
    }
  };
}

/**
 * ابطال یک نشست خاص (خروج کاربر)
 */
export async function revokeSession(db, token) {
  const result = await db.prepare(
    "UPDATE sessions SET revoked_at = ? WHERE token = ? AND revoked_at IS NULL"
  ).bind(Date.now(), token).run();

  return result.meta?.changes > 0;
}

/**
 * ابطال تمام نشست‌های فعال یک کاربر (خروج از تمام دستگاه‌ها)
 */
export async function revokeAllUserSessions(db, userId) {
  const result = await db.prepare(
    "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL"
  ).bind(Date.now(), userId).run();

  return result.meta?.changes > 0;
}
