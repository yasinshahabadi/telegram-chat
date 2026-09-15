import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// سرویس مدیریت کش محلی فایل‌های چندرسانه‌ای روی حافظه گوشی اندروید
class MediaLocalStorage {
  static Directory? _mediaDir;

  /// دریافت یا ایجاد دایرکتوری اختصاصی کش فایل‌های تلگرام
  Future<Directory> get mediaDirectory async {
    if (_mediaDir != null && await _mediaDir!.exists()) {
      return _mediaDir!;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'telegram_media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _mediaDir = dir;
    return dir;
  }

  /// بررسی وجود فایل در کش محلی (جلوگیری قطعی از دانلود مجدد از اینترنت)
  Future<File?> getCachedFile(String fileName) async {
    try {
      final dir = await mediaDirectory;
      final file = File(p.join(dir.path, fileName));
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// تولید مسیر مقصد استاندارد برای ذخیره یک فایل
  Future<String> getTargetPath(String fileName) async {
    final dir = await mediaDirectory;
    return p.join(dir.path, fileName);
  }

  /// ذخیره مستقیم بایت‌های دانلودشده روی حافظه گوشی
  Future<File> saveBytes(String fileName, List<int> bytes) async {
    final targetPath = await getTargetPath(fileName);
    final file = File(targetPath);
    return await file.writeAsBytes(bytes, flush: true);
  }

  /// حذف فایل از حافظه محلی
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
}
