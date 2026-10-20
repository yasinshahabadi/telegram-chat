/// محدودیت‌های مشترک انتخاب و آپلود رسانه.
///
/// این مقادیر باید با `MAX_FILES_PER_MESSAGE` و `MAX_FILE_SIZE` در
/// `src/media/mediaController.js` هم‌راستا بمانند.
class MediaUploadLimits {
  const MediaUploadLimits._();

  static const int maxFiles = 10;
  static const int maxTotalBytes = 20 * 1024 * 1024;

  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
  };

  static const Set<String> videoExtensions = {
    'mp4',
    'mov',
    'mkv',
    'avi',
    '3gp',
    'webm',
    'm4v',
  };

  static const Set<String> audioExtensions = {
    'mp3',
    'm4a',
    'wav',
    'ogg',
    'aac',
    'opus',
  };

  static String mediaTypeForFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'document';
    final ext = name.substring(dot + 1).toLowerCase();
    if (imageExtensions.contains(ext)) return 'photo';
    if (videoExtensions.contains(ext)) return 'video';
    if (audioExtensions.contains(ext)) return 'audio';
    return 'document';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes بایت';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} کیلوبایت';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
  }
}
