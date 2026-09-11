// lib/services/foreground_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/chat_message.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(ChatBackgroundTaskHandler());
}

class ChatBackgroundTaskHandler extends TaskHandler {
  WebSocketChannel? _wsChannel;
  bool _isConnected = false;
  bool _isAppInForeground = true;

  String? _sessionToken;
  String? _userName;
  String? _userId;
  String? _tgId;
  int _lastTimestamp = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // راه‌اندازی نوتیفیکیشن در ایزولیت پس‌زمینه
    await NotificationService().init();

    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString('chat_token');
    _userName = prefs.getString('user_name');
    _userId = prefs.getString('user_id');
    _tgId = prefs.getString('tg_id');
    _lastTimestamp = prefs.getInt('last_msg_time') ?? DateTime.now().millisecondsSinceEpoch;

    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));

      _wsChannel!.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['type'] == 'new_message' && data['message'] != null) {
          final msg = ChatMessage.fromJson(data['message']);
          if (msg.timestamp > _lastTimestamp) {
            _lastTimestamp = msg.timestamp;
            _handleIncomingMessage(msg);
          }
        }
      }, onDone: () {
        _isConnected = false;
        Future.delayed(const Duration(seconds: 4), () => _connectWebSocket());
      }, onError: (_) {
        _isConnected = false;
      });

      if (_userName != null && _userId != null) {
        _wsChannel!.sink.add(jsonEncode({
          "type": "identify",
          "userName": _userName,
          "userId": _userId,
          "tgId": _tgId
        }));
      }

      _isConnected = true;
    } catch (_) {
      _isConnected = false;
    }
  }

  void _handleIncomingMessage(ChatMessage msg) {
    // اگر کاربر در داخل برنامه نیست، اعلان با صدا و ویبره ارسال کن
    if (!_isAppInForeground && msg.senderName != _userName) {
      String notifBody = msg.text;
      if (notifBody.isEmpty) {
        if (msg.mediaType == 'photo') notifBody = '📷 [ارسال تصویر]';
        else if (msg.mediaType == 'video') notifBody = '📹 [ارسال ویدیو]';
        else if (msg.mediaType == 'audio') notifBody = '🎵 [ارسال فایل صوتی]';
        else notifBody = '📁 [ارسال فایل]';
      }

      final title = msg.isFromTelegram ? "📱 تلگرام: ${msg.senderName}" : "🌐 وب: ${msg.senderName}";

      NotificationService().showMessageNotification(
        id: msg.timestamp ~/ 1000,
        title: title,
        body: notifBody,
        messageId: msg.id,
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // ۱. بررسی سلامت سوکت و اتصال مجدد در صورت قطعی
    if (!_isConnected || _wsChannel == null) {
      _connectWebSocket();
    } else {
      // ارسال پینگ زنده به کلودفلر
      _wsChannel?.sink.add(jsonEncode({"type": "presence", "status": _isAppInForeground ? "online" : "offline"}));
    }

    // ۲. پولینگ هوشمند پشتیبان در صورت قطع شدن موقت سوکت
    if (!_isAppInForeground && _lastTimestamp > 0) {
      try {
        final res = await http.get(Uri.parse("${AppConfig.baseUrl}/api/messages?since=$_lastTimestamp"));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List list = data['messages'] ?? [];
          for (var item in list) {
            final m = ChatMessage.fromJson(item);
            if (m.timestamp > _lastTimestamp) {
              _lastTimestamp = m.timestamp;
              _handleIncomingMessage(m);
            }
          }
        }
      } catch (_) {}
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data.containsKey('isForeground')) {
        _isAppInForeground = data['isForeground'] == true;
      }
      if (data.containsKey('user_name')) {
        _userName = data['user_name'];
        _userId = data['user_id'];
        _tgId = data['tg_id'];
      }
      if (data.containsKey('last_msg_time')) {
        _lastTimestamp = data['last_msg_time'];
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _wsChannel?.sink.close();
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

class ForegroundServiceManager {
  static void init() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'telegram_chat_foreground_channel',
        channelName: 'وضعیت سرویس چت',
        channelDescription: 'سرویس پایدار جهت دریافت دائمی پیام‌ها',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000), // اجرای مداوم هر ۱۰ ثانیه در پس‌زمینه
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start({
    required String userName,
    required String userId,
    String? tgId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', userName);
    await prefs.setString('user_id', userId);
    if (tgId != null) await prefs.setString('tg_id', tgId);

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({
        'user_name': userName,
        'user_id': userId,
        'tg_id': tgId,
      });
      return;
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.startService(
      serviceId: 100,
      notificationTitle: 'پیام‌رسان متصل است',
      notificationText: 'در حال دریافت آنلاین پیام‌های گروه',
      callback: startForegroundCallback,
    );
  }

  static void setAppLifecycle(bool isForeground) {
    FlutterForegroundTask.sendDataToTask({'isForeground': isForeground});
  }

  static void syncLastMessageTime(int timestamp) {
    FlutterForegroundTask.sendDataToTask({'last_msg_time': timestamp});
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}