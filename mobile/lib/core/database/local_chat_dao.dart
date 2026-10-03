import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

const _uuid = Uuid();

class LocalChatDao {
  final AppDatabase _appDatabase;

  LocalChatDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db async => await _appDatabase.database;

  // ==========================================
  // پیام‌ها
  // ==========================================

  Future<bool> _isPendingDelete(Database db, String messageId) async {
    try {
      final rows = await db.query(
        'pending_actions',
        columns: ['payload_json'],
        where: 'action_type = ?',
        whereArgs: ['delete_message'],
      );
      for (final row in rows) {
        try {
          final payload = jsonDecode(row['payload_json'] as String);
          if (payload is Map && payload['messageId'] == messageId) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveMessage(Map<String, dynamic> messageData) async {
    final db = await _db;
    final messageId = messageData['id'] as String?;
    if (messageId == null || messageId.isEmpty) return;

    if (await _isPendingDelete(db, messageId)) {
      return;
    }

    await db.insert(
      'messages',
      {
        'id': messageId,
        'client_message_id': messageData['client_message_id'] ?? messageData['clientMessageId'],
        'sender_id': messageData['sender_id'] ?? messageData['senderId'],
        'sender_name': messageData['sender_name'] ?? messageData['senderName'] ?? 'کاربر',
        'text': messageData['text'] ?? '',
        'is_from_telegram': (messageData['is_from_telegram'] == 1 || messageData['isFromTelegram'] == true) ? 1 : 0,
        'telegram_message_id': messageData['telegram_message_id'] ?? messageData['telegramMessageId'],
        'reply_to_message_id': messageData['reply_to_message_id'] ?? messageData['replyToId'],
        'reply_to_name': messageData['reply_to_name'] ?? messageData['replyToName'],
        'reply_to_text': messageData['reply_to_text'] ?? messageData['replyToText'],
        'reply_to_media_type': messageData['reply_to_media_type'] ?? messageData['replyToMediaType'],
        'reply_to_attachment_id': messageData['reply_to_attachment_id'] ?? messageData['replyToAttachmentId'],
        'reply_to_telegram_file_id': messageData['reply_to_telegram_file_id'] ?? messageData['replyToTelegramFileId'],
        'reply_to_file_name': messageData['reply_to_file_name'] ?? messageData['replyToFileName'],
        'reply_to_duration': messageData['reply_to_duration'] ?? messageData['replyToDuration'],
        'is_pinned': (messageData['is_pinned'] == 1 || messageData['isPinned'] == true) ? 1 : 0,
        'is_edited': (messageData['is_edited'] == 1 || messageData['isEdited'] == true) ? 1 : 0,
        'status': messageData['status'] ?? 'synced',
        'read_at': messageData['read_at'] ?? messageData['readAt'],
        'created_at': messageData['created_at'] ?? messageData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'updated_at': messageData['updated_at'] ?? messageData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getMessagesList({int limit = 40, int? beforeCreatedAt}) async {
    final db = await _db;
    if (beforeCreatedAt != null) {
      return await db.query(
        'messages',
        where: 'created_at < ?',
        whereArgs: [beforeCreatedAt],
        orderBy: 'created_at DESC',
        limit: limit,
      );
    }

    return await db.query(
      'messages',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getMessageById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateMessageStatus(String messageId, String newStatus) async {
    final db = await _db;
    await db.update(
      'messages',
      {'status': newStatus, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageText(String messageId, String newText) async {
    final db = await _db;
    await db.update(
      'messages',
      {
        'text': newText,
        'is_edited': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> setPinnedMessage(String messageId, bool isPinned) async {
    final db = await _db;
    if (isPinned) {
      await db.update('messages', {'is_pinned': 0});
    }
    await db.update(
      'messages',
      {'is_pinned': isPinned ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markMessagesAsRead(List<String> messageIds, int readAt) async {
    if (messageIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(messageIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE messages SET read_at = ? WHERE id IN ($placeholders) AND read_at IS NULL',
      [readAt, ...messageIds],
    );
  }

  Future<void> applyRemoteReadReceipt(
    List<String> messageIds,
    int readAt,
    String myUserId,
  ) async {
    if (messageIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(messageIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE messages SET read_at = ? '
      'WHERE id IN ($placeholders) AND read_at IS NULL AND sender_id = ?',
      [readAt, ...messageIds, myUserId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'id = ?', whereArgs: [messageId]);
      await txn.delete('attachments', where: 'message_id = ?', whereArgs: [messageId]);
      await txn.delete('reactions', where: 'message_id = ?', whereArgs: [messageId]);
    });
  }

  // ==========================================
  // پیوست‌ها
  // ==========================================

  /// ✅ ذخیره یا به‌روزرسانی پیوست با حفظ داده‌های محلی.
  ///
  /// اگر داده‌ورودی `local_path` نداشته باشد (مثل پیام‌های آمده از سرور در sync)،
  /// مقدار قبلی روی دیسک حفظ می‌شود. بدون این، هر sync مسیر کش را پاک می‌کرد
  /// و عکس‌های آپلودشده ناپدید می‌شدند.
  Future<void> saveAttachment(Map<String, dynamic> data) async {
    final db = await _db;
    final id = data['id'] as String?;
    if (id == null || id.isEmpty) return;

    // واکشی ردیف فعلی (اگر وجود دارد) برای حفظ فیلدهای محلی
    Map<String, dynamic>? existing;
    try {
      final rows = await db.query(
        'attachments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      existing = rows.isNotEmpty ? rows.first : null;
    } catch (_) {}

    // مقدار ورودی
    final incomingLocalPath = data['local_path'] ?? data['localPath'];
    final incomingIsDownloaded = data['is_downloaded'] ?? data['isDownloaded'];
    final incomingMessageId = data['message_id'] ?? data['messageId'];

    // ✅ حفظ مقادیر قبلی در صورت نبود مقدار جدید
    final localPath = incomingLocalPath ?? existing?['local_path'] as String?;
    final isDownloaded = (incomingIsDownloaded == 1 || incomingIsDownloaded == true)
        ? 1
        : (existing?['is_downloaded'] as int? ?? 0);
    final messageId = incomingMessageId ?? existing?['message_id'];

    // اگر پیام مقصد تغییر کرده ولی مسیر محلی موجود است، ردیف را حفظ می‌کنیم.
    // اما اگر message_id جدید null باشد و قبلی هم null، ردیف را نادیده می‌گیریم.
    if (messageId == null) return;

    await db.insert(
      'attachments',
      {
        'id': id,
        'message_id': messageId,
        'media_type': data['media_type'] ?? data['mediaType'] ?? existing?['media_type'] ?? 'document',
        'local_path': localPath,
        'r2_key': data['r2_key'] ?? data['r2Key'] ?? existing?['r2_key'],
        'telegram_file_id': data['telegram_file_id'] ?? data['telegramFileId'] ?? existing?['telegram_file_id'],
        'file_name': data['file_name'] ?? data['fileName'] ?? existing?['file_name'] ?? 'file',
        'file_size': data['file_size'] ?? data['fileSize'] ?? existing?['file_size'],
        'mime_type': data['mime_type'] ?? data['mimeType'] ?? existing?['mime_type'],
        'duration': data['duration'] ?? existing?['duration'] ?? 0,
        'upload_progress': data['upload_progress'] ?? existing?['upload_progress'] ?? 1.0,
        'download_progress': data['download_progress'] ?? existing?['download_progress'] ?? 1.0,
        'is_downloaded': isDownloaded,
        'created_at': data['created_at'] ?? data['createdAt'] ?? existing?['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAttachmentsForMessage(String messageId) async {
    final db = await _db;
    return await db.query(
      'attachments',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateAttachmentLocalPath(String attachmentId, String localPath) async {
    final db = await _db;
    await db.update(
      'attachments',
      {
        'local_path': localPath,
        'is_downloaded': 1,
      },
      where: 'id = ?',
      whereArgs: [attachmentId],
    );
  }

  /// ✅ حذف پیام‌های موقت (optimistic) که با id نهایی سرور جایگزین شده‌اند.
  Future<void> deleteOrphanTempMessages() async {
    final db = await _db;
    try {
      final orphans = await db.query(
        'messages',
        columns: ['id'],
        where: "id LIKE 'temp_upload_%'",
      );
      for (final o in orphans) {
        final mId = o['id'] as String?;
        if (mId == null) continue;
        // اگر پیامی با همان client_message_id در سرور ثبت شده، temp orphan است.
        final linked = await db.query(
          'messages',
          columns: ['id'],
          where: 'client_message_id = (SELECT client_message_id FROM messages WHERE id = ?) AND id != ?',
          whereArgs: [mId, mId],
          limit: 1,
        );
        if (linked.isNotEmpty) {
          await db.delete('messages', where: 'id = ?', whereArgs: [mId]);
          await db.delete('attachments', where: 'message_id = ?', whereArgs: [mId]);
        }
      }
    } catch (_) {}
  }

  // ==========================================
  // واکنش‌ها
  // ==========================================

  Future<List<Map<String, dynamic>>> getReactionsForMessage(String messageId) async {
    final db = await _db;
    return await db.query(
      'reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> replaceReactionsForMessage(
    String messageId,
    List<Map<String, dynamic>> aggregated,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete('reactions', where: 'message_id = ?', whereArgs: [messageId]);

      for (final r in aggregated) {
        final emoji = r['emoji'] as String?;
        if (emoji == null || emoji.isEmpty) continue;
        final count = (r['count'] as num?)?.toInt() ?? 0;
        final userIds = (r['userIds'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[];

        for (final uid in userIds) {
          await txn.insert(
            'reactions',
            {
              'id': _uuid.v4(),
              'message_id': messageId,
              'user_id': uid,
              'telegram_user_id': null,
              'emoji': emoji,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        final unknown = (count - userIds.length).clamp(0, count);
        for (int i = 0; i < unknown; i++) {
          await txn.insert(
            'reactions',
            {
              'id': _uuid.v4(),
              'message_id': messageId,
              'user_id': null,
              'telegram_user_id': null,
              'emoji': emoji,
              'created_at': now,
            },
          );
        }
      }
    });
  }

  // ==========================================
  // صف اکشن‌های معلق
  // ==========================================

  Future<void> enqueuePendingAction(String id, String actionType, String payloadJson) async {
    final db = await _db;
    await db.insert(
      'pending_actions',
      {
        'id': id,
        'action_type': actionType,
        'payload_json': payloadJson,
        'retry_count': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final db = await _db;
    return await db.query('pending_actions', orderBy: 'created_at ASC');
  }

  Future<void> removePendingAction(String id) async {
    final db = await _db;
    await db.delete('pending_actions', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================
  // نشانگر همگام‌سازی
  // ==========================================

  Future<void> setSyncCursor(int cursor) async {
    final db = await _db;
    await db.insert(
      'sync_state',
      {
        'key': 'last_server_cursor',
        'value': cursor.toString(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getSyncCursor() async {
    final db = await _db;
    final results = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['last_server_cursor'],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return int.tryParse(results.first['value'] as String) ?? 0;
    }
    return 0;
  }
}