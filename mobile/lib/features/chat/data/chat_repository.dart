import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/data/media_local_storage.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'chat_websocket_client.dart';
import 'socket_event_dispatcher.dart';

class ChatRepository extends ChangeNotifier {
  final LocalChatDao _localDao;
  final ChatWebSocketClient _socketClient;
  final MediaLocalStorage _mediaStorage = MediaLocalStorage();

  /// ✅ هندلر رویدادهای سوکت (Stage 6).
  /// کلاس جدا، ولی با callback به state داخلی این repo وصل می‌شود.
  late final SocketEventDispatcher _dispatcher;

  List<ChatMessageModel> _messages = [];
  ChatMessageModel? _pinnedMessage;
  String? _typingUserName;
  String? _currentUserId;
  Timer? _typingTimer;
  Timer? _pendingRetryTimer;
  bool _isLoading = false;
  bool isAppInBackground = false;

  VoidCallback? onSocketReconnected;

  final Map<String, Map<String, dynamic>> _onlineUsers = {};

  StreamSubscription? _socketSubscription;
  StreamSubscription? _socketStateSubscription;

  ChatRepository({
    required LocalChatDao localDao,
    required ChatWebSocketClient socketClient,
  })  : _localDao = localDao,
        _socketClient = socketClient {
    _dispatcher = SocketEventDispatcher(
      localDao: _localDao,
      getMessages: () => _messages,
      getCurrentUserId: () => _currentUserId,
      getPinnedMessage: () => _pinnedMessage,
      notifyChanged: () => notifyListeners(),
      setPinnedMessage: (pinned) {
        _pinnedMessage = pinned;
        // نکته: notify عمداً اینجا نیست — caller خودش notifyChanged را
        // صدا می‌زند (چون ممکن است چند تغییر state در یک رویداد رخ دهد).
      },
      setTypingUserName: (name) {
        _typingUserName = name;
        _typingTimer?.cancel();
        if (name != null) {
          _typingTimer = Timer(const Duration(seconds: 3), () {
            _typingUserName = null;
            notifyListeners();
          });
        }
        notifyListeners();
      },
      setOnlineUsers: (users) {
        _onlineUsers.clear();
        _onlineUsers.addAll(users);
        notifyListeners();
      },
    );
  }

  List<ChatMessageModel> get messages => _messages;
  ChatMessageModel? get pinnedMessage => _pinnedMessage;
  String? get typingUserName => _typingUserName;
  bool get isLoading => _isLoading;
  SocketConnectionState get connectionState => _socketClient.state;

  Map<String, Map<String, dynamic>> get onlineUsers =>
      Map.unmodifiable(_onlineUsers);
  int get onlineCount => _onlineUsers.length;
  bool isUserOnline(String userId) => _onlineUsers.containsKey(userId);

  Future<void> initialize(AuthUser currentUser) async {
    _currentUserId = currentUser.id;
    _isLoading = true;
    notifyListeners();

    try {
      await loadLocalMessages();

      _socketStateSubscription?.cancel();
      _socketStateSubscription = _socketClient.stateStream.listen((state) {
        if (state == SocketConnectionState.connected) {
          processPendingQueue();
          _socketClient.sendPresence(online: !isAppInBackground);
          _schedulePendingRetry(immediate: true);
          try {
            onSocketReconnected?.call();
          } catch (e) {
            debugPrint('[ChatRepo] onSocketReconnected error: $e');
          }
        }
        notifyListeners();
      });

      _socketSubscription?.cancel();
      _socketSubscription = _socketClient.messageStream.listen((event) {
        // ✅ تمام پردازش رویداد به SocketEventDispatcher منتقل شده.
        _dispatcher.handle(event).catchError((e, st) {
          debugPrint('[ChatRepo] Failed to handle socket event: $e\n$st');
        });
      });

      _schedulePendingRetry();
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLocalMessages({int limit = 50}) async {
    try {
      // ✅ پاک‌سازی پیام‌های temp orphan قبل از خواندن
      try {
        await _localDao.deleteOrphanTempMessages();
      } catch (_) {}

      final rawList = await _localDao.getMessagesList(limit: limit);
      final me = _currentUserId;

      final loaded = <ChatMessageModel>[];
      for (final raw in rawList) {
        final messageId = raw['id'] as String?;
        if (messageId == null) continue;

        final List<MediaAttachmentModel> atts = [];
        try {
          final attachments =
              await _localDao.getAttachmentsForMessage(messageId);
          for (final a in attachments) {
            atts.add(MediaAttachmentModel.fromDbMap(a));
          }
        } catch (_) {}

        final Map<String, int> reactionsMap = {};
        final Set<String> myReactions = {};
        try {
          final rows = await _localDao.getReactionsForMessage(messageId);
          for (final r in rows) {
            final emoji = r['emoji'] as String?;
            if (emoji == null || emoji.isEmpty) continue;
            reactionsMap[emoji] = (reactionsMap[emoji] ?? 0) + 1;
            if (me != null && r['user_id'] == me) {
              myReactions.add(emoji);
            }
          }
        } catch (_) {}

        loaded.add(ChatMessageModel.fromDbMap(
          raw,
          attachments: atts,
          reactions: reactionsMap,
          myReactions: myReactions,
        ));
      }

      // حفظ وضعیت in-flight برای پیام‌هایی که در حال آپلود هستند
      final Map<String, ChatMessageModel> inFlight = {};
      for (final m in _messages) {
        if (m.isUploading || m.isFailed) inFlight[m.id] = m;
      }
      if (inFlight.isNotEmpty) {
        for (int i = 0; i < loaded.length; i++) {
          final inf = inFlight[loaded[i].id];
          if (inf != null) {
            loaded[i] = loaded[i].copyWith(
              status: inf.status,
              isUploading: inf.isUploading,
              uploadProgress: inf.uploadProgress,
            );
          }
        }
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

  _ReplyPreviewInfo? _extractReplyPreview(ChatMessageModel? replyTo) {
    if (replyTo == null) return null;
    final att =
        replyTo.attachments.isNotEmpty ? replyTo.attachments.first : null;
    return _ReplyPreviewInfo(
      messageId: replyTo.id,
      name: replyTo.senderName,
      text: replyTo.text,
      mediaType: att?.mediaType,
      attachmentId: att?.id,
      telegramFileId: att?.telegramFileId,
      fileName: att?.fileName,
      duration: att?.duration,
    );
  }

  Future<void> sendMessage({
    required String text,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = const Uuid().v4();
    final clientMessageId = const Uuid().v4();
    final rp = _extractReplyPreview(replyTo);

    final newMessage = ChatMessageModel(
      id: messageId,
      clientMessageId: clientMessageId,
      senderId: currentUser.id,
      senderName: currentUser.fullName,
      text: text,
      isFromTelegram: false,
      replyToMessageId: rp?.messageId,
      replyToName: rp?.name,
      replyToText: rp?.text,
      replyToMediaType: rp?.mediaType,
      replyToAttachmentId: rp?.attachmentId,
      replyToTelegramFileId: rp?.telegramFileId,
      replyToFileName: rp?.fileName,
      replyToDuration: rp?.duration,
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
        'replyTo': rp == null
            ? null
            : {
                'id': rp.messageId,
                'name': rp.name,
                'text': rp.text,
                'tgMsgId': replyTo?.telegramMessageId,
              },
      });
      await _localDao.enqueuePendingAction(
          messageId, 'send_message', payloadJson);
    } catch (_) {}

    if (_socketClient.isConnected) {
      final sent = _socketClient.sendChatMessage(
        text: text,
        clientMessageId: clientMessageId,
        replyTo: rp == null
            ? null
            : {
                'id': rp.messageId,
                'name': rp.name,
                'text': rp.text,
                'tgMsgId': replyTo?.telegramMessageId,
              },
      );

      if (sent) {
        await _localDao.updateMessageStatus(messageId, 'sending');
        _updateMessageStatusInMemory(messageId, MessageStatus.sending);
      }
    }

    _schedulePendingRetry();
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
      } else if (actionType == 'delete_message') {
        try {
          final Map<String, dynamic> payload =
              jsonDecode(action['payload_json'] as String);
          final mId = payload['messageId'] as String?;
          if (mId != null) {
            _socketClient.sendDeleteMessage(mId);
          }
        } catch (_) {}
      }
    }
  }

  void _schedulePendingRetry({bool immediate = false}) {
    _pendingRetryTimer?.cancel();

    if (!_socketClient.isConnected) return;

    final delay = immediate ? Duration.zero : const Duration(seconds: 12);

    _pendingRetryTimer = Timer(delay, () async {
      if (!_socketClient.isConnected) return;

      try {
        final actions = await _localDao.getPendingActions();
        if (actions.isEmpty) return;

        await processPendingQueue();
        _schedulePendingRetry();
      } catch (_) {
        _schedulePendingRetry();
      }
    });
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

  Future<void> toggleReaction(String messageId, String emoji) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final msg = _messages[idx];
    final reactions = Map<String, int>.from(msg.reactions);
    final myReactions = Set<String>.from(msg.myReactions);

    final isMine = myReactions.contains(emoji);
    if (isMine) {
      myReactions.remove(emoji);
      final newCount = (reactions[emoji] ?? 1) - 1;
      if (newCount <= 0) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = newCount;
      }
    } else {
      myReactions.add(emoji);
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    }

    _messages[idx] = msg.copyWith(
      reactions: reactions,
      myReactions: myReactions,
    );
    notifyListeners();

    final sent =
        _socketClient.sendToggleReaction(messageId: messageId, emoji: emoji);
    if (!sent) {
      _messages[idx] = msg;
      notifyListeners();
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final actionId = 'delete_$messageId';

    try {
      await _localDao.enqueuePendingAction(
        actionId,
        'delete_message',
        jsonEncode({'messageId': messageId}),
      );
    } catch (_) {}

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _messages.removeAt(idx);
      if (_pinnedMessage?.id == messageId) _pinnedMessage = null;
      notifyListeners();
    }

    try {
      await _localDao.deleteMessage(messageId);
    } catch (_) {}

    if (_socketClient.isConnected) {
      _socketClient.sendDeleteMessage(messageId);
    }

    _schedulePendingRetry();
  }

  /// ✅ کپی فایل‌های انتخاب‌شده به storage داخلی اپ + ثبت رکورد optimistic.
  Future<ChatMessageModel> addOptimisticMultiUpload({
    required List<File> files,
    required List<String> mediaTypes,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    final tempId = 'temp_upload_${const Uuid().v4()}';
    final clientMessageId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rp = _extractReplyPreview(replyTo);

    final optimisticAtts = <MediaAttachmentModel>[];
    for (int i = 0; i < files.length; i++) {
      final original = files[i];
      final attId = 'att_${tempId}_$i';
      final originalName = p.basename(original.path);

      // ✅ کپی به storage داخلی
      File durable = original;
      try {
        final copied = await _mediaStorage.saveFileFromPathForAttachment(
          original.path,
          attId,
          originalName,
        );
        if (copied != null) durable = copied;
      } catch (e) {
        debugPrint('[ChatRepo] Copy to storage failed: $e');
      }

      optimisticAtts.add(MediaAttachmentModel(
        id: attId,
        messageId: tempId,
        mediaType: mediaTypes[i],
        localPath: durable.path,
        fileName: originalName,
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
      replyToMessageId: rp?.messageId,
      replyToName: rp?.name,
      replyToText: rp?.text,
      replyToMediaType: rp?.mediaType,
      replyToAttachmentId: rp?.attachmentId,
      replyToTelegramFileId: rp?.telegramFileId,
      replyToFileName: rp?.fileName,
      replyToDuration: rp?.duration,
      status: MessageStatus.sending,
      createdAt: now,
      updatedAt: now,
      isUploading: true,
      uploadProgress: 0.0,
      attachments: optimisticAtts,
    );

    try {
      await _localDao.saveMessage(optimistic.toDbMap());
      for (final a in optimisticAtts) {
        try {
          await _localDao.saveAttachment(a.toDbMap());
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ChatRepo] Failed to persist optimistic upload: $e');
    }

    _messages.insert(0, optimistic);
    notifyListeners();
    return optimistic;
  }

  void updateUploadProgress(String tempId, double progress) {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        uploadProgress: progress.clamp(0.0, 1.0),
        isUploading: true,
        status: MessageStatus.sending,
      );
      notifyListeners();
    }
  }

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
    final mergedAtts = _mergeAttachmentsForUpload(old.attachments, attachments);

    _messages[idx] = old.copyWith(
      id: realMessageId,
      status: MessageStatus.synced,
      isUploading: false,
      uploadProgress: 1.0,
      updatedAt: now,
      attachments: mergedAtts,
    );
    notifyListeners();

    // ✅ ابتدا پیام ذخیره می‌شود، سپس پیوست‌ها.
    _localDao.saveMessage(_messages[idx].toDbMap()).then((_) {
      for (final a in mergedAtts) {
        _localDao.saveAttachment(a.toDbMap()).catchError((_) {});
      }
    }).catchError((_) {});
  }

  /// ✅ تغییر وضعیت به «ناموفق» + ذخیره در DB.
  Future<void> failUpload(String tempId, String error) async {
    final idx = _messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        status: MessageStatus.failed,
        isUploading: false,
      );
      notifyListeners();
    }
    try {
      await _localDao.updateMessageStatus(tempId, 'failed');
    } catch (_) {}
  }

  /// ✅ آماده‌سازی پیام برای تلاش دوباره: تغییر وضعیت به sending + متن اختیاری.
  void prepareForRetry(String messageId, {String? newText}) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final old = _messages[idx];
    _messages[idx] = old.copyWith(
      status: MessageStatus.sending,
      isUploading: true,
      uploadProgress: 0.0,
      text: newText ?? old.text,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    _localDao.saveMessage(_messages[idx].toDbMap()).catchError((_) {});
  }

  void setLocalPathForAttachment(
    String messageId,
    String attachmentId,
    String localPath,
  ) {
    _localDao
        .updateAttachmentLocalPath(attachmentId, localPath)
        .catchError((_) {});

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
  }

  /// ادغام پیوست‌های آپلود (نسخهٔ Stage 3).
  ///
  /// این نسخه با `SocketEventDispatcher._mergeAttachmentsByIndex` متفاوت است:
  /// نسخهٔ dispatcher بر اساس clientMessageId merge می‌کند، این نسخه بر اساس
  /// ترتیب index در `addOptimisticMultiUpload`. هر دو ضروری‌اند و در جای
  /// خود استفاده می‌شوند.
  List<MediaAttachmentModel> _mergeAttachmentsForUpload(
    List<MediaAttachmentModel> existing,
    List<MediaAttachmentModel> incoming,
  ) {
    if (incoming.isEmpty) return existing;

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
    _pendingRetryTimer?.cancel();
    super.dispose();
  }
}

class _ReplyPreviewInfo {
  final String messageId;
  final String name;
  final String text;
  final String? mediaType;
  final String? attachmentId;
  final String? telegramFileId;
  final String? fileName;
  final int? duration;

  const _ReplyPreviewInfo({
    required this.messageId,
    required this.name,
    required this.text,
    this.mediaType,
    this.attachmentId,
    this.telegramFileId,
    this.fileName,
    this.duration,
  });
}