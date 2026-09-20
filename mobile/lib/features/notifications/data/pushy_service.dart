import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pushy_flutter/pushy_flutter.dart';
import '../../../../config.dart';

/// لیسنر پس‌زمینه برای پردازش و نمایش اعلان هنگام بسته بودن اپلیکیشن
@pragma('vm:entry-point')
void backgroundPushyNotificationListener(Map<String, dynamic> data) {
  debugPrint('[PUSHY] Received background push: $data');
  final String title = data['title']?.toString() ?? 'Guysgram';
  final String message = data['message']?.toString() ?? data['text']?.toString() ?? 'پیام جدید دریافت شد';

  Pushy.notify(title, message, data);
  Pushy.clearBadge();
}

/// سرویس مدیریت اعلان‌های مستقل Pushy در کلاینت فلاتر
class PushyService {
  static final PushyService instance = PushyService._internal();
  PushyService._internal();

  bool _isInitialized = false;

  /// مقداردهی اولیه و فعال‌سازی گوش دادن به نوتیفیکیشن‌ها
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      Pushy.listen();
      Pushy.setNotificationListener(backgroundPushyNotificationListener);
      debugPrint('[PUSHY] Listener started successfully');
    } catch (e) {
      debugPrint('[PUSHY ERROR] Failed to start listener: $e');
    }
  }

  /// ثبت توکن دستگاه در سرورهای پوشی و ذخیره در کلودفلر
  Future<String?> registerDeviceToken({
    required String sessionToken,
    required String deviceId,
  }) async {
    try {
      final String deviceToken = await Pushy.register();
      debugPrint('[PUSHY] Device Token: $deviceToken');

      final url = Uri.parse('${AppConfig.baseUrl}/api/notifications/register-token');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sessionToken',
        },
        body: jsonEncode({
          'fcmToken': deviceToken,
          'deviceId': deviceId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[PUSHY] Token registered on Cloudflare server successfully');
        return deviceToken;
      } else {
        debugPrint('[PUSHY ERROR] Server returned: ${response.body}');
      }
    } catch (e) {
      debugPrint('[PUSHY ERROR] Registration failed: $e');
    }
    return null;
  }
}
