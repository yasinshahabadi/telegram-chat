import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

/// یک آیتم انتخاب‌شده برای ارسال (از گالری، فایل یا موزیک).
///
/// اگر آیتم از گالری آمده باشد، [asset] نگه داشته می‌شود تا فایل اصلی
/// فقط در لحظهٔ ارسال resolve شود. این کار از ساخت زودهنگام فایل‌های
/// موقت و مصرف حافظه جلوگیری می‌کند.
class PickedMedia {
  final AssetEntity? asset;
  final File? sourceFile;
  final String fileName;
  final String mediaType; // photo | video | audio | document
  final int duration;

  const PickedMedia({
    this.asset,
    this.sourceFile,
    required this.fileName,
    required this.mediaType,
    this.duration = 0,
  }) : assert(asset != null || sourceFile != null);

  factory PickedMedia.fromAsset(AssetEntity asset) {
    return PickedMedia(
      asset: asset,
      fileName: asset.title ?? 'IMG_${asset.id}',
      mediaType: asset.type == AssetType.video ? 'video' : 'photo',
      duration: asset.duration,
    );
  }

  factory PickedMedia.fromFile(
    File file, {
    required String mediaType,
    String? fileName,
    int duration = 0,
  }) {
    return PickedMedia(
      sourceFile: file,
      fileName: fileName ?? file.uri.pathSegments.last,
      mediaType: mediaType,
      duration: duration,
    );
  }

  bool get isFromGallery => asset != null;
  bool get isPhoto => mediaType == 'photo';
  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';

  /// فایل نهایی برای آپلود؛ برای آیتم‌های گالری در زمان نیاز resolve می‌شود.
  Future<File?> resolveFile() async {
    if (sourceFile != null) return sourceFile;
    try {
      return await asset?.originFile;
    } catch (_) {
      return null;
    }
  }

  /// نام فایل نهایی؛ اگر عنوان گالری بدون پسوند بود از نام فایل اصلی
  /// استفاده می‌کنیم تا نوع رسانه در سرور/تلگرام درست تشخیص داده شود.
  Future<String> resolveFileName() async {
    if (sourceFile != null) {
      return sourceFile!.uri.pathSegments.last;
    }
    if (_hasExtension(fileName)) return fileName;
    final file = await resolveFile();
    if (file != null) return file.uri.pathSegments.last;
    return fileName;
  }

  static bool _hasExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1;
  }
}
