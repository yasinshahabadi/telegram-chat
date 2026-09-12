// lib/services/notification_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  void Function(String? messageId)? onNotificationClick;

  // تاریخچه پیام‌های نوتیفیکیشن جاری به سبک تلگرام
  final List<Message> _cachedMessages = [];
  String? _lastSenderName;

  Future<void> init({void Function(String? messageId)? onNotificationTap}) async {
    onNotificationClick = onNotificationTap;

    // استفاده از آیکون جدید اختصاصی برنامه
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (onNotificationClick != null && response.payload != null) {
          onNotificationClick!(response.payload);
        }
      },
    );

    const androidChannel = AndroidNotificationChannel(
      'chat_messages_channel',
      'پیام‌های جدید چت',
      description: 'اعلان دریافت پیام‌های جدید از تلگرام و وب',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
      await androidPlugin.requestNotificationsPermission();
    }
  }

  // دانلود موقت آواتار فرستنده جهت قرار گرفتن در دایره نوتیفیکیشن
  Future<String?> _downloadAvatar(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse("${AppConfig.baseUrl}/api/avatar?userId=$userId"));
      if (res.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final filePath = "${dir.path}/avatar_$userId.jpg";
        final file = File(filePath);
        await file.writeAsBytes(res.bodyBytes);
        return filePath;
      }
    } catch (_) {}
    return null;
  }

  // پاک کردن تاریخچه پیام‌های اعلان هنگام ورود به برنامه
  void clearNotificationHistory() {
    _cachedMessages.clear();
    _lastSenderName = null;
    _localNotifications.cancel(1001);
  }

  // نمایش نوتیفیکیشن تجمیعی به سبک تلگرام (MessagingStyle)
  Future<void> showMessageNotification({
    required String senderName,
    required String body,
    String? senderId,
    String? messageId,
    int? timestamp,
  }) async {
    final msgTime = DateTime.fromMillisecondsSinceEpoch(timestamp ?? DateTime.now().millisecondsSinceEpoch);

    // دانلود یا دریافت کش آواتار فرستنده
    String? avatarPath = await _downloadAvatar(senderId);

    // تعریف شخص فرستنده پیام
    final person = Person(
      name: senderName,
      key: senderId ?? senderName,
      icon: avatarPath != null ? BitmapFilePathAndroidIcon(avatarPath) : null,
    );

    // اگر فرستنده عوض شده باشد، تاریخچه قبلی ریست می‌شود
    if (_lastSenderName != null && _lastSenderName != senderName) {
      _cachedMessages.clear();
    }
    _lastSenderName = senderName;

    // اضافه کردن پیام جدید به لیست پیام‌های همین اعلان
    _cachedMessages.add(Message(body, msgTime, person));

    // حداکstr ۵ پیام آخر نمایش داده می‌شوند
    if (_cachedMessages.length > 5) {
      _cachedMessages.removeAt(0);
    }

    final messagingStyle = MessagingStyleInformation(
      person,
      groupConversation: false,
      conversationTitle: senderName,
      messages: List.from(_cachedMessages),
    );

    final androidDetails = AndroidNotificationDetails(
      'chat_messages_channel',
      'پیام‌های جدید چت',
      channelDescription: 'اعلان دریافت پیام‌های جدید از تلگرام و وب',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: messagingStyle,
      largeIcon: avatarPath != null ? FilePathAndroidBitmap(avatarPath) : null,
      icon: '@mipmap/launcher_icon',
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
      category: AndroidNotificationCategory.message,
    );

    final details = NotificationDetails(android: androidDetails);

    // استفاده از یک ID ثابت (1001) تا پیام‌های جدید در یک اعلان تجمیع شوند و اعلان جداگانه ساخته نشود
    await _localNotifications.show(1001, senderName, body, details, payload: messageId);
  }
}