import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

class LocalChatDao {
  final AppDatabase _appDatabase;

  LocalChatDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db async => await _appDatabase.database;

  // ==========================================
  // پیام‌ها
  // ==========================================

  Future<void> saveMessage(Map<String, dynamic> messageData) async {
    final db = await _db;
    await db.insert(
      'messages',
      {
        'id': messageData['id'],
        'client_message_id': messageData['client_message_id'] ?? messageData['clientMessageId'],
        'sender_id': messageData['sender_id'] ?? messageData['senderId'],
        'sender_name': messageData['sender_name'] ?? messageData['senderName'] ?? 'کاربر',
        'text': messageData['text'] ?? '',
        'is_from_telegram': (messageData['is_from_telegram'] == 1 || messageData['isFromTelegram'] == true) ? 1 : 0,
        'telegram_message_id': messageData['telegram_message_id'] ?? messageData['telegramMessageId'],
        'reply_to_message_id': messageData['reply_to_message_id'] ?? messageData['replyToId'],
        'reply_to_name': messageData['reply_to_name'] ?? messageData['replyToName'],
        'reply_to_text': messageData['reply_to_text'] ?? messageData['replyToText'],
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

  /// ✅ واکشی یک پیام بر اساس شناسه (برای merge در sync)
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

  // ==========================================
  // پیوست‌ها
  // ==========================================

  Future<void> saveAttachment(Map<String, dynamic> data) async {
    final db = await _db;
    await db.insert(
      'attachments',
      {
        'id': data['id'],
        'message_id': data['message_id'] ?? data['messageId'],
        'media_type': data['media_type'] ?? data['mediaType'],
        'local_path': data['local_path'] ?? data['localPath'],
        'r2_key': data['r2_key'] ?? data['r2Key'],
        'telegram_file_id': data['telegram_file_id'] ?? data['telegramFileId'],
        'file_name': data['file_name'] ?? data['fileName'],
        'file_size': data['file_size'] ?? data['fileSize'],
        'mime_type': data['mime_type'] ?? data['mimeType'],
        'duration': data['duration'] ?? 0,
        'upload_progress': data['upload_progress'] ?? 1.0,
        'download_progress': data['download_progress'] ?? 1.0,
        'is_downloaded': (data['is_downloaded'] == 1 || data['isDownloaded'] == true) ? 1 : 0,
        'created_at': data['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
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