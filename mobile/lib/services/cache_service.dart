// lib/services/cache_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/chat_message.dart';

class CacheService {
  static const String _cachedMessagesKey = 'local_cached_messages_v1';
  static const String _avatarCheckPrefix = 'avatar_last_check_';
  // بررسی آواتار حداکثر هر ۶ ساعت یک‌بار
  static const int _avatarTtlMillis = 6 * 60 * 60 * 1000;
  // حذف پیام‌ها و مدیای قدیمی‌تر از ۲۴ ساعت مطابق کلودفلر
  static const int _retentionMillis = 24 * 60 * 60 * 1000;

  // ۱. دریافت پیام‌های ذخیره‌شده جهت لود در ۰ ثانیه
  static Future<List<ChatMessage>> getCachedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cachedMessagesKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List decoded = jsonDecode(jsonStr);
      final now = DateTime.now().millisecondsSinceEpoch;
      final threshold = now - _retentionMillis;

      // فیلتر کردن پیام‌های زیر ۲۴ ساعت
      final validMessages = decoded
          .map((item) => ChatMessage.fromJson(item))
          .where((m) => m.timestamp >= threshold)
          .toList();

      return validMessages;
    } catch (_) {
      return [];
    }
  }

  // ۲. ذخیره پیام‌ها در حافظه پایدار محلی
  static Future<void> saveMessages(List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final threshold = now - _retentionMillis;

      final toCache = messages.where((m) => m.timestamp >= threshold).map((m) {
        return {
          'id': m.id,
          'sender_id': m.senderId,
          'sender_name': m.senderName,
          'text': m.text,
          'is_from_telegram': m.isFromTelegram ? 1 : 0,
          'timestamp': m.timestamp,
          'reply_to_name': m.replyToName,
          'reply_to_text': m.replyToText,
          'reply_to_id': m.replyToId,
          'tg_msg_id': m.tgMsgId,
          'is_read': m.isRead,
          'read_at': m.readAt,
          'is_edited': m.isEdited ? 1 : 0,
          'media_type': m.mediaType,
          'media_file_id': m.mediaFileId,
          'media_file_name': m.mediaFileName,
          'media_file_size': m.mediaFileSize,
          'media_thumb_id': m.mediaThumbId,
          'media_duration': m.mediaDuration,
          'reactions': jsonEncode(m.reactions),
          'forward_from_name': m.forwardFromName,
          'forward_channel_username': m.forwardChannelUsername,
          'forward_post_id': m.forwardPostId,
          'forward_chat_id': m.forwardChatId,
          'media_group_id': m.mediaGroupId,
        };
      }).toList();

      await prefs.setString(_cachedMessagesKey, jsonEncode(toCache));
    } catch (_) {}
  }

  // ۳. پوشه اختصاصی کش رسانه‌ها (عکس، ویدیو، ویس، فایل)
  static Future<Directory> getMediaCacheDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/chat_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ۴. پوشه اختصاصی آواتارها
  static Future<Directory> getAvatarCacheDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/avatars');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ۵. متد هوشمند دریافت و نوسازی آواتار تلگرام (با فاصله حداقل ۶ ساعت)
  static Future<String?> getOrFetchAvatar(String? userId) async {
    if (userId == null || userId.isEmpty) return null;

    try {
      final avatarDir = await getAvatarCacheDir();
      final avatarFile = File('${avatarDir.path}/avatar_$userId.jpg');
      final prefs = await SharedPreferences.getInstance();

      final lastCheck = prefs.getInt('$_avatarCheckPrefix$userId') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      final bool fileExists = await avatarFile.exists();

      // اگر فایل وجود دارد و هنوز ۶ ساعت نگذشته، فوراً از کش برگردان (بدون مصرف اینترنت)
      if (fileExists && (now - lastCheck < _avatarTtlMillis)) {
        return avatarFile.path;
      }

      // اگر فایل نیست یا ۶ ساعت گذشته، در پس‌زمینه بررسی و دانلود کن
      final res = await http.get(Uri.parse("${AppConfig.baseUrl}/api/avatar?userId=$userId"));
      await prefs.setInt('$_avatarCheckPrefix$userId', now);

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await avatarFile.writeAsBytes(res.bodyBytes);
        return avatarFile.path;
      }

      if (fileExists) return avatarFile.path;
    } catch (_) {}
    return null;
  }

  // ۶. ذخیره فایل مدیا در کش محلی
  static Future<String?> saveMediaToCache(String fileId, List<int> bytes, String extension) async {
    try {
      final mediaDir = await getMediaCacheDir();
      final file = File('${mediaDir.path}/media_${fileId.replaceAll("-", "")}.$extension');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // ۷. بررسی وجود فایل مدیا در کش
  static Future<String?> getCachedMediaPath(String fileId, String extension) async {
    try {
      final mediaDir = await getMediaCacheDir();
      final file = File('${mediaDir.path}/media_${fileId.replaceAll("-", "")}.$extension');
      if (await file.exists()) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  // ۸. پاکسازی خودکار کش‌های قدیمی‌تر از ۲۴ ساعت (همگام با سرور کلودفلر)
  static Future<void> pruneOldCache() async {
    try {
      final mediaDir = await getMediaCacheDir();
      final now = DateTime.now();

      if (await mediaDir.exists()) {
        await for (var entity in mediaDir.list()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (now.difference(stat.modified).inMilliseconds > _retentionMillis) {
              await entity.delete();
            }
          }
        }
      }
    } catch (_) {}
  }

  // ۹. محاسبه دقیق حجم کش برای صفحه تنظیمات
  static Future<Map<String, int>> getCacheBreakdown() async {
    int photoSize = 0;
    int videoSize = 0;
    int audioSize = 0;
    int docSize = 0;
    int avatarSize = 0;

    try {
      final mediaDir = await getMediaCacheDir();
      if (await mediaDir.exists()) {
        await for (var entity in mediaDir.list()) {
          if (entity is File) {
            final len = await entity.length();
            final path = entity.path.toLowerCase();
            if (path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.webp')) {
              photoSize += len;
            } else if (path.endsWith('.mp4') || path.endsWith('.mov')) {
              videoSize += len;
            } else if (path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.ogg')) {
              audioSize += len;
            } else {
              docSize += len;
            }
          }
        }
      }

      final avatarDir = await getAvatarCacheDir();
      if (await avatarDir.exists()) {
        await for (var entity in avatarDir.list()) {
          if (entity is File) {
            avatarSize += await entity.length();
          }
        }
      }
    } catch (_) {}

    final total = photoSize + videoSize + audioSize + docSize + avatarSize;
    return {
      'photos': photoSize,
      'videos': videoSize,
      'audios': audioSize,
      'documents': docSize,
      'avatars': avatarSize,
      'total': total,
    };
  }

  // ۱۰. پاکسازی کامل تمام فایل‌های کش
  static Future<void> clearAllCache() async {
    try {
      final mediaDir = await getMediaCacheDir();
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }

      final avatarDir = await getAvatarCacheDir();
      if (await avatarDir.exists()) {
        await avatarDir.delete(recursive: true);
      }

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (var entity in tempDir.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}