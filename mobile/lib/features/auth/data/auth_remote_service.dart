import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../config.dart';
import '../domain/models/auth_user.dart';

/// نتیجه پاسخ دریافتی از سرور برای تایید دستگاه
class VerifyDeviceResult {
  final String status; // 'ok', 'pending', 'error', 'network_error'
  final AuthUser? user;
  final AuthSession? session;
  final String? message;

  const VerifyDeviceResult({
    required this.status,
    this.user,
    this.session,
    this.message,
  });

  bool get isOk => status == 'ok';
  bool get isPending => status == 'pending';
}

/// سرویس شبکه ارتباط با اندپوینت‌های احراز هویت ورکر کلودفلر
class AuthRemoteService {
  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  AuthRemoteService({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// تایید دستگاه و دریافت نشست
  /// POST /api/auth/verify-device
  Future<VerifyDeviceResult> verifyDevice({
    required String sessionToken,
    required String deviceIdentifier,
    required String deviceName,
  }) async {
    final url = Uri.parse('$_baseUrl/api/auth/verify-device');

    try {
      final response = await _client
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'sessionToken': sessionToken,
              'deviceIdentifier': deviceIdentifier,
              'deviceName': deviceName,
              'platform': 'android',
              'appVersion': '1.0.0',
            }),
          )
          .timeout(_timeout);

      final Map<String, dynamic> data = jsonDecode(response.body);
      final status = data['status']?.toString() ?? 'error';

      if (response.statusCode == 200 && status == 'ok') {
        final userData = data['user'] as Map<String, dynamic>?;
        final sessionData = data['session'] as Map<String, dynamic>?;

        return VerifyDeviceResult(
          status: 'ok',
          user: userData != null ? AuthUser.fromJson(userData) : null,
          session: sessionData != null ? AuthSession.fromJson(sessionData) : null,
        );
      }

      if (response.statusCode == 403 || status == 'pending') {
        return VerifyDeviceResult(
          status: 'pending',
          message: data['message'] as String? ?? 'حساب شما در انتظار تایید مدیر در تلگرام است.',
        );
      }

      return VerifyDeviceResult(
        status: status,
        message: data['message'] as String? ?? 'خطا در تایید نشست.',
      );
    } on SocketException {
      return const VerifyDeviceResult(
        status: 'network_error',
        message: 'خطا در اتصال به اینترنت. لطفاً شبکه خود را بررسی کنید.',
      );
    } on TimeoutException {
      return const VerifyDeviceResult(
        status: 'network_error',
        message: 'مهلت پاسخ سرور به پایان رسید (تایم‌اوت).',
      );
    } catch (e) {
      return VerifyDeviceResult(
        status: 'error',
        message: e.toString(),
      );
    }
  }

  /// بررسی اعتبار نشست فعلی کلاینت با سرور
  /// GET /api/auth/me
  Future<AuthUser?> getMe(String sessionToken) async {
    final url = Uri.parse('$_baseUrl/api/auth/me');

    try {
      final response = await _client.get(
        url,
        headers: {
          ..._headers,
          'Authorization': 'Bearer $sessionToken',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['status'] == 'ok' && data['user'] != null) {
          return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (_) {
      // در صورت خطای شبکه مقدار null بازمی‌گردد تا سیستم تصمیم آفلاین بگیرد
      return null;
    }
  }

  /// ابطال نشست و خروج از حساب در سرور
  /// POST /api/auth/logout
  Future<bool> logout(String sessionToken) async {
    final url = Uri.parse('$_baseUrl/api/auth/logout');

    try {
      final response = await _client.post(
        url,
        headers: {
          ..._headers,
          'Authorization': 'Bearer $sessionToken',
        },
      ).timeout(_timeout);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
