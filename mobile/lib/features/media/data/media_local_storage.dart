import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// مدیریت حافظه محلی مدیا با محدودیت ۲۰۰ مگابایت و LRU
class MediaLocalStorage {
  static const int maxCacheBytes = 200 * 1024 * 1024; // 200 MB
  static Directory? _mediaDir;

  MediaLocalStorage();

  /// پوشه اصلی ذخیره مدیا
  Future<Directory> get mediaDirectory async {
    if (_mediaDir != null && await _mediaDir!.exists()) return _mediaDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'telegram_media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _mediaDir = dir;
    return dir;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  }

  /// بررسی وجود فایل در کش (با بروزرسانی زمان دسترسی برای LRU)
  Future<File?> getCachedFile(String fileName) async {
    try {
      final dir = await mediaDirectory;
      final file = File(p.join(dir.path, _sanitizeFileName(fileName)));
      if (await file.exists() && await file.length() > 0) {
        try { await file.setLastModified(DateTime.now()); } catch (_) {}
        return file;
      }
    } catch (_) {}
    return null;
  }

  Future<String> getTargetPath(String fileName) async {
    final dir = await mediaDirectory;
    return p.join(dir.path, _sanitizeFileName(fileName));
  }

  /// کپی فایل از مسیر موقت به حافظه دائمی
  Future<File?> saveFileFromPath(String sourcePath, String fileName) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final targetPath = await getTargetPath(fileName);
      final target = await source.copy(targetPath);
      await enforceLimit();
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<File> saveBytes(String fileName, List<int> bytes) async {
    final targetPath = await getTargetPath(fileName);
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    await enforceLimit();
    return file;
  }

  Future<bool> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// محاسبه حجم کل پوشه
  Future<int> getTotalSize() async {
    try {
      final dir = await mediaDirectory;
      int total = 0;
      await for (final f in dir.list(recursive: false)) {
        if (f is File && !f.path.endsWith('.tmp')) {
          try { total += await f.length(); } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// اعمال محدودیت ۲۰۰ MB با حذف قدیمی‌ترین فایل‌ها (LRU)
  Future<int> enforceLimit() async {
    try {
      final dir = await mediaDirectory;
      final entries = <MapEntry<File, int>>[];
      int total = 0;

      await for (final f in dir.list(recursive: false)) {
        if (f is File && !f.path.endsWith('.tmp')) {
          try {
            final stat = await f.stat();
            total += stat.size;
            entries.add(MapEntry(f, stat.modified.millisecondsSinceEpoch));
          } catch (_) {}
        }
      }

      if (total <= maxCacheBytes) return 0;

      // قدیمی‌ترین اول
      entries.sort((a, b) => a.value.compareTo(b.value));

      int freed = 0;
      int remaining = total;
      final targetSize = (maxCacheBytes * 0.9).toInt(); // حذف تا ۹۰٪

      for (final entry in entries) {
        if (remaining <= targetSize) break;
        try {
          final size = await entry.key.length();
          await entry.key.delete();
          freed += size;
          remaining -= size;
        } catch (_) {}
      }

      return freed;
    } catch (_) {
      return 0;
    }
  }

  /// پاک‌سازی کامل
  Future<void> clearAll() async {
    try {
      final dir = await mediaDirectory;
      await for (final f in dir.list(recursive: false)) {
        try { if (f is File) await f.delete(); } catch (_) {}
      }
    } catch (_) {}
  }

  /// حذف فایل‌های یک دسته خاص
  Future<int> clearByCategory(String category) async {
    try {
      final dir = await mediaDirectory;
      int freed = 0;
      final imageExts = ['jpg','jpeg','png','webp','gif','bmp','heic','heif'];
      final videoExts = ['mp4','mov','mkv','avi','webm','3gp','m4v'];
      final voiceExts = ['m4a','ogg','opus'];
      final audioExts = ['mp3','wav','aac'];

      await for (final f in dir.list(recursive: false)) {
        if (f is File) {
          final ext = f.path.split('.').last.toLowerCase();
          bool shouldDelete = false;

          switch (category) {
            case 'photo': shouldDelete = imageExts.contains(ext); break;
            case 'video': shouldDelete = videoExts.contains(ext); break;
            case 'voice': shouldDelete = voiceExts.contains(ext); break;
            case 'audio': shouldDelete = audioExts.contains(ext); break;
            case 'document':
              shouldDelete = !imageExts.contains(ext) &&
                  !videoExts.contains(ext) &&
                  !voiceExts.contains(ext) &&
                  !audioExts.contains(ext);
              break;
          }

          if (shouldDelete) {
            try {
              final size = await f.length();
              await f.delete();
              freed += size;
            } catch (_) {}
          }
        }
      }
      return freed;
    } catch (_) {
      return 0;
    }
  }

  /// حجم مصرفی به تفکیک نوع
  Future<Map<String, int>> getSizeByCategory() async {
    final result = <String, int>{
      'photo': 0, 'video': 0, 'voice': 0, 'audio': 0, 'document': 0,
    };
    try {
      final dir = await mediaDirectory;
      final imageExts = ['jpg','jpeg','png','webp','gif','bmp','heic','heif'];
      final videoExts = ['mp4','mov','mkv','avi','webm','3gp','m4v'];
      final voiceExts = ['m4a','ogg','opus'];
      final audioExts = ['mp3','wav','aac'];

      await for (final f in dir.list(recursive: false)) {
        if (f is File) {
          try {
            final size = await f.length();
            final ext = f.path.split('.').last.toLowerCase();
            if (imageExts.contains(ext)) {
              result['photo'] = result['photo']! + size;
            } else if (videoExts.contains(ext)) {
              result['video'] = result['video']! + size;
            } else if (voiceExts.contains(ext)) {
              result['voice'] = result['voice']! + size;
            } else if (audioExts.contains(ext)) {
              result['audio'] = result['audio']! + size;
            } else {
              result['document'] = result['document']! + size;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return result;
  }

  Future<int> getFileCount() async {
    try {
      final dir = await mediaDirectory;
      int count = 0;
      await for (final f in dir.list(recursive: false)) {
        if (f is File && !f.path.endsWith('.tmp')) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}