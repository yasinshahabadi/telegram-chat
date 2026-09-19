import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'chat_websocket_client.dart';

/// ریپازیتوری چت مجهز به لاگ‌های زنده عیب‌یابی
class ChatRepository extends ChangeNotifier {
  final LocalChatDao _localDao;
  final ChatWebSocketClient _socketClient;

  List<ChatMessageModel> _messages = [];
  ChatMessageModel? _pinnedMessage;
  String? _typingUserName;
  Timer? _typingTimer;
  bool _isLoading = false;

  StreamSubscription? _socketSubscription;
  StreamSubscription? _socketStateSubscription;

  ChatRepository({
    required LocalChatDao localDao,
    required ChatWebSocketClient socketClient,
  })  : _localDao = localDao,
        _socketClient = socketClient;

  List<ChatMessageModel> get messages => _messages;
  ChatMessageModel? get pinnedMessage => _pinnedMessage;
  String? get typingUserName => _typingUserName;
  bool get isLoading => _isLoading;
  SocketConnectionState get connectionState => _socketClient.state;

  Future<void> initialize(AuthUser currentUser) async {
    debugPrint('[CHAT] Initializing ChatRepository for user: ${currentUser.fullName} (${currentUser.id})');
    _isLoading = true;
    notifyListeners();

    try {
      await loadLocalMessages();

      _socketStateSubscription?.cancel();
      _socketStateSubscription = _socketClient.stateStream.listen((state) {
        debugPrint('[CHAT] Socket state changed to: $state');
        if (state == SocketConnectionState.connected) {
          processPendingQueue();
        }
        notifyListeners();
      });

      _socketSubscription?.cancel();
      _socketSubscription = _socketClient.messageStream.listen((event) {
        debugPrint('[CHAT] Incoming socket event: ${event['type']}');
        _handleIncomingSocketEvent(event, currentUser);
      });
    } catch (e) {
      debugPrint('[CHAT ERROR] Error in initialize: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLocalMessages({int limit = 50}) async {
    try {
      final rawList = await _localDao.getMessagesList(limit: limit);
      _messages = rawList.map((m) => ChatMessageModel.fromDbMap(m)).toList();
      debugPrint('[CHAT] Loaded ${_messages.length} messages from local SQLite');

      try {
        _pinnedMessage = _messages.firstWhere((m) => m.isPinned);
      } catch (_) {
        _pinnedMessage = null;
      }
    } catch (e) {
      debugPrint('[CHAT ERROR] Failed to load messages from SQLite: $e');
      _messages = [];
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String text,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    debugPrint('[CHAT] -> sendMessage called with text: "$text"');
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = const Uuid().v4();
    final clientMessageId = const Uuid().v4();

    final newMessage = ChatMessageModel(
      id: messageId,
      clientMessageId: clientMessageId,
      senderId: currentUser.id,
      senderName: currentUser.fullName,
      text: text,
      isFromTelegram: false,
      replyToMessageId: replyTo?.id,
      replyToName: replyTo?.senderName,
      replyToText: replyTo?.text,
      status: MessageStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    // ۱. نمایش آنی و تضمینی در بالای لیست (Optimistic UI)
    _messages.insert(0, newMessage);
    notifyListeners();
    debugPrint('[CHAT] Message inserted into memory list. Total in UI: ${_messages.length}');

    // ۲. درج در دیتابیس محلی با هندل کردن خطا
    try {
      await _localDao.saveMessage(newMessage.toDbMap());
      debugPrint('[CHAT] Message saved to SQLite database successfully');
    } catch (dbError) {
      debugPrint('[CHAT ERROR] Failed to save message to SQLite: $dbError');
    }

    // ۳. ذخیره در صف کارهای معلق آفلاین
    try {
      final payloadJson = jsonEncode({
        'messageId': messageId,
        'clientMessageId': clientMessageId,
        'text': text,
        'replyTo': replyTo != null
            ? {
                'id': replyTo.id,
                'name': replyTo.senderName,
                'text': replyTo.text,
                'tgMsgId': replyTo.telegramMessageId,
              }
            : null,
      });
      await _localDao.enqueuePendingAction(messageId, 'send_message', payloadJson);
      debugPrint('[CHAT] Pending action enqueued');
    } catch (qError) {
      debugPrint('[CHAT ERROR] Failed to enqueue pending action: $qError');
    }

    // ۴. ارسال از طریق وب‌سوکت در صورت آنلاین بودن
    if (_socketClient.isConnected) {
      debugPrint('[CHAT] Socket is CONNECTED. Sending chat_message frame...');
      final sent = _socketClient.sendChatMessage(
        text: text,
        clientMessageId: clientMessageId,
        replyTo: replyTo != null
            ? {
                'id': replyTo.id,
                'name': replyTo.senderName,
                'text': replyTo.text,
                'tgMsgId': replyTo.telegramMessageId,
              }
            : null,
      );

      debugPrint('[CHAT] Frame dispatched to socket, success = $sent');
      if (sent) {
        await _localDao.updateMessageStatus(messageId, 'sending');
        _updateMessageStatusInMemory(messageId, MessageStatus.sending);
      }
    } else {
      debugPrint('[CHAT WARNING] Socket is NOT connected! Current state: ${_socketClient.state}');
    }
  }

  Future<void> processPendingQueue() async {
    final pendingActions = await _localDao.getPendingActions();
    if (pendingActions.isEmpty || !_socketClient.isConnected) return;
    debugPrint('[CHAT] Processing ${pendingActions.length} pending actions...');

    for (final action in pendingActions) {
      final actionType = action['action_type'] as String;
      final actionId = action['id'] as String;

      if (actionType == 'send_message') {
        try {
          final Map<String, dynamic> payload = jsonDecode(action['payload_json'] as String);
          final sent = _socketClient.sendChatMessage(
            text: payload['text'] as String,
            clientMessageId: payload['clientMessageId'] as String?,
            replyTo: payload['replyTo'] as Map<String, dynamic>?,
          );

          if (sent) {
            await _localDao.removePendingAction(actionId);
            await _localDao.updateMessageStatus(actionId, 'sending');
            _updateMessageStatusInMemory(actionId, MessageStatus.sending);
            debugPrint('[CHAT] Dispatched queued message: $actionId');
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _handleIncomingSocketEvent(Map<String, dynamic> event, AuthUser currentUser) async {
    final type = event['type'] as String?;
    if (type == null) return;

    if (type == 'new_message' && event['message'] != null) {
      final msgJson = event['message'] as Map<String, dynamic>;
      final clientMsgId = msgJson['clientMessageId'] ?? msgJson['client_message_id'];

      if (clientMsgId != null) {
        final existingIndex = _messages.indexWhere((m) => m.clientMessageId == clientMsgId);
        if (existingIndex != -1) {
          final existing = _messages[existingIndex];
          final syncedMessage = existing.copyWith(
            id: msgJson['id'] as String? ?? existing.id,
            telegramMessageId: msgJson['telegramMessageId'] as int? ?? msgJson['tg_msg_id'] as int?,
            status: MessageStatus.synced,
          );

          await _localDao.saveMessage(syncedMessage.toDbMap());
          await _localDao.removePendingAction(existing.id);

          _messages[existingIndex] = syncedMessage;
          notifyListeners();
          debugPrint('[CHAT] Own message confirmed by server (synced): ${syncedMessage.id}');
          return;
        }
      }

      final incoming = ChatMessageModel.fromJson(msgJson);
      await _localDao.saveMessage(incoming.toDbMap());

      _messages.removeWhere((m) => m.id == incoming.id);
      _messages.insert(0, incoming);
      notifyListeners();
      debugPrint('[CHAT] Incoming new message added to UI: ${incoming.text}');
      return;
    }

    if (type == 'message_edited' && event['messageId'] != null) {
      final mId = event['messageId'] as String;
      final newText = event['text'] as String? ?? '';
      await _localDao.updateMessageText(mId, newText);

      final index = _messages.indexWhere((m) => m.id == mId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(text: newText, isEdited: true);
        notifyListeners();
      }
      return;
    }

    if (type == 'message_pinned' && event['message'] != null) {
      final msgJson = event['message'] as Map<String, dynamic>;
      final pinned = ChatMessageModel.fromJson(msgJson);
      await _localDao.setPinnedMessage(pinned.id, true);

      _pinnedMessage = pinned;
      final index = _messages.indexWhere((m) => m.id == pinned.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(isPinned: true);
      }
      notifyListeners();
      return;
    }

    if (type == 'message_unpinned') {
      _pinnedMessage = null;
      notifyListeners();
      return;
    }

    if (type == 'typing' && event['fullName'] != null) {
      _typingUserName = event['fullName'] as String;
      notifyListeners();

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _typingUserName = null;
        notifyListeners();
      });
      return;
    }
  }

  void _updateMessageStatusInMemory(String id, MessageStatus newStatus) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  Future<void> editMessage(String messageId, String newText) async {
    _socketClient.sendEditMessage(messageId: messageId, newText: newText);
    await _localDao.updateMessageText(messageId, newText);

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(text: newText, isEdited: true);
      notifyListeners();
    }
  }

  void pinMessage(String messageId) {
    _socketClient.sendPinMessage(messageId);
  }

  void unpinMessage() {
    _socketClient.sendUnpinMessage();
  }

  void sendTyping() {
    _socketClient.sendTyping();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _socketStateSubscription?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}
