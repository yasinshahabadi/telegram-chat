// lib/services/notification_service.dart
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  void Function(String? messageId)? onNotificationClick;

  Future<void> init({void Function(String? messageId)? onNotificationTap}) async {
    onNotificationClick = onNotificationTap;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (onNotificationClick != null && response.payload != null) {
          onNotificationClick!(response.payload);
        }
      },
    );

    // ساخت کانال نوتیفیکیشن با اولویت بالا برای اندروید (Heads-Up Banner)
    const androidChannel = AndroidNotificationChannel(
      'chat_messages_channel',
      'پیام‌های جدید چت',
      description: 'اعلان دریافت پیام‌های جدید از تلگرام و وب',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
      await androidPlugin.requestNotificationsPermission();
    }
  }

  // نمایش نوتیفیکیشن پیام جدید همراه با صدا، ویبره و بنر
  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    String? messageId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'chat_messages_channel',
      'پیام‌های جدید چت',
      channelDescription: 'اعلان دریافت پیام‌های جدید از تلگرام و وب',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
      styleInformation: BigTextStyleInformation(body),
    );

    final details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(id, title, body, details, payload: messageId);
  }
}