import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/auth_user.dart';

/// سرویس مدیریت محلی اطلاعات احراز هویت و مشخصات سخت‌افزاری دستگاه
class AuthLocalStorage {
  static const String _keySessionToken = 'auth_session_token';
  static const String _keyDeviceIdentifier = 'auth_device_identifier';
  static const String _keyCachedUser = 'auth_cached_user';

  final SharedPreferences _prefs;
  final DeviceInfoPlugin _deviceInfoPlugin;

  AuthLocalStorage({
    required SharedPreferences prefs,
    DeviceInfoPlugin? deviceInfoPlugin,
  })  : _prefs = prefs,
        _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  /// ایجاد یا واکشی شناسه پایدار سخت‌افزاری دستگاه برای اندروید
  Future<String> getOrCreateDeviceIdentifier() async {
    final existingId = _prefs.getString(_keyDeviceIdentifier);
    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }

    String deviceId;
    try {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      // استفاده از شناسه اندروید یا تولید UUID در صورت عدم دسترسی
      deviceId = androidInfo.id.isNotEmpty
          ? 'android_${androidInfo.id}'
          : 'android_${const Uuid().v4()}';
    } catch (_) {
      deviceId = 'android_${const Uuid().v4()}';
    }

    await _prefs.setString(_keyDeviceIdentifier, deviceId);
    return deviceId;
  }

  /// نام مدل یا برند دستگاه جهت نمایش در پنل مدیریت
  Future<String> getDeviceModelName() async {
    try {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      final manufacturer = androidInfo.manufacturer;
      final model = androidInfo.model;
      return '$manufacturer $model'.trim();
    } catch (_) {
      return 'Android Device';
    }
  }

  /// دریافت توکن نشست ذخیره‌شده
  String? getSessionToken() {
    return _prefs.getString(_keySessionToken);
  }

  /// ذخیره توکن نشست
  Future<void> saveSessionToken(String token) async {
    await _prefs.setString(_keySessionToken, token);
  }

  /// ذخیره مشخصات کاربر جهت استفاده در حالت آفلاین
  Future<void> saveCachedUser(AuthUser user) async {
    final userJson = jsonEncode(user.toJson());
    await _prefs.setString(_keyCachedUser, userJson);
  }

  /// دریافت مشخصات کش‌شده کاربر
  AuthUser? getCachedUser() {
    final userJson = _prefs.getString(_keyCachedUser);
    if (userJson == null || userJson.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> map = jsonDecode(userJson);
      return AuthUser.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// پاکسازی نشست هنگام خروج از حساب
  Future<void> clearAuthData() async {
    await _prefs.remove(_keySessionToken);
    await _prefs.remove(_keyCachedUser);
    // شناسه دستگاه حذف نمی‌شود تا سخت‌افزار ثابت بماند
  }
}
