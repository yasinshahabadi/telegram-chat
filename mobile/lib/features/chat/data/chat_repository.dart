import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'chat_websocket_client.dart';

/// ریپازیتوری چت با پشتیبانی از:
/// - نمایش پیام‌ها و مدیا
/// - کاربران آنلاین
/// - تیک خوانده‌شدن
/// - آپلود خوش‌بینانه با نوار پیشرفت
/// - حفظ localPath پس از برودکست WebSocket
class ChatRepository extends ChangeNotifier {
  final LocalChatDao _localDao;
  final ChatWebSocketClient _socketClient;

  List<ChatMessageModel> _messages = [];
  ChatMessageModel? _pinnedMessage;
  String? _typingUserName;
  Timer? _typingTimer;
  bool _isLoading = false;
  bool isAppInBackground = false;

  // ✅ کاربران آنلاین
  final Map<String, Map<String, dynamic>> _onlineUsers = {};

  StreamSubscription? _socketSubscription;
  StreamSubscription? _socketStateSubscription;

  ChatRepository({
    required LocalChatDao localDao,
    required ChatWebSocketClient socketClient,
  })  : _localDao = localDao,
        _socketClient = socketClient;

  // ─── Getters ───
  List<ChatMessageModel> get messages => _messages;
  ChatMessageModel? get pinnedMessage => _pinnedMessage;
  String? get typingUserName => _typingUserName;
  bool get isLoading => _isLoading;
  SocketConnectionState get connectionState => _socketClient.state;

  Map<String, Map<String, dynamic>> get onlineUsers =>
      Map.unmodifiable(_onlineUsers);
  int get onlineCount => _onlineUsers.length;
  bool isUserOnline(String userId) => _onlineUsers.containsKey(userId);

  // ─── Initialize ───
  Future<void> initialize(AuthUser currentUser) async {
    _isLoading = true;
    notifyListeners();

    try {
      await loadLocalMessages();

      _socketStateSubscription?.cancel();
      _socketStateSubscription = _socketClient.stateStream.listen((state) {
        if (state == SocketConnectionState.connected) {
          processPendingQueue();
          // ✅ اطلاع‌رسانی وضعیت فعلی حضور به سرور
          _socketClient.sendPresence(online: !isAppInBackground);
        }
        notifyListeners();
      });

      _socketSubscription?.cancel();
      _socketSubscription = _socketClient.messageStream.listen((event) {
        _handleIncomingSocketEvent(event, currentUser);
      });
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Load local messages with attachments ───
  Future<void> loadLocalMessages({int limit = 50}) async {
    try {
      final rawList = await _localDao.getMessagesList(limit: limit);

      final loaded = <ChatMessageModel>[];
      for (final raw in rawList) {
        final messageId = raw['id'] as String?;
        if (messageId == null) continue;

        MediaAttachmentModel? attachment;
        try {
          final attachments =
              await _localDao.getAttachmentsForMessage(messageId);
          if (attachments.isNotEmpty) {
            attachment = MediaAttachmentModel.fromDbMap(attachments.first);
          }
        } catch (_) {}

        loaded.add(ChatMessageModel.fromDbMap(raw, attachment: attachment));
      }

      _messages = loaded;

      try {
        _pinnedMessage = _messages.firstWhere((m) => m.isPinned);
      } catch (_) {
        _pinnedMessage = null;
      }
    } catch (_) {
      _messages = [];
    } finally {
      notifyListeners();
    }
  }

  // ─── Send text message ───
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

    _messages.insert(0, newMessage);
    notifyListeners();

    try {
      await _localDao.saveMessage(newMessage.toDbMap());
    } catch (_) {}

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
      await _localDao.enqueuePendingAction(
          messageId, 'send_message', payloadJson);
    } catch (_) {}

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

  // ─── Pending queue ───
  Future<void> processPendingQueue() async {
    final pendingActions = await _localDao.getPendingActions();
    if (pendingActions.isEmpty || !_socketClient.isConnected) return;

    for (final action in pendingActions) {
      final actionType = action['action_type'] as String;
      final actionId = action['id'] as String;

      if (actionType == 'send_message') {
        try {
          final Map<String, dynamic> payload =
              jsonDecode(action['payload_json'] as String);
          final sent = _socketClient.sendChatMessage(
            text: payload['text'] as String,
            clientMessageId: payload['clientMessageId'] as String?,
            replyTo: payload['replyTo'] as Map<String, dynamic>?,
          );

          if (sent) {
            await _localDao.removePendingAction(actionId);
            await _localDao.updateMessageStatus(actionId, 'sending');
            _updateMessageStatusInMemory(actionId, MessageStatus.sending);
          }
        } catch (_) {}
      }
    }
  }

  // ─── Mark as read ───
  Future<void> markMessagesAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _localDao.markMessagesAsRead(messageIds, now);

    for (final id in messageIds) {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx != -1 && _messages[idx].readAt == null) {
        _messages[idx] = _messages[idx].copyWith(readAt: now);
      }
    }
    notifyListeners();

    _socketClient.sendMarkRead(messageIds);
  }

  // ─── Optimistic Upload ───
  String addOptimisticUpload({
    required String fileName,
    required int fileSize,
    required String mediaType,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) {
    final tempId = 'temp_upload_${const Uuid().v4()}';
    final now = DateTime.now().millisecondsSinceEpoch;

    final optimistic = ChatMessageModel(
      id: tempId,
      senderId: currentUser.id,
      senderName: currentUser.fullName,
      text: '',
      isFromTelegram: false,
      replyToMessageId: replyTo?.id,
      replyToName: replyTo?.senderName,
      replyToText: replyTo?.text,
      status: MessageStatus.sending,
      createdAt: now,
      updatedAt: now,
      isUploading: true,
      uploadProgress: 0.0,
      attachment: MediaAttachmentModel(
        id: 'att_$tempId',
        messageId: tempId,
        mediaType: mediaType,
        fileName: fileName,
        fileSize: fileSize,
        isDownloaded: false,
        createdAt: now,
      ),
    );

    _messages.insert(0, optimistic);
    notifyListeners();
    return tempId;
  }

  void updateUploadProgress(String tempId, double progress) {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(uploadProgress: progress);
      notifyListeners();
    }
  }

  void finalizeUpload({
    required String tempId,
    required String realMessageId,
    required String fileId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String mediaType,
  }) {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx == -1) return;

    final old = _messages[idx];
    final now = DateTime.now().millisecondsSinceEpoch;

    final finalMessage = old.copyWith(
      id: realMessageId,
      status: MessageStatus.synced,
      isUploading: false,
      uploadProgress: 1.0,
      updatedAt: now,
      attachment: MediaAttachmentModel(
        id: 'att_$realMessageId',
        messageId: realMessageId,
        mediaType: mediaType,
        telegramFileId: fileId,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        isDownloaded: false,
        createdAt: now,
      ),
    );

    _messages[idx] = finalMessage;
    notifyListeners();
  }

  void failUpload(String tempId, String error) {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        status: MessageStatus.failed,
        isUploading: false,
      );
      notifyListeners();
    }
  }

  /// ✅ به‌روزرسانی localPath پیام پس از کش شدن فایل
  void setLocalPathForMessage(String messageId, String localPath) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final currentAttachment = _messages[idx].attachment;
    if (currentAttachment == null) return;

    if (currentAttachment.localPath != null &&
        currentAttachment.localPath == localPath) {
      return;
    }

    _messages[idx] = _messages[idx].copyWith(
      attachment: currentAttachment.copyWith(
        localPath: localPath,
        isDownloaded: true,
      ),
    );
    notifyListeners();

    _localDao
        .updateAttachmentLocalPath(currentAttachment.id, localPath)
        .catchError((_) {});
  }

  // ─── Handle socket events ───
  Future<void> _handleIncomingSocketEvent(
      Map<String, dynamic> event, AuthUser currentUser) async {
    final type = event['type'] as String?;
    if (type == null) return;

    // ═══════════════ رویداد آنلاین‌ها ═══════════════
    if (type == 'online_users' && event['users'] != null) {
      final usersList = (event['users'] as List).cast<Map<String, dynamic>>();
      _onlineUsers.clear();
      for (final u in usersList) {
        final id = u['userId'] as String?;
        if (id != null) _onlineUsers[id] = u;
      }
      notifyListeners();
      return;
    }

    // ═══════════════ رویداد خوانده‌شدن پیام‌ها ═══════════════
    if (type == 'messages_read' && event['messageIds'] != null) {
      final ids = (event['messageIds'] as List).cast<String>();
      final readerId = event['userId'] as String?;
      final readAt = event['readAt'] as int? ??
          DateTime.now().millisecondsSinceEpoch;

      final toMark = <String>[];
      for (final id in ids) {
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx != -1) {
          final msg = _messages[idx];
          if (msg.senderId == currentUser.id &&
              msg.senderId != readerId &&
              msg.readAt == null) {
            toMark.add(id);
            _messages[idx] = msg.copyWith(readAt: readAt);
          }
        }
      }

      if (toMark.isNotEmpty) {
        await _localDao.markMessagesAsRead(toMark, readAt);
        notifyListeners();
      }
      return;
    }

    // ═══════════════ پیام جدید ═══════════════
    if (type == 'new_message' && event['message'] != null) {
      final msgJson = event['message'] as Map<String, dynamic>;
      final clientMsgId =
          msgJson['clientMessageId'] ?? msgJson['client_message_id'];
      final incomingId = msgJson['id'] as String?;

      // ۱) پیام خودمان (client message id)
      if (clientMsgId != null) {
        final existingIndex =
            _messages.indexWhere((m) => m.clientMessageId == clientMsgId);
        if (existingIndex != -1) {
          final existing = _messages[existingIndex];
          final syncedMessage = existing.copyWith(
            id: incomingId ?? existing.id,
            telegramMessageId: msgJson['telegramMessageId'] as int? ??
                msgJson['tg_msg_id'] as int?,
            status: MessageStatus.synced,
          );

          await _localDao.saveMessage(syncedMessage.toDbMap());
          await _localDao.removePendingAction(existing.id);

          _messages[existingIndex] = syncedMessage;
          notifyListeners();
          return;
        }
      }

      // ۲) ساخت پیام از سرور
      ChatMessageModel incoming = ChatMessageModel.fromJson(msgJson);

      // ✅ حفظ localPath و readAt از پیام قبلی (اگر وجود دارد)
      if (incomingId != null) {
        final existingIndex =
            _messages.indexWhere((m) => m.id == incomingId);
        if (existingIndex != -1) {
          final existing = _messages[existingIndex];
          final existingAttachment = existing.attachment;

          if (existingAttachment != null &&
              existingAttachment.localPath != null &&
              incoming.attachment != null) {
            final mergedAttachment = incoming.attachment!.copyWith(
              localPath: existingAttachment.localPath,
              isDownloaded: true,
            );
            incoming = incoming.copyWith(attachment: mergedAttachment);
          } else if (existingAttachment != null &&
              incoming.attachment == null) {
            incoming = incoming.copyWith(attachment: existingAttachment);
          }

          if (existing.readAt != null && incoming.readAt == null) {
            incoming = incoming.copyWith(readAt: existing.readAt);
          }
        }
      }

      await _localDao.saveMessage(incoming.toDbMap());

      if (incoming.attachment != null) {
        try {
          await _localDao.saveAttachment(incoming.attachment!.toDbMap());
        } catch (_) {}
      }

      _messages.removeWhere((m) => m.id == incoming.id);
      _messages.insert(0, incoming);
      notifyListeners();
      return;
    }

    // ═══════════════ ویرایش پیام ═══════════════
    if (type == 'message_edited' && event['messageId'] != null) {
      final mId = event['messageId'] as String;
      final newText = event['text'] as String? ?? '';
      await _localDao.updateMessageText(mId, newText);

      final index = _messages.indexWhere((m) => m.id == mId);
      if (index != -1) {
        _messages[index] =
            _messages[index].copyWith(text: newText, isEdited: true);
        notifyListeners();
      }
      return;
    }

    // ═══════════════ پین پیام ═══════════════
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

    // ═══════════════ حذف پین ═══════════════
    if (type == 'message_unpinned') {
      _pinnedMessage = null;
      notifyListeners();
      return;
    }

    // ═══════════════ در حال تایپ ═══════════════
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
      _messages[index] =
          _messages[index].copyWith(text: newText, isEdited: true);
      notifyListeners();
    }
  }

  void pinMessage(String messageId) => _socketClient.sendPinMessage(messageId);
  void unpinMessage() => _socketClient.sendUnpinMessage();
  void sendTyping() => _socketClient.sendTyping();

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _socketStateSubscription?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}