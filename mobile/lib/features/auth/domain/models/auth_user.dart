/// وضعیت‌های مختلف احراز هویت در کلاینت اندروید
enum AuthStatus {
  /// وضعیت اولیه پیش از بررسی نشست
  initial,

  /// کاربر وارد حساب نشده است
  unauthenticated,

  /// حساب کاربری در انتظار تایید مدیر سیستم در تلگرام است
  pendingApproval,

  /// کاربر با موفقیت احراز هویت شده و آنلاین است
  authenticated,

  /// کاربر قبلاً وارد شده اما به دلیل قطعی موقت اینترنت به صورت آفلاین به دیتابیس لوکال دسترسی دارد
  offlineAuthenticated,

  /// بروز خطا در فرآیند احراز هویت
  error,
}

/// مدل داده‌ای مشخصات کاربر احراز هویت شده
class AuthUser {
  final String id;
  final String? telegramId;
  final String fullName;
  final String username;
  final bool isAdmin;
  final bool isApproved;

  const AuthUser({
    required this.id,
    this.telegramId,
    required this.fullName,
    required this.username,
    this.isAdmin = false,
    this.isApproved = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      telegramId: json['telegramId']?.toString() ?? json['telegram_id']?.toString(),
      fullName: json['fullName'] as String? ?? json['full_name'] as String? ?? 'کاربر',
      username: json['username'] as String? ?? 'ندارد',
      isAdmin: json['isAdmin'] == true || json['is_admin'] == 1,
      isApproved: json['isApproved'] == true || json['is_approved'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'telegramId': telegramId,
      'fullName': fullName,
      'username': username,
      'isAdmin': isAdmin,
      'isApproved': isApproved,
    };
  }

  AuthUser copyWith({
    String? id,
    String? telegramId,
    String? fullName,
    String? username,
    bool? isAdmin,
    bool? isApproved,
  }) {
    return AuthUser(
      id: id ?? this.id,
      telegramId: telegramId ?? this.telegramId,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
      isApproved: isApproved ?? this.isApproved,
    );
  }
}

/// مدل داده‌ای نشست کلاینت
class AuthSession {
  final String token;
  final int? expiresAt;
  final String? deviceId;

  const AuthSession({
    required this.token,
    this.expiresAt,
    this.deviceId,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String? ?? '',
      expiresAt: json['expiresAt'] as int? ?? json['expires_at'] as int?,
      deviceId: json['deviceId'] as String? ?? json['device_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'expiresAt': expiresAt,
      'deviceId': deviceId,
    };
  }
}
