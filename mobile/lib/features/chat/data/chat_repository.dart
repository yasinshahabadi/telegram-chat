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

/// نتیجهٔ آماده‌سازی پیامِ ریپلای‌شده برای پرش.
enum ReplyTargetLoadResult {
  /// پیام در حافظه/DB موجود و آمادهٔ نمایش است.
  loaded,

  /// پیام نه در حافظه است و نه در DB (حذف شده است).
  notFound,

  /// پیام در DB هست ولی بازهٔ تاریخی آن برای بارگذاری بیش از حد بزرگ است.
  tooOld,
}

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
      onMessageIdChanged: _repointReplyReferences,
    );

    _uploadLifecycle = UploadLifecycle(
      localDao: _localDao,
      getMessages: () => _messages,
      notify: () => notifyListeners(),
      onMessageIdChanged: _repointReplyReferences,
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
  //  Reply target availability
  // ═════════════════════════════════════════════

  /// حداکثر تعداد پیامی که برای پرش به یک پیام قدیمی از DB بارگذاری می‌شود.
  ///
  /// اگر پیام مقصد قدیمی‌تر از این بازه باشد، به‌جای بارگذاری هزاران پیام
  /// (و مصرف حافظه) [ReplyTargetLoadResult.tooOld] برگردانده می‌شود تا UI
  /// پیام مناسب نشان دهد.
  static const int _replyHistoryLimit = 1000;

  /// اطمینان از این‌که پیام [messageId] برای نمایش/پرش در حافظه موجود است.
  ///
  /// - اگر در حافظه باشد: [ReplyTargetLoadResult.loaded].
  /// - اگر در DB باشد ولی جزو ۵۰ پیام آخر نباشد: بازهٔ پیوستهٔ آن پیام تا
  ///   جدیدترین پیام بارگذاری و با لیست فعلی ادغام می‌شود.
  /// - اگر در DB هم نباشد (حذف‌شده): [ReplyTargetLoadResult.notFound].
  /// - اگر بازهٔ بارگذاری بیش از حد بزرگ باشد: [ReplyTargetLoadResult.tooOld].
  Future<ReplyTargetLoadResult> ensureMessageLoaded(String messageId) async {
    if (messageId.isEmpty) return ReplyTargetLoadResult.notFound;
    if (_messages.any((m) => m.id == messageId)) {
      return ReplyTargetLoadResult.loaded;
    }

    try {
      final targetRow = await _localDao.getMessageById(messageId);
      if (targetRow == null) return ReplyTargetLoadResult.notFound;

      final createdAt = targetRow['created_at'] as int? ?? 0;
      final rows = await _localDao.getMessagesSince(
        sinceCreatedAt: createdAt,
        limit: _replyHistoryLimit + 1,
      );

      if (rows.isEmpty) return ReplyTargetLoadResult.notFound;
      if (rows.length > _replyHistoryLimit) {
        debugPrint(
          '[ChatRepo] reply target $messageId is older than the load window',
        );
        return ReplyTargetLoadResult.tooOld;
      }

      final ids = rows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toList(growable: false);

      // دو کوئری برای همهٔ پیام‌ها به‌جای دو کوئری برای هر پیام.
      final attachmentsByMessage =
          await _localDao.getAttachmentsForMessages(ids);
      final reactionsByMessage = await _localDao.getReactionsForMessages(ids);

      final loaded = <ChatMessageModel>[];
      for (final raw in rows) {
        final id = raw['id'] as String?;
        if (id == null) continue;

        final attachments =
            (attachmentsByMessage[id] ?? const <Map<String, dynamic>>[])
                .map(MediaAttachmentModel.fromDbMap)
                .toList(growable: false);

        final reactions = <String, int>{};
        final myReactions = <String>{};
        for (final reaction
            in reactionsByMessage[id] ?? const <Map<String, dynamic>>[]) {
          final emoji = reaction['emoji'] as String?;
          if (emoji == null || emoji.isEmpty) continue;
          reactions[emoji] = (reactions[emoji] ?? 0) + 1;
          if (_currentUserId != null &&
              reaction['user_id'] == _currentUserId) {
            myReactions.add(emoji);
          }
        }

        loaded.add(ChatMessageModel.fromDbMap(
          raw,
          attachments: attachments,
          reactions: reactions,
          myReactions: myReactions,
        ));
      }

      // پیام‌های داخل حافظه ممکن است وضعیت تازه‌تری (در حال آپلود/خوانده‌شده)
      // داشته باشند؛ بنابراین نسخهٔ حافظه اولویت دارد.
      final mergedById = <String, ChatMessageModel>{
        for (final message in loaded) message.id: message,
      };
      for (final message in _messages) {
        mergedById[message.id] = message;
      }

      final merged = mergedById.values.toList(growable: false)
        ..sort((a, b) {
          final byTime = b.createdAt.compareTo(a.createdAt);
          return byTime != 0 ? byTime : b.id.compareTo(a.id);
        });

      _messages = merged;
      notifyListeners();

      return _messages.any((m) => m.id == messageId)
          ? ReplyTargetLoadResult.loaded
          : ReplyTargetLoadResult.notFound;
    } catch (e) {
      debugPrint('[ChatRepo] ensureMessageLoaded failed: $e');
      return ReplyTargetLoadResult.notFound;
    }
  }

  /// وقتی یک پیام optimistic شناسهٔ واقعی می‌گیرد، ارجاع‌های reply به شناسهٔ
  /// قبلی باید به‌روز شوند؛ وگرنه کلیک روی همان پیش‌نمایش reply بعداً
  /// «پیام موجود نیست» نشان می‌دهد.
  Future<void> _repointReplyReferences(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;

    var changed = false;
    for (int i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.replyToMessageId == oldId) {
        _messages[i] = message.copyWith(replyToMessageId: newId);
        changed = true;
      }
    }
    if (changed) notifyListeners();

    try {
      await _localDao.updateReplyTargetId(oldId, newId);
    } catch (_) {}
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
    String caption = '',
  }) {
    return _uploadLifecycle.addOptimisticMultiUpload(
      files: files,
      mediaTypes: mediaTypes,
      currentUser: currentUser,
      replyTo: replyTo,
      caption: caption,
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
