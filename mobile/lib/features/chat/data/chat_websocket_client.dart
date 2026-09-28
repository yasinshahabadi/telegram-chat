import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../config.dart';

enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class ChatWebSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  SocketConnectionState _state = SocketConnectionState.disconnected;
  final _stateController = StreamController<SocketConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  String? _sessionToken;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  bool _lastPresenceOnline = true;

  /// آخرین لحظه‌ای که از سرور چیزی شنیدیم (پیام عادی، pong، online_users...).
  /// در heartbeat از این برای تشخیص «سرور ساکت است» استفاده می‌کنیم.
  DateTime? _lastMessageFromServer;

  /// اگر بیش از این مدت از سرور خبری نشد، اتصال را قطع‌شده تلقی می‌کنیم.
  static const Duration _silenceTimeout = Duration(seconds: 60);

  /// فاصلهٔ ارسال ping.
  static const Duration _heartbeatInterval = Duration(seconds: 25);

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
      _reconnectAttempts > 0
          ? SocketConnectionState.reconnecting
          : SocketConnectionState.connecting,
    );

    try {
      final baseWsUrl = AppConfig.wsUrl;
      final uri = Uri.parse('$baseWsUrl?token=$_sessionToken');

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _updateState(SocketConnectionState.connected);
      _reconnectAttempts = 0;
      _lastMessageFromServer = DateTime.now();

      sendPresence(online: _lastPresenceOnline);

      _subscription?.cancel();
      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onDone: _onConnectionClosed,
        onError: (err) => _onConnectionError(err),
        cancelOnError: true,
      );

      _startHeartbeat();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _onMessageReceived(dynamic raw) {
    _lastMessageFromServer = DateTime.now();
    try {
      final Map<String, dynamic> data = jsonDecode(raw as String);
      _messageController.add(data);
    } catch (_) {}
  }

  void _onConnectionClosed() {
    _stopHeartbeat();
    _cleanupChannel();
    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _onConnectionError(dynamic error) {
    _stopHeartbeat();
    _cleanupChannel();
    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  // ═════════════════════════════════════════════
  //  Heartbeat (ping/pong)
  // ═════════════════════════════════════════════

  /// هر ۲۵ ثانیه ping می‌فرستیم. سرور با pong پاسخ می‌دهد.
  /// اگر ظرف ۶۰ ثانیه هیچ پیامی از سرور نرسد، اتصال را از دست‌رفته
  /// تلقی می‌کنیم و به‌صورت فعال reconnect می‌کنیم.
  ///
  /// این مکانیسم مهم‌ترین راهکار رفع باگ «پیام‌ها بعد از سوئیچ شبکه نمی‌رسند» است:
  /// WebSocket ممکن است در سمت کلاینت هنوز «باز» به نظر برسد، درحالی‌که
  /// از دید سرور یا NAT میانی مدت‌هاست بسته شده است.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isDisposed || !isConnected) return;

      final last = _lastMessageFromServer;
      if (last != null &&
          DateTime.now().difference(last) > _silenceTimeout) {
        debugPrint('[WS] Heartbeat: server silent for >${_silenceTimeout.inSeconds}s, forcing reconnect');
        _stopHeartbeat();
        _cleanupChannel();
        _scheduleReconnect();
        return;
      }

      _send({'type': 'ping'});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ═════════════════════════════════════════════

  void _scheduleReconnect() {
    if (_isDisposed || _sessionToken == null) {
      _updateState(SocketConnectionState.disconnected);
      return;
    }

    _updateState(SocketConnectionState.reconnecting);
    _reconnectTimer?.cancel();

    final delaySeconds = min(pow(2, _reconnectAttempts).toInt(), 15);
    final jitter = (Random().nextDouble() * 500).toInt();
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

  bool sendPresence({required bool online}) {
    _lastPresenceOnline = online;
    return _send({
      'type': 'presence',
      'status': online ? 'online' : 'away',
    });
  }

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

  bool sendDeleteMessage(String messageId) {
    return _send({
      'type': 'delete_message',
      'messageId': messageId,
    });
  }

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

  bool sendPinMessage(String messageId) {
    return _send({
      'type': 'pin_message',
      'messageId': messageId,
    });
  }

  bool sendUnpinMessage() {
    return _send({
      'type': 'unpin_message',
    });
  }

  bool sendTyping() {
    return _send({
      'type': 'typing',
    });
  }

  bool sendMarkRead(List<String> messageIds) {
    return _send({
      'type': 'mark_read',
      'messageIds': messageIds,
    });
  }

  void disconnect() {
    try {
      sendPresence(online: false);
    } catch (_) {}

    _isDisposed = true;
    _sessionToken = null;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _cleanupChannel();
    _updateState(SocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}