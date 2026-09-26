import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'chat_websocket_client.dart';

class ChatRepository extends ChangeNotifier {
  final LocalChatDao _localDao;
  final ChatWebSocketClient _socketClient;

  List<ChatMessageModel> _messages = [];
  ChatMessageModel? _pinnedMessage;
  String? _typingUserName;
  Timer? _typingTimer;
  bool _isLoading = false;
  bool isAppInBackground = false;

  final Map<String, Map<String, dynamic>> _onlineUsers = {};

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

  Map<String, Map<String, dynamic>> get onlineUsers => Map.unmodifiable(_onlineUsers);
  int get onlineCount => _onlineUsers.length;
  bool isUserOnline(String userId) => _onlineUsers.containsKey(userId);

  Future<void> initialize(AuthUser currentUser) async {
    _isLoading = true;
    notifyListeners();

    try {
      await loadLocalMessages();

      _socketStateSubscription?.cancel();
      _socketStateSubscription = _socketClient.stateStream.listen((state) {
        if (state == SocketConnectionState.connected) {
          processPendingQueue();
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

  Future<void> loadLocalMessages({int limit = 50}) async {
    try {
      final rawList = await _localDao.getMessagesList(limit: limit);

      final loaded = <ChatMessageModel>[];
      for (final raw in rawList) {
        final messageId = raw['id'] as String?;
        if (messageId == null) continue;

        final List<MediaAttachmentModel> atts = [];
        try {
          final attachments = await _localDao.getAttachmentsForMessage(messageId);
          for (final a in attachments) {
            atts.add(MediaAttachmentModel.fromDbMap(a));
          }
        } catch (_) {}

        loaded.add(ChatMessageModel.fromDbMap(raw, attachments: atts));
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
      await _localDao.enqueuePendingAction(messageId, 'send_message', payloadJson);
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

  // ═════════════════════════════════════════════
  //  آپلود Optimistic (چند پیوست)
  // ═════════════════════════════════════════════

  ChatMessageModel addOptimisticMultiUpload({
    required List<File> files,
    required List<String> mediaTypes,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) {
    final tempId = 'temp_upload_${const Uuid().v4()}';
    final clientMessageId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final optimisticAtts = <MediaAttachmentModel>[];
    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      optimisticAtts.add(MediaAttachmentModel(
        id: 'att_${tempId}_$i',
        messageId: tempId,
        mediaType: mediaTypes[i],
        localPath: f.path,
        fileName: p.basename(f.path),
        isDownloaded: true,
        createdAt: now,
      ));
    }

    final optimistic = ChatMessageModel(
      id: tempId,
      clientMessageId: clientMessageId,
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
      attachments: optimisticAtts,
    );

    _messages.insert(0, optimistic);
    notifyListeners();
    return optimistic;
  }

  void updateUploadProgress(String tempId, double progress) {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(uploadProgress: progress.clamp(0.0, 1.0));
      notifyListeners();
    }
  }

  /// جایگزینی پیام موقت با پیام واقعی سرور. Idempotent.
  void finalizeMultiUpload({
    required String tempId,
    String? clientMessageId,
    required String realMessageId,
    required List<MediaAttachmentModel> attachments,
  }) {
    int idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx == -1 && clientMessageId != null) {
      idx = _messages.indexWhere((m) => m.clientMessageId == clientMessageId);
    }
    if (idx == -1) return;

    final old = _messages[idx];
    final now = DateTime.now().millisecondsSinceEpoch;
    final mergedAtts = _mergeAttachmentsByIndex(old.attachments, attachments);

    _messages[idx] = old.copyWith(
      id: realMessageId,
      status: MessageStatus.synced,
      isUploading: false,
      uploadProgress: 1.0,
      updatedAt: now,
      attachments: mergedAtts,
    );
    notifyListeners();

    // Persist locally so restart preserves the state.
    _localDao.saveMessage(_messages[idx].toDbMap()).catchError((_) {});
    for (final a in mergedAtts) {
      _localDao.saveAttachment(a.toDbMap()).catchError((_) {});
    }
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

  /// به‌روزرسانی مسیر محلی یک پیوست پس از کش شدن آپلود.
  void setLocalPathForAttachment(
    String messageId,
    String attachmentId,
    String localPath,
  ) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final msg = _messages[idx];
    final atts = List<MediaAttachmentModel>.from(msg.attachments);
    final attIdx = atts.indexWhere((a) => a.id == attachmentId);
    if (attIdx == -1) return;

    atts[attIdx] = atts[attIdx].copyWith(
      localPath: localPath,
      isDownloaded: true,
    );
    _messages[idx] = msg.copyWith(attachments: atts);
    notifyListeners();

    _localDao.updateAttachmentLocalPath(attachmentId, localPath).catchError((_) {});
  }

  // ═════════════════════════════════════════════
  //  Socket events
  // ═════════════════════════════════════════════

  Future<void> _handleIncomingSocketEvent(
      Map<String, dynamic> event, AuthUser currentUser) async {
    final type = event['type'] as String?;
    if (type == null) return;

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

    if (type == 'messages_read' && event['messageIds'] != null) {
      final ids = (event['messageIds'] as List).cast<String>();
      final readerId = event['userId'] as String?;
      final readAt = event['readAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;

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

    if (type == 'new_message' && event['message'] != null) {
      final msgJson = event['message'] as Map<String, dynamic>;
      final incoming = ChatMessageModel.fromJson(msgJson);
      final clientMsgId = incoming.clientMessageId;

      // Case 1: our own optimistic upload echo.
      if (clientMsgId != null) {
        final idx = _messages.indexWhere((m) => m.clientMessageId == clientMsgId);
        if (idx != -1) {
          final existing = _messages[idx];
          final mergedAtts = _mergeAttachmentsByIndex(
            existing.attachments, incoming.attachments,
          );
          final merged = existing.copyWith(
            id: incoming.id,
            telegramMessageId: incoming.telegramMessageId,
            status: MessageStatus.synced,
            isUploading: false,
            uploadProgress: 1.0,
            attachments: mergedAtts,
            updatedAt: incoming.updatedAt,
          );
          await _localDao.saveMessage(merged.toDbMap());
          for (final a in merged.attachments) {
            try { await _localDao.saveAttachment(a.toDbMap()); } catch (_) {}
          }
          await _localDao.removePendingAction(existing.id);
          _messages[idx] = merged;
          notifyListeners();
          return;
        }
      }

      // Case 2: already-processed echo (by id).
      final idxById = _messages.indexWhere((m) => m.id == incoming.id);
      if (idxById != -1) {
        final existing = _messages[idxById];
        final mergedAtts = _mergeAttachmentsByIndex(
          existing.attachments, incoming.attachments,
        );
        final merged = existing.copyWith(
          clientMessageId: incoming.clientMessageId ?? existing.clientMessageId,
          attachments: mergedAtts,
        );
        await _localDao.saveMessage(merged.toDbMap());
        for (final a in merged.attachments) {
          try { await _localDao.saveAttachment(a.toDbMap()); } catch (_) {}
        }
        _messages[idxById] = merged;
        notifyListeners();
        return;
      }

      // Case 3: truly new message.
      await _localDao.saveMessage(incoming.toDbMap());
      for (final a in incoming.attachments) {
        try { await _localDao.saveAttachment(a.toDbMap()); } catch (_) {}
      }
      _messages.insert(0, incoming);
      notifyListeners();
      return;
    }

    if (type == 'message_ack' && event['clientMessageId'] != null) {
      final clientMsgId = event['clientMessageId'] as String;
      final realMessageId = event['messageId'] as String?;
      final idx = _messages.indexWhere((m) => m.clientMessageId == clientMsgId);
      if (idx != -1 && realMessageId != null) {
        _messages[idx] = _messages[idx].copyWith(
          id: realMessageId,
          status: MessageStatus.synced,
        );
        await _localDao.updateMessageStatus(realMessageId, 'synced');
        notifyListeners();
      }
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
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].id != pinned.id && _messages[i].isPinned) {
          _messages[i] = _messages[i].copyWith(isPinned: false);
        }
      }
      final index = _messages.indexWhere((m) => m.id == pinned.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(isPinned: true);
      }
      notifyListeners();
      return;
    }

    if (type == 'message_unpinned') {
      _pinnedMessage = null;
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].isPinned) {
          _messages[i] = _messages[i].copyWith(isPinned: false);
        }
      }
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

  /// ادغام پیوست‌ها بر اساس ترتیب (برای optimistic → server).
  /// حفظ `localPath` از سمت موجود.
  List<MediaAttachmentModel> _mergeAttachmentsByIndex(
    List<MediaAttachmentModel> existing,
    List<MediaAttachmentModel> incoming,
  ) {
    final result = <MediaAttachmentModel>[];
    for (int i = 0; i < incoming.length; i++) {
      final inc = incoming[i];
      if (i < existing.length) {
        final ex = existing[i];
        result.add(inc.copyWith(
          localPath: inc.localPath ?? ex.localPath,
          isDownloaded: inc.isDownloaded || ex.isDownloaded,
        ));
      } else {
        result.add(inc);
      }
    }
    return result;
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