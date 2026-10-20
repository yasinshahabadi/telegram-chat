import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// مدیریت کش موقت برنامه و جلوگیری از رشد بی‌رویهٔ آن.
///
/// دو منبع اصلی رشد کش:
///  * `file_picker` هر فایل انتخاب‌شده را در `cache/file_picker/<timestamp>/`
///    کپی می‌کند و هرگز پاک نمی‌کند؛ حتی وقتی کاربر از صفحهٔ پیش‌نمایش
///    برمی‌گردد یا حجم فایل بیش از حد مجاز است.
///  * `photo_manager` فایل اصلی گالری را در `cache/pm_*` کپی می‌کند و
///    بندانگشتی‌ها را با Glide در `cache/image_manager_disk_cache` نگه
///    می‌دارد (Glide به‌تنهایی تا ۲۵۰ مگابایت اجازهٔ رشد دارد).
///
/// فایل‌های دائمی مدیا در پوشهٔ documents برنامه ذخیره می‌شوند و این کلاس
/// هرگز به آن‌ها دست نمی‌زند.
class AppCacheManager {
  AppCacheManager._();

  static final AppCacheManager instance = AppCacheManager._();

  /// سقف کش بندانگشتی‌های گالری. با عبور از این مقدار، کش Glide پاک
  /// می‌شود تا در یک نشست طولانی هم حجم کش کنترل‌شده بماند.
  static const int glideCacheLimitBytes = 48 * 1024 * 1024; // 48 MB

  static const String _pickerCacheDirName = 'file_picker';
  static const String _glideCacheDirName = 'image_manager_disk_cache';
  static const String _scopedOriginalPrefix = 'pm_';

  /// وقتی گالری باز است، پاک‌سازی کش آن را به تعویق می‌اندازیم تا
  /// بندانگشتی‌های در حال نمایش ناگهان خالی نشوند.
  bool galleryVisible = false;

  Directory? _cacheDir;

  Future<Directory> _cacheDirectory() async {
    final cached = _cacheDir;
    if (cached != null && await cached.exists()) return cached;

    final directory = await getTemporaryDirectory();
    _cacheDir = directory;
    return directory;
  }

  /// پاک‌سازی باقی‌ماندهٔ اجرای قبلی برنامه.
  ///
  /// فقط یک‌بار در شروع برنامه (بعد از runApp) صدا زده می‌شود؛ بنابراین
  /// هیچ فایلی از یک انتخاب یا آپلود در حال انجام، در استفاده نیست.
  Future<void> cleanupOnStartup() async {
    try {
      await clearPickedFileCache();
      await clearScopedOriginals();
      await trimGalleryCache();
    } catch (e) {
      debugPrint('[AppCache] startup cleanup failed: $e');
    }
  }

  /// حذف همهٔ کپی‌های باقی‌ماندهٔ `file_picker`.
  Future<void> clearPickedFileCache() async {
    try {
      final cache = await _cacheDirectory();
      final directory = Directory(p.join(cache.path, _pickerCacheDirName));
      if (!await directory.exists()) return;

      await for (final entry in directory.list(followLinks: false)) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AppCache] clear picker cache failed: $e');
    }
  }

  /// حذف کپی‌های موقت یک جلسهٔ انتخاب فایل.
  ///
  /// فقط فایل‌هایی که داخل `cache/file_picker` هستند حذف می‌شوند؛ فایل‌های
  /// دائمی (مثل کپی ذخیره‌شده برای retry) دست‌نخورده می‌مانند.
  Future<void> releasePickedFiles(Iterable<String> paths) async {
    try {
      final cache = await _cacheDirectory();
      final pickerRoot = p.normalize(
        p.join(cache.path, _pickerCacheDirName),
      );
      final parentDirectories = <String>{};

      for (final path in paths) {
        final normalized = p.normalize(path);
        if (!p.isWithin(pickerRoot, normalized)) continue;

        try {
          final file = File(normalized);
          if (await file.exists()) await file.delete();
        } catch (_) {}

        parentDirectories.add(p.dirname(normalized));
      }

      // هر جلسهٔ انتخاب در یک پوشهٔ timestamp قرار می‌گیرد؛ اگر خالی شد،
      // خود پوشه را هم حذف می‌کنیم.
      for (final parent in parentDirectories) {
        if (!p.isWithin(pickerRoot, parent)) continue;
        try {
          final directory = Directory(parent);
          if (await directory.exists() &&
              await directory.list(followLinks: false).isEmpty) {
            await directory.delete();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AppCache] release picked files failed: $e');
    }
  }

  /// پاک‌سازی کش گالری پس از پایان کار با آن (یا در شروع برنامه).
  ///
  /// کپی‌های اصلی `photo_manager` همیشه حذف می‌شوند؛ کش بندانگشتی Glide
  /// فقط وقتی از سقف تعیین‌شده عبور کند پاک می‌شود تا باز شدن‌های بعدی
  /// گالری همچنان روان باشد.
  Future<void> trimGalleryCache() async {
    if (galleryVisible) return;

    try {
      await clearScopedOriginals();

      final cache = await _cacheDirectory();
      final glide = Directory(p.join(cache.path, _glideCacheDirName));
      if (await _directorySize(glide) > glideCacheLimitBytes) {
        // روش رسمی خود photo_manager؛ هم کش Glide و هم فایل‌های pm_ را
        // پاک می‌کند. در این لحظه هیچ آپلودی از گالری در جریان نیست.
        await PhotoManager.clearFileCache();
      }
    } catch (e) {
      debugPrint('[AppCache] trim gallery cache failed: $e');
    }
  }

  /// حذف کپی فایل‌های اصلی گالری در ریشهٔ کش (`pm_<id>_o_<name>`).
  ///
  /// بندانگشتی‌های Glide در این متد دست‌نخورده می‌مانند.
  Future<void> clearScopedOriginals() async {
    try {
      final cache = await _cacheDirectory();
      await for (final entry in cache.list(followLinks: false)) {
        if (entry is! File) continue;
        if (!p.basename(entry.path).startsWith(_scopedOriginalPrefix)) continue;
        try {
          await entry.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AppCache] clear scoped originals failed: $e');
    }
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;

    int total = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {}
      }
    } catch (_) {}
    return total;
  }
}
