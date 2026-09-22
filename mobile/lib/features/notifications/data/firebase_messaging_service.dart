import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../../../../config.dart';

/// ثابت‌های کانال اعلان
const String _channelId = 'guysgram_default_channel';
const String _channelName = 'اعلان‌های Guysgram';
const String _channelDesc = 'اعلان پیام‌های دریافتی از سوپرگروه تلگرام';

/// هندلر پیام‌های پس‌زمینه FCM
///
/// ⚠️ نکته مهم: در این تابع **نباید** اعلان نمایش دهیم!
/// چون FCM دارای `notification` payload است و سیستم‌عامل اندروید
/// به‌طور خودکار اعلان را در background/terminated نمایش می‌دهد.
/// اگر اینجا اعلان نمایش دهیم، اعلان تکراری می‌شود.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase باید در isolate جدید مقداردهی اولیه شود
  await Firebase.initializeApp();

  debugPrint('[FCM-BG] Message received: ${message.messageId}');
  debugPrint('[FCM-BG] Data: ${message.data}');

  // اینجا فقط می‌توانید منطق‌های background اجرا کنید:
  // - به‌روزرسانی دیتابیس محلی
  // - ذخیره payload برای پردازش بعدی
  // - شمارش badge
  //
  // اما نمایش اعلان نکنید چون سیستم خودش نمایش می‌دهد.
}

/// سرویس مدیریت اعلان‌های Firebase Cloud Messaging
class FirebaseMessagingService {
  static final FirebaseMessagingService instance =
      FirebaseMessagingService._internal();
  FirebaseMessagingService._internal();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// مقداردهی اولیه Firebase و FCM
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // ۱. راه‌اندازی Firebase
      await Firebase.initializeApp();
      debugPrint('[FCM] Firebase.initializeApp() succeeded');

      // ۲. درخواست مجوز اعلان
      await _requestPermission();

      // ۳. ثبت هندلر پیام‌های پس‌زمینه
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // ۴. تنظیمات Local Notifications (فقط برای کانال، نه برای نمایش)
      await _initLocalNotifications();

      // ۵. گوش دادن به پیام‌ها در حالت foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // ۶. گوش دادن به کلیک روی اعلان
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // ۷. بررسی اعلان اولیه (اگر اپ از حالت terminated باز شده باشد)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      _isInitialized = true;
      debugPrint('[FCM] Initialized successfully');
    } catch (e, st) {
      debugPrint('[FCM ERROR] Init failed: $e');
      debugPrint('[FCM ERROR] Stack: $st');
    }
  }

  /// درخواست مجوز اعلان
  Future<void> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM ERROR] requestPermission: $e');
    }
  }

  /// تنظیمات Local Notifications و ایجاد کانال
  /// (فقط برای اطمینان از وجود کانال؛ اعلان در foreground نمایش نمی‌دهیم)
  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[FCM] Notification tapped: ${response.payload}');
      },
    );

    // ایجاد کانال اعلان در Android
    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
    }
  }

  /// پردازش پیام در حالت foreground
  ///
  /// ⚠️ نکته: در این حالت **نباید اعلان نمایش دهیم**.
  /// کاربر داخل اپ است و پیام را از طریق WebSocket در UI می‌بیند.
  /// اگر اپ روی صفحه‌ای غیر از چت باشد، می‌توانید اینجا یک SnackBar
  /// یا بنر درون‌برنامه‌ای (In-App Banner) نمایش دهید.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground message: ${message.messageId}');
    debugPrint('[FCM] Data: ${message.data}');

    // ❌ هیچ اعلان سیستمی نمایش ندهید.
    // فقط می‌توانید منطق درون‌برنامه‌ای اضافه کنید:
    // - به‌روزرسانی شمارنده unread
    // - نمایش SnackBar
    // - بروزرسانی badge درون‌برنامه‌ای
    //
    // مثال (اختیاری):
    // final data = message.data;
    // InAppNotificationBus.instance.emit(data);
  }

  /// پردازش کلیک روی اعلان (چه در background، چه terminated)
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification opened app: ${message.data}');
    // اینجا می‌توانید ناوبری به صفحه چت را انجام دهید:
    // - push به ChatScreen
    // - scroll به پیام مربوطه با استفاده از messageId
  }

  /// دریافت توکن FCM دستگاه
  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('[FCM] Device Token: $token');
      return token;
    } catch (e) {
      debugPrint('[FCM ERROR] getToken failed: $e');
      return null;
    }
  }

  /// ثبت توکن در سرور Cloudflare
  Future<bool> registerTokenOnServer({
    required String sessionToken,
    required String deviceId,
  }) async {
    try {
      final fcmToken = await getToken();
      if (fcmToken == null) return false;

      final url =
          Uri.parse('${AppConfig.baseUrl}/api/notifications/register-token');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sessionToken',
        },
        body: jsonEncode({
          'fcmToken': fcmToken,
          'deviceId': deviceId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Token registered on server');
        return true;
      } else {
        debugPrint('[FCM ERROR] Server: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[FCM ERROR] Registration failed: $e');
      return false;
    }
  }

  /// لغو ثبت توکن (هنگام logout)
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      debugPrint('[FCM] Token deleted');
    } catch (e) {
      debugPrint('[FCM ERROR] deleteToken failed: $e');
    }
  }
}