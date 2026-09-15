import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// هندلر پس‌زمینه برای پاسخ مستقیم و کلیک روی اعلان‌ها
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // این متد برای پردازش اکشن‌های پس‌زمینه در Isolate مجزا توسط فلاتر استفاده می‌شود
}

/// سرویس مدیریت اعلان‌های بومی اندروید و پاسخ مستقیم
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'telegram_chat_messages';
  static const String _channelName = 'پیام‌های چت';
  static const String _channelDesc = 'اعلان پیام‌های دریافتی از سوپرگروه تلگرام';
  static const String _groupKey = 'com.telegram_chat.MESSAGES';

  Function(String text, String? payload)? onDirectReplyReceived;
  Function(String? payload)? onNotificationTapped;

  NotificationService._internal();

  /// مقداردهی اولیه سرویس اعلان و ثبت کانال‌های اندروید
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

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

    // ایجاد کانال با اولویت بالا در اندروید ۸ به بالا
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
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

  /// درخواست مجوز اعلان در اندروید ۱۳ به بالا (API 33+)
  Future<bool> requestPermission() async {
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final granted = await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// نمایش اعلان پیام جدید با دکمه پاسخ مستقیم (RemoteInput)
  Future<void> showChatNotification({
    required int id,
    required String senderName,
    required String messageText,
    String? payload,
  }) async {
    // تعریف اکشن پاسخ مستقیم (RemoteInput)
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

    // ساخت یا به‌روزرسانی اعلان خلاصه گروه (Summary)
    await _showGroupSummaryNotification();
  }

  /// اعلان خلاصه برای تجمیع و گروه‌بندی هوشمند پیام‌ها
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
      0, // شناسه ثابت برای اعلان خلاصه
      'گفتگوی تلگرام',
      'پیام‌های جدید دریافتی',
      const NotificationDetails(android: summaryDetails),
    );
  }

  /// لغو یک اعلان خاص با شناسه
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// پاکسازی تمام اعلان‌ها (هنگام باز شدن صفحه چت)
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}
