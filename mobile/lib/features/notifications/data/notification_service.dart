import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// هندلر پس‌زمینه برای پاسخ مستقیم و کلیک روی اعلان‌ها
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // این متد برای پردازش اکشن‌های پس‌زمینه در Isolate مجزا توسط فلاتر استفاده می‌شود
}

/// سرویس مدیریت اعلان‌های بومی اندروید و پاسخ مستقیم
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'guysgram_default_channel_v2';
  static const String _channelName = 'اعلان‌های Guysgram';
  static const String _channelDesc = 'اعلان پیام‌های دریافتی از سوپرگروه تلگرام';
  static const String _groupKey = 'com.telegram_chat.MESSAGES';

  static const List<String> _legacyChannelIds = [
    'telegram_chat_messages',
    'guysgram_default_channel',
    'telegram_chat',
  ];

  Function(String text, String? payload)? onDirectReplyReceived;
  Function(String? payload)? onNotificationTapped;

  NotificationService._internal();

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'action_reply' && response.input != null) {
          onDirectReplyReceived?.call(response.input!, response.payload);
        } else {
          onNotificationTapped?.call(response.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      for (final legacyId in _legacyChannelIds) {
        try {
          await androidImplementation.deleteNotificationChannel(legacyId);
        } catch (_) {}
      }

      await androidImplementation.createNotificationChannel(
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
    }
  }

  Future<bool> requestPermission() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final granted =
          await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  Future<void> showChatNotification({
    required int id,
    required String senderName,
    required String messageText,
    String? payload,
  }) async {
    const replyAction = AndroidNotificationAction(
      'action_reply',
      'پاسخ',
      inputs: [
        AndroidNotificationActionInput(
          label: 'پاسخ خود را بنویسید...',
        ),
      ],
      showsUserInterface: false,
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      groupKey: _groupKey,
      category: AndroidNotificationCategory.message,
      actions: const [replyAction],
      showWhen: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        messageText,
        contentTitle: senderName,
        summaryText: 'پیام جدید',
      ),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      senderName,
      messageText,
      notificationDetails,
      payload: payload,
    );

    await _showGroupSummaryNotification();
  }

  /// ✅ اعلان خلاصه برای پیام‌های از دست رفته در حین آفلاین بودن
  /// این متد هنگام sync شدن مجدد فراخوانی می‌شود تا اگر FCM نتوانسته
  /// پیام را برساند، کاربر حداقل یک اعلان خلاصه دریافت کند.
  Future<void> showMissedMessagesNotification({
    required int count,
    String? sender,
    String? text,
  }) async {
    final title = count == 1 ? (sender ?? 'پیام جدید') : '$count پیام جدید';
    final body = text ?? 'برای مشاهده وارد برنامه شوید';

    // شناسه ثابت برای تجمیع اعلان‌های missed
    const notificationId = 99001;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'پیام‌های از دست رفته',
      ),
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showGroupSummaryNotification() async {
    const summaryDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      groupKey: _groupKey,
      setAsGroupSummary: true,
    );

    await _notificationsPlugin.show(
      0,
      'گفتگوی تلگرام',
      'پیام‌های جدید دریافتی',
      const NotificationDetails(android: summaryDetails),
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}