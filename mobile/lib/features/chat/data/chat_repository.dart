import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/local_chat_dao.dart';
import '../../auth/domain/models/auth_user.dart';
import '../domain/models/chat_message_model.dart';
import 'chat_websocket_client.dart';

/// ریپازیتوری و مدیر وضعیت گفتگوی زنده و آفلاین
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

  /// بارگذاری پیام‌های اولیه از دیتابیس محلی SQLite جهت رندر آنی
  Future<void> initialize(AuthUser currentUser) async {
    _isLoading = true;
    notifyListeners();

    // ۱. خواندن سریع تاریخچه از SQLite (بدون معطلی برای اینترنت)
    await loadLocalMessages();

    // ۲. گوش دادن به وضعیت اتصال سوکت و تخلیه صف آفلاین پس از وصل شدن
    _socketStateSubscription?.cancel();
    _socketStateSubscription = _socketClient.stateStream.listen((state) {
      if (state == SocketConnectionState.connected) {
        processPendingQueue();
      }
      notifyListeners();
    });

    // ۳. گوش دادن به پیام‌های ورودی از سوکت زنده
    _socketSubscription?.cancel();
    _socketSubscription = _socketClient.messageStream.listen((event) {
      _handleIncomingSocketEvent(event, currentUser);
    });

    _isLoading = false;
    notifyListeners();
  }

  /// بارگذاری تاریخچه پیام‌ها از پایگاه داده محلی SQLite
  Future<void> loadLocalMessages({int limit = 50}) async {
    final rawList = await _localDao.getMessagesList(limit: limit);
    _messages = rawList.map((m) => ChatMessageModel.fromDbMap(m)).toList();

    // شناسایی پیام پین‌شده محلی
    try {
      _pinnedMessage = _messages.firstWhere((m) => m.isPinned);
    } catch (_) {
      _pinnedMessage = null;
    }

    notifyListeners();
  }

  /// ارسال پیام جدید با الگوی خوش‌بینانه (Optimistic UI)
  Future<void> sendMessage({
    required String text,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
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

    // ۱. درج فوری در دیتابیس محلی SQLite
    await _localDao.saveMessage(newMessage.toDbMap());

    // ۲. نمایش آنی در بالای لیست (رندر بدون لگ برای کاربر)
    _messages.insert(0, newMessage);
    notifyListeners();

    // ۳. ذخیره در صف کارهای معلق آفلاین
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

    // ۴. ارسال از طریق وب‌سوکت در صورت آنلاین بودن
    if (_socketClient.isConnected) {
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

      if (sent) {
        await _localDao.updateMessageStatus(messageId, 'sending');
        _updateMessageStatusInMemory(messageId, MessageStatus.sending);
      }
    }
  }

  /// پردازش و ارسال خودکار پیام‌های صف آفلاین پس از اتصال مجدد شبکه
  Future<void> processPendingQueue() async {
    final pendingActions = await _localDao.getPendingActions();
    if (pendingActions.isEmpty || !_socketClient.isConnected) return;

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
            // حذف تسک از صف و به‌روزرسانی وضعیت
            await _localDao.removePendingAction(actionId);
            await _localDao.updateMessageStatus(actionId, 'sending');
            _updateMessageStatusInMemory(actionId, MessageStatus.sending);
          }
        } catch (_) {}
      }
    }
  }

  /// پردازش رویدادهای زنده دریافتی از وب‌سوکت
  Future<void> _handleIncomingSocketEvent(Map<String, dynamic> event, AuthUser currentUser) async {
    final type = event['type'] as String?;
    if (type == null) return;

    if (type == 'new_message' && event['message'] != null) {
      final msgJson = event['message'] as Map<String, dynamic>;
      final clientMsgId = msgJson['clientMessageId'] ?? msgJson['client_message_id'];

      // الف) اگر پیام تایید پیام ارسالی خودمان است (Deduplication)
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
          return;
        }
      }

      // ب) اگر پیام جدید از تلگرام یا کاربر دیگری است
      final incoming = ChatMessageModel.fromJson(msgJson);
      await _localDao.saveMessage(incoming.toDbMap());

      // جلوگیری از اضافه شدن تکراری
      _messages.removeWhere((m) => m.id == incoming.id);
      _messages.insert(0, incoming);
      notifyListeners();
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

  /// ارسال درخواست ویرایش پیام
  Future<void> editMessage(String messageId, String newText) async {
    _socketClient.sendEditMessage(messageId: messageId, newText: newText);
    await _localDao.updateMessageText(messageId, newText);

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(text: newText, isEdited: true);
      notifyListeners();
    }
  }

  /// ارسال درخواست پین کردن پیام
  void pinMessage(String messageId) {
    _socketClient.sendPinMessage(messageId);
  }

  /// ارسال درخواست حذف پین
  void unpinMessage() {
    _socketClient.sendUnpinMessage();
  }

  /// ارسال سیگنال در حال تایپ
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
