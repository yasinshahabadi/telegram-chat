import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../config.dart';

/// وضعیت‌های اتصال وب‌سوکت
enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// کلاینت وب‌سوکت بلادرنگ چت با پشتیبانی از اتصال مجدد هوشمند
class ChatWebSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  SocketConnectionState _state = SocketConnectionState.disconnected;
  final _stateController = StreamController<SocketConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  String? _sessionToken;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  Stream<SocketConnectionState> get stateStream => _stateController.stream;
  SocketConnectionState get state => _state;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _state == SocketConnectionState.connected;

  void _updateState(SocketConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// اتصال به وب‌سوکت با توکن نشست معتبر
  Future<void> connect(String sessionToken) async {
    _sessionToken = sessionToken;
    _isDisposed = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();

    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (_isDisposed || _sessionToken == null) return;

    _updateState(
      _reconnectAttempts > 0 ? SocketConnectionState.reconnecting : SocketConnectionState.connecting,
    );

    try {
      final baseWsUrl = AppConfig.wsUrl;
      final uri = Uri.parse('$baseWsUrl?token=$_sessionToken');

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _updateState(SocketConnectionState.connected);
      _reconnectAttempts = 0; // ریست تعداد تلاش‌ها پس از اتصال موفق

      _subscription?.cancel();
      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onConnectionClosed,
        onError: (err) => _onConnectionError(err),
        cancelOnError: true,
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessageReceived(dynamic raw) {
    try {
      final Map<String, dynamic> data = jsonDecode(raw as String);
      _messageController.add(data);
    } catch (_) {}
  }

  void _onConnectionClosed() {
    _cleanupChannel();
    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _onConnectionError(dynamic error) {
    _cleanupChannel();
    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  /// زمان‌بندی تلاش مجدد برای اتصال با فاصله نمایی (Exponential Backoff)
  void _scheduleReconnect() {
    if (_isDisposed || _sessionToken == null) {
      _updateState(SocketConnectionState.disconnected);
      return;
    }

    _updateState(SocketConnectionState.reconnecting);
    _reconnectTimer?.cancel();

    // محاسبه تاخیر با فاصله نمایی: 1s, 2s, 4s, 8s تا سقف 15 ثانیه
    final delaySeconds = min(pow(2, _reconnectAttempts).toInt(), 15);
    final jitter = (Random().nextDouble() * 500).toInt(); // تصادفی‌سازی میلی‌ثانیه‌ای
    final totalDelay = Duration(seconds: delaySeconds, milliseconds: jitter);

    _reconnectAttempts++;

    _reconnectTimer = Timer(totalDelay, () {
      if (!_isDisposed) {
        _establishConnection();
      }
    });
  }

  void _cleanupChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  // ==========================================
  // متدهای ارسال رویدادها از طریق سوکت
  // ==========================================

  bool _send(Map<String, dynamic> payload) {
    if (_channel != null && _state == SocketConnectionState.connected) {
      try {
        _channel!.sink.add(jsonEncode(payload));
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// ارسال پیام جدید متنی
  bool sendChatMessage({
    required String text,
    String? clientMessageId,
    Map<String, dynamic>? replyTo,
  }) {
    return _send({
      'type': 'chat_message',
      'text': text,
      'clientMessageId': clientMessageId,
      if (replyTo != null) 'replyTo': replyTo,
    });
  }

  /// ارسال ویرایش متن پیام
  bool sendEditMessage({
    required String messageId,
    required String newText,
  }) {
    return _send({
      'type': 'edit_message',
      'messageId': messageId,
      'newText': newText,
    });
  }

  /// ارسال تغییر ری‌اکشن (اموجی)
  bool sendToggleReaction({
    required String messageId,
    required String emoji,
  }) {
    return _send({
      'type': 'toggle_reaction',
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  /// ارسال پین کردن پیام
  bool sendPinMessage(String messageId) {
    return _send({
      'type': 'pin_message',
      'messageId': messageId,
    });
  }

  /// ارسال حذف پین پیام
  bool sendUnpinMessage() {
    return _send({
      'type': 'unpin_message',
    });
  }

  /// ارسال رویداد در حال تایپ
  bool sendTyping() {
    return _send({
      'type': 'typing',
    });
  }

  /// ارسال وضعیت خوانده شدن پیام‌ها
  bool sendMarkRead(List<String> messageIds) {
    return _send({
      'type': 'mark_read',
      'messageIds': messageIds,
    });
  }

  /// قطع اتصال و آزادسازی منابع
  void disconnect() {
    _isDisposed = true;
    _sessionToken = null;
    _reconnectTimer?.cancel();
    _cleanupChannel();
    _updateState(SocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}
