import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../config.dart';
import '../domain/models/auth_user.dart';
import 'auth_local_storage.dart';
import 'auth_remote_service.dart';

/// ریپازیتوری و مدیر وضعیت احراز هویت برنامه
class AuthRepository extends ChangeNotifier {
  final AuthLocalStorage _localStorage;
  final AuthRemoteService _remoteService;

  AuthStatus _status = AuthStatus.initial;
  AuthUser? _currentUser;
  String? _pendingSessionToken;
  String? _errorMessage;
  bool _isLoading = false;

  AuthRepository({
    required AuthLocalStorage localStorage,
    required AuthRemoteService remoteService,
  })  : _localStorage = localStorage,
        _remoteService = remoteService;

  AuthStatus get status => _status;
  AuthUser? get currentUser => _currentUser;
  String? get pendingSessionToken => _pendingSessionToken;
  String? get sessionToken => _localStorage.getSessionToken();
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated || _status == AuthStatus.offlineAuthenticated;

  /// مقداردهی اولیه و بررسی وضعیت نشست کاربر هنگام باز شدن برنامه
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final token = _localStorage.getSessionToken();
    final cachedUser = _localStorage.getCachedUser();

    if (token == null || token.isEmpty) {
      _status = AuthStatus.unauthenticated;
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // ۱. اگر اطلاعات کش‌شده وجود دارد، فوراً کاربر را آفلاین وارد کن تا معطل شبکه نماند
    if (cachedUser != null) {
      _currentUser = cachedUser;
      _status = AuthStatus.offlineAuthenticated;
      notifyListeners();
    }

    // ۲. بررسی هم‌زمان اعتبار نشست با ورکر کلودفلر
    try {
      final remoteUser = await _remoteService.getMe(token);

      if (remoteUser != null) {
        _currentUser = remoteUser;
        _status = AuthStatus.authenticated;
        await _localStorage.saveCachedUser(remoteUser);
      } else {
        // در صورت عدم پاسخ معتبر (اگر توکن باطل شده باشد)
        // اگر کاربر کش‌شده داشتیم وضعیت آفلاین حفظ می‌شود، در غیر این صورت خروج
        if (_currentUser == null) {
          await _localStorage.clearAuthData();
          _status = AuthStatus.unauthenticated;
        }
      }
    } catch (_) {
      // در صورت خطای اتصال به اینترنت، وضعیت آفلاین حفظ می‌شود
      if (_currentUser != null) {
        _status = AuthStatus.offlineAuthenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// آغاز فرآیند لاگین تلگرام: تولید توکن و لینک ورود به ربات
  String startTelegramLogin() {
    // تولید یک توکن تصادفی و غیرقابل حدس برای دیپ‌لینک
    final token = const Uuid().v4().replaceAll('-', '') +
        const Uuid().v4().replaceAll('-', '').substring(0, 8);
    _pendingSessionToken = token;
    _errorMessage = null;

    final botUsername = AppConfig.botUsername.replaceAll('@', '');
    return 'https://t.me/$botUsername?start=auth_$token';
  }

  /// بررسی وضعیت تایید دستگاه توسط سرور و تلگرام
  Future<bool> checkVerification() async {
    final token = _pendingSessionToken;
    if (token == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final deviceId = await _localStorage.getOrCreateDeviceIdentifier();
      final deviceName = await _localStorage.getDeviceModelName();

      final result = await _remoteService.verifyDevice(
        sessionToken: token,
        deviceIdentifier: deviceId,
        deviceName: deviceName,
      );

      if (result.isOk && result.user != null) {
        await _localStorage.saveSessionToken(token);
        await _localStorage.saveCachedUser(result.user!);

        _currentUser = result.user;
        _status = AuthStatus.authenticated;
        _pendingSessionToken = null;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      if (result.isPending) {
        _status = AuthStatus.pendingApproval;
        _errorMessage = result.message;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _errorMessage = result.message ?? 'خطا در احراز هویت';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'خطا در ارتباط با سرور: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// انصراف از ورود در انتظار تایید
  void cancelPendingLogin() {
    _pendingSessionToken = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  /// خروج قطعی از حساب کاربری
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    final token = _localStorage.getSessionToken();
    if (token != null && token.isNotEmpty) {
      await _remoteService.logout(token);
    }

    await _localStorage.clearAuthData();
    _currentUser = null;
    _pendingSessionToken = null;
    _status = AuthStatus.unauthenticated;
    _isLoading = false;
    notifyListeners();
  }
}
