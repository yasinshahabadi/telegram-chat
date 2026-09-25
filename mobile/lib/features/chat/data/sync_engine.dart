import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:telegram_chat_mobile/config.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// ✅ نتیجه همگام‌سازی — برای تصمیم‌گیری درباره نمایش اعلان
class SyncResult {
  final bool success;
  final int newMessagesCount;
  final String? lastMessageSender;
  final String? lastMessageText;

  const SyncResult({
    required this.success,
    this.newMessagesCount = 0,
    this.lastMessageSender,
    this.lastMessageText,
  });

  SyncResult.failure() : this(success: false);
}

/// موتور همگام‌سازی آفلاین و دریافت دلتای رویدادها بر پایه نشانگر ترتیبی سرور
class SyncEngine {
  final LocalChatDao _localDao;
  final http.Client _client;
  final String _baseUrl;

  bool _isSyncing = false;
  static const Duration _timeout = Duration(seconds: 15);

  SyncEngine({
    required LocalChatDao localDao,
    http.Client? client,
    String? baseUrl,
  })  : _localDao = localDao,
        _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  bool get isSyncing => _isSyncing;

  /// اجرای همگام‌سازی + بازگرداندن تعداد پیام‌های جدید
  Future<SyncResult> syncMissedEvents(
    String sessionToken, {
    String? currentUserId,
    Function()? onSyncCompleted,
  }) async {
    if (_isSyncing || sessionToken.isEmpty) {
      return const SyncResult(success: false);
    }
    _isSyncing = true;

    int newMessagesCount = 0;
    String? lastSender;
    String? lastText;

    try {
      bool hasMore = true;

      while (hasMore) {
        final currentCursor = await _localDao.getSyncCursor();
        final url = Uri.parse('$_baseUrl/api/sync?cursor=$currentCursor&limit=50');

        final response = await _client.get(
          url,
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Accept': 'application/json',
          },
        ).timeout(_timeout);

        if (response.statusCode != 200) break;

        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['ok'] != true) break;

        final events = data['events'] as List<dynamic>? ?? [];
        if (events.isEmpty) break;

        for (final rawEvent in events) {
          final event = rawEvent as Map<String, dynamic>;
          final eventType = event['eventType'] as String?;

          // ✅ شمارش پیام‌های جدید از سایر کاربران (برای اعلان بعدی)
          if (eventType == 'message_created') {
            final payload = event['payload'] as Map<String, dynamic>?;
            if (payload != null) {
              final senderId = payload['senderId'] as String?;
              if (currentUserId == null || senderId != currentUserId) {
                newMessagesCount++;
                lastSender = payload['senderName'] as String?;
                lastText = payload['text'] as String?;
              }
            }
          }

          await _applyEventToLocalDatabase(event);
        }

        final latestCursor = data['latestCursor'] as int? ?? currentCursor;
        await _localDao.setSyncCursor(latestCursor);

        hasMore = data['hasMore'] == true;
      }

      onSyncCompleted?.call();

      return SyncResult(
        success: true,
        newMessagesCount: newMessagesCount,
        lastMessageSender: lastSender,
        lastMessageText: lastText,
      );
    } on SocketException {
      return const SyncResult(success: false);
    } on TimeoutException {
      return const SyncResult(success: false);
    } catch (_) {
      return const SyncResult(success: false);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _applyEventToLocalDatabase(Map<String, dynamic> event) async {
    final eventType =
        event['eventType'] as String? ?? event['event_type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (eventType == null || payload == null) return;

    switch (eventType) {
      case 'message_created':
        final message = ChatMessageModel.fromJson(payload);
        await _localDao.saveMessage(message.toDbMap());

        if (message.attachment != null) {
          try {
            await _localDao.saveAttachment(message.attachment!.toDbMap());
          } catch (_) {}
        } else if (payload['attachment'] != null &&
            payload['attachment'] is Map<String, dynamic>) {
          final att = MediaAttachmentModel.fromJson(
              payload['attachment'] as Map<String, dynamic>);
          await _localDao.saveAttachment(att.toDbMap());
        }
        break;

      case 'message_edited':
        final messageId =
            payload['messageId'] as String? ?? payload['id'] as String?;
        final text = payload['text'] as String? ?? '';
        if (messageId != null) {
          await _localDao.updateMessageText(messageId, text);
        }
        break;

      case 'message_pinned':
        final messageId =
            payload['messageId'] as String? ?? payload['id'] as String?;
        if (messageId != null) {
          await _localDao.setPinnedMessage(messageId, true);
        }
        break;

      case 'message_unpinned':
        break;

      case 'reaction_updated':
        break;
    }
  }
}