import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite Database Manager with fail-safe pragmas
class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  static Database? _database;

  AppDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'telegram_chat_local_v2.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    try { await db.execute('PRAGMA foreign_keys = ON'); } catch (_) {}
    try { await db.execute('PRAGMA synchronous = NORMAL'); } catch (_) {}
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        client_message_id TEXT UNIQUE,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        text TEXT,
        is_from_telegram INTEGER NOT NULL DEFAULT 0,
        telegram_message_id INTEGER,
        reply_to_message_id TEXT,
        reply_to_name TEXT,
        reply_to_text TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_edited INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'synced',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        media_type TEXT NOT NULL,
        local_path TEXT,
        r2_key TEXT,
        telegram_file_id TEXT,
        file_name TEXT,
        file_size INTEGER,
        mime_type TEXT,
        duration INTEGER,
        upload_progress REAL NOT NULL DEFAULT 1.0,
        download_progress REAL NOT NULL DEFAULT 1.0,
        is_downloaded INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE reactions (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        user_id TEXT,
        telegram_user_id TEXT,
        emoji TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(message_id, user_id, emoji),
        FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_actions (
        id TEXT PRIMARY KEY,
        action_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_local_msg_created ON messages(created_at DESC)');
    await db.execute('CREATE INDEX idx_local_msg_client_id ON messages(client_message_id)');
    await db.execute('CREATE INDEX idx_local_attach_msg ON attachments(message_id)');
    await db.execute('CREATE INDEX idx_local_react_msg ON reactions(message_id)');
    await db.execute('CREATE INDEX idx_local_pending_created ON pending_actions(created_at ASC)');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
