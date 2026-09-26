import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../../../../config.dart';

const String _channelId = 'guysgram_default_channel_v2';
const String _channelName = 'اعلان‌های Guysgram';
const String _channelDesc = 'اعلان پیام‌های دریافتی از سوپرگروه تلگرام';

const List<String> _legacyChannelIds = [
  'guysgram_default_channel',
  'telegram_chat_messages',
  'telegram_chat',
];

/// ✅ Stream سراسری برای اطلاع‌رسانی به ChatRepository در مورد کلیک روی اعلان
final StreamController<RemoteMessage> _notificationClickController =
    StreamController<RemoteMessage>.broadcast();
Stream<RemoteMessage> get notificationClickStream =>
    _notificationClickController.stream;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM-BG] Message received: ${message.messageId}');
  debugPrint('[FCM-BG] Data: ${message.data}');
}

class FirebaseMessagingService {
  static final FirebaseMessagingService instance =
      FirebaseMessagingService._internal();
  FirebaseMessagingService._internal();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      debugPrint('[FCM] Firebase.initializeApp() succeeded');

      await _requestPermission();

      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      await _initLocalNotifications();

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

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

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      for (final legacyId in _legacyChannelIds) {
        try {
          await androidImpl.deleteNotificationChannel(legacyId);
          debugPrint('[FCM] Deleted legacy channel: $legacyId');
        } catch (e) {
          debugPrint('[FCM] Failed to delete legacy channel $legacyId: $e');
        }
      }

      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
          enableLights: true,
          ledColor: Color(0xFF0088CC),
          showBadge: true,
        ),
      );

      debugPrint('[FCM] Channel created: $_channelId');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground message: ${message.messageId}');
    debugPrint('[FCM] Data: ${message.data}');
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notification opened app: ${message.data}');
    // ✅ انتشار رویداد کلیک روی اعلان
    if (!_notificationClickController.isClosed) {
      _notificationClickController.add(message);
    }
  }

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

  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      debugPrint('[FCM] Token deleted');
    } catch (e) {
      debugPrint('[FCM ERROR] deleteToken failed: $e');
    }
  }
}