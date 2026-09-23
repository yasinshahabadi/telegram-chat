import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:telegram_chat_mobile/config.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// موتور همگام‌سازی آفلاین و دریافت دلتای رویدادها بر پایه نشانگر ترتیبی سرور (Server Cursor)
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

  /// اجرای همگام‌سازی دلتا با سرور بر اساس آخرین نشانگر دیتابیس لوکال
  Future<bool> syncMissedEvents(String sessionToken, {Function()? onSyncCompleted}) async {
    if (_isSyncing || sessionToken.isEmpty) return false;
    _isSyncing = true;

    try {
      bool hasMore = true;

      while (hasMore) {
        // ۱. خواندن آخرین نشانگر ذخیره‌شده در SQLite
        final currentCursor = await _localDao.getSyncCursor();
        final url = Uri.parse('$_baseUrl/api/sync?cursor=$currentCursor&limit=50');

        final response = await _client.get(
          url,
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Accept': 'application/json',
          },
        ).timeout(_timeout);

        if (response.statusCode != 200) {
          break;
        }

        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['ok'] != true) break;

        final events = data['events'] as List<dynamic>? ?? [];
        if (events.isEmpty) {
          break;
        }

        // ۲. اعمال ترتیبی رویدادها در پایگاه داده محلی SQLite
        for (final rawEvent in events) {
          final event = rawEvent as Map<String, dynamic>;
          await _applyEventToLocalDatabase(event);
        }

        // ۳. ذخیره نشانگر به‌روزشده در SQLite
        final latestCursor = data['latestCursor'] as int? ?? currentCursor;
        await _localDao.setSyncCursor(latestCursor);

        hasMore = data['hasMore'] == true;
      }

      onSyncCompleted?.call();
      return true;
    } on SocketException {
      // قطعی اینترنت طبیعی است و بدون کرش مدیریت می‌شود
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// اعمال یک رویداد خاص در دیتابیس محلی
  Future<void> _applyEventToLocalDatabase(Map<String, dynamic> event) async {
    final eventType = event['eventType'] as String? ?? event['event_type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (eventType == null || payload == null) return;

    switch (eventType) {
      case 'message_created':
        final message = ChatMessageModel.fromJson(payload);
        await _localDao.saveMessage(message.toDbMap());

        // ✅ ذخیره attachment
        if (message.attachment != null) {
          try {
            await _localDao.saveAttachment(message.attachment!.toDbMap());
          } catch (_) {}
        } else if (payload['attachment'] != null && payload['attachment'] is Map<String, dynamic>) {
          final att = MediaAttachmentModel.fromJson(payload['attachment'] as Map<String, dynamic>);
          await _localDao.saveAttachment(att.toDbMap());
        }
        break;

      case 'message_edited':
        final messageId = payload['messageId'] as String? ?? payload['id'] as String?;
        final text = payload['text'] as String? ?? '';
        if (messageId != null) {
          await _localDao.updateMessageText(messageId, text);
        }
        break;

      case 'message_pinned':
        final messageId = payload['messageId'] as String? ?? payload['id'] as String?;
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
