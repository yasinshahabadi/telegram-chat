import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'chat_websocket_client.dart';
import 'pending_action_queue.dart';
import 'socket_event_dispatcher.dart';
import 'upload_lifecycle.dart';

class ChatRepository extends ChangeNotifier {
  final LocalChatDao _localDao;
  final ChatWebSocketClient _socketClient;

  /// ✅ هندلر رویدادهای سوکت (Stage 6).
  late final SocketEventDispatcher _dispatcher;

  /// ✅ چرخهٔ آپلود و ساخت پیام (Stage 7).
  late final UploadLifecycle _uploadLifecycle;

  /// ✅ صف اکشن‌های معلق (Stage 7).
  late final PendingActionQueue _pendingQueue;

  List<ChatMessageModel> _messages = [];
  ChatMessageModel? _pinnedMessage;
  String? _typingUserName;
  String? _currentUserId;
  Timer? _typingTimer;
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

    _uploadLifecycle = UploadLifecycle(
      localDao: _localDao,
      getMessages: () => _messages,
      notify: () => notifyListeners(),
    );

    _pendingQueue = PendingActionQueue(
      localDao: _localDao,
      socketClient: _socketClient,
      onMessageStatusChanged: (messageId, status) {
        _uploadLifecycle.updateStatusInMemory(messageId, status);
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
          _pendingQueue.scheduleRetry(immediate: true);
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
        _dispatcher.handle(event).catchError((e, st) {
          debugPrint('[ChatRepo] Failed to handle socket event: $e\n$st');
        });
      });

      _pendingQueue.scheduleRetry();
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLocalMessages({int limit = 50}) async {
    try {
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

  // ═════════════════════════════════════════════
  //  Send / delete (coordination)
  // ═════════════════════════════════════════════

  Future<void> sendMessage({
    required String text,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    final optimistic = await _uploadLifecycle.createOptimisticText(
      text: text,
      currentUser: currentUser,
      replyTo: replyTo,
    );

    final rp = ReplyPreviewInfo.from(replyTo);
    final socketReplyPayload =
        rp?.toSocketPayload(tgMsgId: replyTo?.telegramMessageId);

    await _pendingQueue.enqueueSendMessage(
      messageId: optimistic.id,
      clientMessageId: optimistic.clientMessageId!,
      text: text,
      replyTo: socketReplyPayload,
    );

    if (_socketClient.isConnected) {
      final sent = _socketClient.sendChatMessage(
        text: text,
        clientMessageId: optimistic.clientMessageId,
        replyTo: socketReplyPayload,
      );

      if (sent) {
        await _localDao.updateMessageStatus(optimistic.id, 'sending');
        _uploadLifecycle.updateStatusInMemory(
            optimistic.id, MessageStatus.sending);
      }
    }

    _pendingQueue.scheduleRetry();
  }

  Future<void> deleteMessage(String messageId) async {
    await _pendingQueue.enqueueDeleteMessage(messageId);

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

    _pendingQueue.scheduleRetry();
  }

  /// public API — پاکسازی صف (در main.dart صدا زده می‌شود).
  Future<void> processPendingQueue() => _pendingQueue.processQueue();

  // ═════════════════════════════════════════════
  //  Read / reaction
  // ═════════════════════════════════════════════

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

  // ═════════════════════════════════════════════
  //  Upload (delegate to lifecycle)
  // ═════════════════════════════════════════════

  Future<ChatMessageModel> addOptimisticMultiUpload({
    required List<File> files,
    required List<String> mediaTypes,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) {
    return _uploadLifecycle.addOptimisticMultiUpload(
      files: files,
      mediaTypes: mediaTypes,
      currentUser: currentUser,
      replyTo: replyTo,
    );
  }

  void updateUploadProgress(String tempId, double progress) {
    _uploadLifecycle.updateUploadProgress(tempId, progress);
  }

  void finalizeMultiUpload({
    required String tempId,
    String? clientMessageId,
    required String realMessageId,
    required List<MediaAttachmentModel> attachments,
  }) {
    _uploadLifecycle.finalizeMultiUpload(
      tempId: tempId,
      clientMessageId: clientMessageId,
      realMessageId: realMessageId,
      attachments: attachments,
    );
  }

  Future<void> failUpload(String tempId, String error) {
    return _uploadLifecycle.failUpload(tempId, error);
  }

  void prepareForRetry(String messageId, {String? newText}) {
    _uploadLifecycle.prepareForRetry(messageId, newText: newText);
  }

  void setLocalPathForAttachment(
    String messageId,
    String attachmentId,
    String localPath,
  ) {
    _uploadLifecycle.setLocalPathForAttachment(
        messageId, attachmentId, localPath);
  }

  // ═════════════════════════════════════════════
  //  Edit / pin / typing
  // ═════════════════════════════════════════════

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
    _pendingQueue.dispose();
    super.dispose();
  }
}