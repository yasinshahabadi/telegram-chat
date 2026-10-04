import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// هندلر رویدادهای ورودی سوکت.
class SocketEventDispatcher {
  final LocalChatDao localDao;

  final List<ChatMessageModel> Function() getMessages;
  final String? Function() getCurrentUserId;
  final ChatMessageModel? Function() getPinnedMessage;
  final void Function() notifyChanged;
  final void Function(ChatMessageModel? pinned) setPinnedMessage;
  final void Function(String? fullName) setTypingUserName;
  final void Function(Map<String, Map<String, dynamic>> users) setOnlineUsers;

  SocketEventDispatcher({
    required this.localDao,
    required this.getMessages,
    required this.getCurrentUserId,
    required this.getPinnedMessage,
    required this.notifyChanged,
    required this.setPinnedMessage,
    required this.setTypingUserName,
    required this.setOnlineUsers,
  });

  // ═════════════════════════════════════════════
  //  Entry point
  // ═════════════════════════════════════════════

  Future<void> handle(Map<String, dynamic> event) async {
    final type = event['type'] as String?;
    if (type == null) return;

    if (type != 'pong' && type != 'typing' && type != 'online_users') {
      debugPrint('[Socket] ← $type');
    }

    switch (type) {
      case 'pong':
        return;
      case 'online_users':
        if (event['users'] != null) _handleOnlineUsers(event);
        return;
      case 'messages_read':
        if (event['messageIds'] != null) await _handleMessagesRead(event);
        return;
      case 'new_message':
        if (event['message'] != null) await _handleNewMessage(event);
        return;
      case 'message_ack':
        if (event['clientMessageId'] != null) await _handleMessageAck(event);
        return;
      case 'message_edited':
        if (event['messageId'] != null) await _handleMessageEdited(event);
        return;
      case 'message_deleted':
        if (event['messageId'] != null) await _handleMessageDeleted(event);
        return;
      case 'reaction_updated':
        if (event['messageId'] != null) await _handleReactionUpdated(event);
        return;
      case 'message_pinned':
        if (event['message'] != null) await _handleMessagePinned(event);
        return;
      case 'message_unpinned':
        _handleMessageUnpinned();
        return;
      case 'typing':
        if (event['fullName'] != null) _handleTyping(event);
        return;
      case 'error':
        debugPrint('[Socket] Server error: ${event['message']}');
        return;
    }
  }

  // ═════════════════════════════════════════════
  //  Handlers
  // ═════════════════════════════════════════════

  void _handleOnlineUsers(Map<String, dynamic> event) {
    final usersList = (event['users'] as List).cast<Map<String, dynamic>>();
    final map = <String, Map<String, dynamic>>{};
    for (final u in usersList) {
      final id = u['userId'] as String?;
      if (id != null) map[id] = u;
    }
    setOnlineUsers(map);
  }

  Future<void> _handleMessagesRead(Map<String, dynamic> event) async {
    final userId = getCurrentUserId();
    if (userId == null) return;

    final ids = (event['messageIds'] as List).cast<String>();
    final readerId = event['userId'] as String?;
    final readAt = event['readAt'] as int? ??
        DateTime.now().millisecondsSinceEpoch;

    final messages = getMessages();
    final toMark = <String>[];

    for (final id in ids) {
      final idx = messages.indexWhere((m) => m.id == id);
      if (idx != -1) {
        final msg = messages[idx];
        if (msg.senderId == userId &&
            msg.senderId != readerId &&
            msg.readAt == null) {
          toMark.add(id);
          messages[idx] = msg.copyWith(readAt: readAt);
        }
      }
    }

    if (toMark.isNotEmpty) {
      await localDao.markMessagesAsRead(toMark, readAt);
      notifyChanged();
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> event) async {
    final userId = getCurrentUserId();
    if (userId == null) return;

    final msgJson = event['message'] as Map<String, dynamic>;
    final incoming = ChatMessageModel.fromJson(msgJson, currentUserId: userId);
    final clientMsgId = incoming.clientMessageId;
    final messages = getMessages();

    debugPrint('[Socket] new_message id=${incoming.id} '
        'clientMsgId=$clientMsgId text="${incoming.text}"');

    // Case 1: match by clientMessageId
    if (clientMsgId != null) {
      final idx = messages.indexWhere((m) => m.clientMessageId == clientMsgId);
      if (idx != -1) {
        final existing = messages[idx];
        final mergedAtts = _mergeAttachmentsByIndex(
          existing.attachments,
          incoming.attachments,
        );
        final merged = existing.copyWith(
          id: incoming.id,
          telegramMessageId: incoming.telegramMessageId,
          status: MessageStatus.synced,
          isUploading: false,
          uploadProgress: 1.0,
          attachments: mergedAtts,
          updatedAt: incoming.updatedAt,
          replyToName: incoming.replyToName ?? existing.replyToName,
          replyToText: incoming.replyToText ?? existing.replyToText,
          replyToMediaType:
              incoming.replyToMediaType ?? existing.replyToMediaType,
          replyToAttachmentId:
              incoming.replyToAttachmentId ?? existing.replyToAttachmentId,
          replyToTelegramFileId: incoming.replyToTelegramFileId ??
              existing.replyToTelegramFileId,
          replyToFileName:
              incoming.replyToFileName ?? existing.replyToFileName,
          replyToDuration:
              incoming.replyToDuration ?? existing.replyToDuration,
        );
        await localDao.saveMessage(merged.toDbMap());
        for (final a in merged.attachments) {
          try {
            await localDao.saveAttachment(a.toDbMap());
          } catch (_) {}
        }
        await localDao.removePendingAction(existing.id);
        messages[idx] = merged;
        notifyChanged();
        return;
      }
    }

    // Case 2: match by id
    final idxById = messages.indexWhere((m) => m.id == incoming.id);
    if (idxById != -1) {
      final existing = messages[idxById];
      final mergedAtts = _mergeAttachmentsByIndex(
        existing.attachments,
        incoming.attachments,
      );
      final merged = existing.copyWith(
        clientMessageId: incoming.clientMessageId ?? existing.clientMessageId,
        attachments: mergedAtts,
      );
      await localDao.saveMessage(merged.toDbMap());
      for (final a in merged.attachments) {
        try {
          await localDao.saveAttachment(a.toDbMap());
        } catch (_) {}
      }
      messages[idxById] = merged;
      notifyChanged();
      return;
    }

    // Case 3: کاملاً جدید
    await localDao.saveMessage(incoming.toDbMap());
    for (final a in incoming.attachments) {
      try {
        await localDao.saveAttachment(a.toDbMap());
      } catch (_) {}
    }
    messages.insert(0, incoming);
    notifyChanged();
  }

  /// ✅ ack از سرور برای پیام متنی.
  ///
  /// باگ قبلی: تنها `updateMessageStatus(realMessageId, 'synced')` صدا زده
  /// می‌شد، ولی چون ردیفی با `id=realMessageId` هنوز در DB نبود (ردیف فعلی
  /// id=clientUuid دارد)، این UPDATE بی‌اثر بود. نتیجه: پیام در DB با
  /// `id=clientUuid` و `status=sending` رها می‌شد. اگر اپ پیش از رسیدن
  /// `new_message` بسته می‌شد، پیام با id اشتباه بارگذاری می‌شد.
  ///
  /// راه‌حل: `saveMessage` را با id جدید صدا بزن — rename branch ردیف قدیمی
  /// را حذف و ردیف جدید را insert می‌کند.
  Future<void> _handleMessageAck(Map<String, dynamic> event) async {
    final clientMsgId = event['clientMessageId'] as String;
    final realMessageId = event['messageId'] as String?;
    if (realMessageId == null) return;

    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.clientMessageId == clientMsgId);
    if (idx == -1) return;

    final old = messages[idx];
    final updated = old.copyWith(
      id: realMessageId,
      status: MessageStatus.synced,
    );
    messages[idx] = updated;

    try {
      await localDao.saveMessage(updated.toDbMap());
    } catch (e) {
      debugPrint('[Socket] message_ack saveMessage failed: $e');
    }

    notifyChanged();
  }

  Future<void> _handleMessageEdited(Map<String, dynamic> event) async {
    final mId = event['messageId'] as String;
    final newText = event['text'] as String? ?? '';
    await localDao.updateMessageText(mId, newText);

    final messages = getMessages();
    final index = messages.indexWhere((m) => m.id == mId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(text: newText, isEdited: true);
      notifyChanged();
    }
  }

  Future<void> _handleMessageDeleted(Map<String, dynamic> event) async {
    final mId = event['messageId'] as String;
    final messages = getMessages();
    messages.removeWhere((m) => m.id == mId);

    if (getPinnedMessage()?.id == mId) {
      setPinnedMessage(null);
    }

    notifyChanged();

    try {
      await localDao.deleteMessage(mId);
    } catch (_) {}
    try {
      await localDao.removePendingAction('delete_$mId');
    } catch (_) {}
  }

  Future<void> _handleReactionUpdated(Map<String, dynamic> event) async {
    final mId = event['messageId'] as String;
    final rawList = event['reactions'];
    final List<Map<String, dynamic>> aggregated = [];
    if (rawList is List) {
      for (final r in rawList) {
        if (r is Map) aggregated.add(r.cast<String, dynamic>());
      }
    }

    final userId = getCurrentUserId();
    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == mId);

    if (idx != -1) {
      final newReactions = <String, int>{};
      final newMyReactions = <String>{};

      for (final r in aggregated) {
        final emoji = r['emoji'] as String?;
        if (emoji == null || emoji.isEmpty) continue;
        final count = (r['count'] as num?)?.toInt() ?? 0;
        newReactions[emoji] = count;

        final ids =
            (r['userIds'] as List?)?.whereType<String>().toList() ?? const [];
        if (userId != null && ids.contains(userId)) {
          newMyReactions.add(emoji);
        }
      }

      messages[idx] = messages[idx].copyWith(
        reactions: newReactions,
        myReactions: newMyReactions,
      );
      notifyChanged();
    }

    try {
      await localDao.replaceReactionsForMessage(mId, aggregated);
    } catch (_) {}
  }

  Future<void> _handleMessagePinned(Map<String, dynamic> event) async {
    final userId = getCurrentUserId();
    if (userId == null) return;

    final msgJson = event['message'] as Map<String, dynamic>;
    final pinned = ChatMessageModel.fromJson(msgJson, currentUserId: userId);
    await localDao.setPinnedMessage(pinned.id, true);

    setPinnedMessage(pinned);

    final messages = getMessages();
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].id != pinned.id && messages[i].isPinned) {
        messages[i] = messages[i].copyWith(isPinned: false);
      }
    }
    final index = messages.indexWhere((m) => m.id == pinned.id);
    if (index != -1) {
      messages[index] = messages[index].copyWith(isPinned: true);
    }
    notifyChanged();
  }

  void _handleMessageUnpinned() {
    setPinnedMessage(null);

    final messages = getMessages();
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].isPinned) {
        messages[i] = messages[i].copyWith(isPinned: false);
      }
    }
    notifyChanged();
  }

  void _handleTyping(Map<String, dynamic> event) {
    setTypingUserName(event['fullName'] as String);
  }

  // ═════════════════════════════════════════════
  //  Helpers
  // ═════════════════════════════════════════════

  List<MediaAttachmentModel> _mergeAttachmentsByIndex(
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
}