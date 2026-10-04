import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'chat_websocket_client.dart';

/// صف اکشن‌های معلق (`pending_actions`).
///
/// مسئول:
///   - enqueue پیام‌های متنی و درخواست‌های حذف
///   - تلاش برای ارسال هر اکشن معلق هنگام اتصال سوکت
///   - زمان‌بندی retry دوره‌ای
///
/// این کلاس مستقل است چون فقط به localDao، socketClient و یک callback
/// برای همگام‌سازی وضعیت پیام در حافظه نیاز دارد.
class PendingActionQueue {
  final LocalChatDao localDao;
  final ChatWebSocketClient socketClient;

  /// callback پس از موفقیت ارسال: `(messageId, newStatus)`.
  final void Function(String messageId, MessageStatus newStatus)
      onMessageStatusChanged;

  Timer? _retryTimer;
  bool _isDisposed = false;

  PendingActionQueue({
    required this.localDao,
    required this.socketClient,
    required this.onMessageStatusChanged,
  });

  // ═════════════════════════════════════════════
  //  Enqueue
  // ═════════════════════════════════════════════

  Future<void> enqueueSendMessage({
    required String messageId,
    required String clientMessageId,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    try {
      final payloadJson = jsonEncode({
        'messageId': messageId,
        'clientMessageId': clientMessageId,
        'text': text,
        'replyTo': replyTo,
      });
      await localDao.enqueuePendingAction(
          messageId, 'send_message', payloadJson);
    } catch (e) {
      debugPrint('[PendingQueue] enqueueSendMessage failed: $e');
    }
  }

  Future<void> enqueueDeleteMessage(String messageId) async {
    final actionId = 'delete_$messageId';
    try {
      await localDao.enqueuePendingAction(
        actionId,
        'delete_message',
        jsonEncode({'messageId': messageId}),
      );
    } catch (e) {
      debugPrint('[PendingQueue] enqueueDeleteMessage failed: $e');
    }
  }

  // ═════════════════════════════════════════════
  //  Process
  // ═════════════════════════════════════════════

  Future<void> processQueue() async {
    if (_isDisposed) return;
    if (!socketClient.isConnected) return;

    final pendingActions = await localDao.getPendingActions();
    if (pendingActions.isEmpty) return;

    for (final action in pendingActions) {
      final actionType = action['action_type'] as String;
      final actionId = action['id'] as String;

      if (actionType == 'send_message') {
        try {
          final Map<String, dynamic> payload =
              jsonDecode(action['payload_json'] as String);
          final sent = socketClient.sendChatMessage(
            text: payload['text'] as String,
            clientMessageId: payload['clientMessageId'] as String?,
            replyTo: payload['replyTo'] as Map<String, dynamic>?,
          );

          if (sent) {
            await localDao.removePendingAction(actionId);
            await localDao.updateMessageStatus(actionId, 'sending');
            onMessageStatusChanged(actionId, MessageStatus.sending);
          }
        } catch (e) {
          debugPrint('[PendingQueue] process send_message failed: $e');
        }
      } else if (actionType == 'delete_message') {
        try {
          final Map<String, dynamic> payload =
              jsonDecode(action['payload_json'] as String);
          final mId = payload['messageId'] as String?;
          if (mId != null) {
            socketClient.sendDeleteMessage(mId);
          }
        } catch (e) {
          debugPrint('[PendingQueue] process delete_message failed: $e');
        }
      }
    }
  }

  // ═════════════════════════════════════════════
  //  Retry scheduling
  // ═════════════════════════════════════════════

  void scheduleRetry({bool immediate = false}) {
    if (_isDisposed) return;
    _retryTimer?.cancel();

    if (!socketClient.isConnected) return;

    final delay = immediate ? Duration.zero : const Duration(seconds: 12);

    _retryTimer = Timer(delay, () async {
      if (_isDisposed) return;
      if (!socketClient.isConnected) return;

      try {
        final actions = await localDao.getPendingActions();
        if (actions.isEmpty) return;

        await processQueue();
        scheduleRetry();
      } catch (_) {
        scheduleRetry();
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}