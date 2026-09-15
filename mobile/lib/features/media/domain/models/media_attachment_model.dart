/// مدل داده‌ای پیوست‌های چندرسانه‌ای پیام (عکس، ویدیو، ویس، صوت و سند)
class MediaAttachmentModel {
  final String id;
  final String messageId;
  final String mediaType; // 'photo', 'video', 'voice', 'audio', 'document'
  final String? localPath;
  final String? r2Key;
  final String? telegramFileId;
  final String fileName;
  final int? fileSize;
  final String? mimeType;
  final int duration;
  final double uploadProgress;
  final double downloadProgress;
  final bool isDownloaded;
  final int createdAt;

  const MediaAttachmentModel({
    required this.id,
    required this.messageId,
    required this.mediaType,
    this.localPath,
    this.r2Key,
    this.telegramFileId,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.duration = 0,
    this.uploadProgress = 1.0,
    this.downloadProgress = 1.0,
    this.isDownloaded = false,
    required this.createdAt,
  });

  /// تبدیل از رکورد دیتابیس محلی SQLite
  factory MediaAttachmentModel.fromDbMap(Map<String, dynamic> map) {
    return MediaAttachmentModel(
      id: map['id'] as String? ?? '',
      messageId: map['message_id'] as String? ?? '',
      mediaType: map['media_type'] as String? ?? 'document',
      localPath: map['local_path'] as String?,
      r2Key: map['r2_key'] as String?,
      telegramFileId: map['telegram_file_id'] as String?,
      fileName: map['file_name'] as String? ?? 'file',
      fileSize: map['file_size'] as int?,
      mimeType: map['mime_type'] as String?,
      duration: map['duration'] as int? ?? 0,
      uploadProgress: (map['upload_progress'] as num? ?? 1.0).toDouble(),
      downloadProgress: (map['download_progress'] as num? ?? 1.0).toDouble(),
      isDownloaded: (map['is_downloaded'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// تبدیل به نقشه جهت ذخیره در دیتابیس محلی SQLite
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'message_id': messageId,
      'media_type': mediaType,
      'local_path': localPath,
      'r2_key': r2Key,
      'telegram_file_id': telegramFileId,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'duration': duration,
      'upload_progress': uploadProgress,
      'download_progress': downloadProgress,
      'is_downloaded': isDownloaded ? 1 : 0,
      'created_at': createdAt,
    };
  }

  /// تبدیل از داده‌های دریافتی از سرور یا وب‌سوکت
  factory MediaAttachmentModel.fromJson(Map<String, dynamic> json) {
    return MediaAttachmentModel(
      id: json['id'] as String? ?? '',
      messageId: json['messageId'] as String? ?? json['message_id'] as String? ?? '',
      mediaType: json['mediaType'] as String? ?? json['media_type'] as String? ?? 'document',
      localPath: json['localPath'] as String?,
      r2Key: json['r2Key'] as String? ?? json['r2_key'] as String?,
      telegramFileId: json['telegramFileId'] as String? ?? json['telegram_file_id'] as String?,
      fileName: json['fileName'] as String? ?? json['file_name'] as String? ?? 'file',
      fileSize: json['fileSize'] as int? ?? json['file_size'] as int?,
      mimeType: json['mimeType'] as String? ?? json['mime_type'] as String?,
      duration: json['duration'] as int? ?? 0,
      uploadProgress: 1.0,
      downloadProgress: 1.0,
      isDownloaded: false,
      createdAt: json['createdAt'] as int? ?? json['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  MediaAttachmentModel copyWith({
    String? id,
    String? messageId,
    String? mediaType,
    String? localPath,
    String? r2Key,
    String? telegramFileId,
    String? fileName,
    int? fileSize,
    String? mimeType,
    int? duration,
    double? uploadProgress,
    double? downloadProgress,
    bool? isDownloaded,
    int? createdAt,
  }) {
    return MediaAttachmentModel(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      mediaType: mediaType ?? this.mediaType,
      localPath: localPath ?? this.localPath,
      r2Key: r2Key ?? this.r2Key,
      telegramFileId: telegramFileId ?? this.telegramFileId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      duration: duration ?? this.duration,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// دریافت آدرس اینترنتی استریم یا دانلود فایل
  String getDownloadUrl(String baseUrl) {
    if (r2Key != null && r2Key!.isNotEmpty) {
      return '$baseUrl/api/media/file?key=${Uri.encodeComponent(r2Key!)}';
    }
    if (telegramFileId != null && telegramFileId!.isNotEmpty) {
      return '$baseUrl/api/media/file?fileId=${Uri.encodeComponent(telegramFileId!)}';
    }
    return '';
  }

  bool get isPhoto => mediaType == 'photo' || mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isVoice => mediaType == 'voice';
  bool get isAudio => mediaType == 'audio';
  bool get isDocument => !isPhoto && !isVideo && !isVoice && !isAudio;

  /// قالب‌بندی حجم فایل به کیلوبایت یا مگابایت
  String get formattedSize {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// قالب‌بندی مدت زمان صوت یا ویدیو به دقیقه و ثانیه (مثلاً 01:25)
  String get formattedDuration {
    final minutes = (duration ~/ 60).toString().padLeft(2, '0');
    final seconds = (duration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
