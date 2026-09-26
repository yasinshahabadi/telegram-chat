import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'media_remote_service.dart';
import 'media_local_storage.dart';

/// مدیر دانلود و کش مدیا — کلیدگذاری بر اساس `attachment.id`.
class MediaDownloadManager extends ChangeNotifier {
  static final MediaDownloadManager instance = MediaDownloadManager._();
  MediaDownloadManager._();

  final MediaLocalStorage _storage = MediaLocalStorage();
  final MediaRemoteService _remote = MediaRemoteService();
  final LocalChatDao _dao = LocalChatDao();

  /// callback: (attachmentId, messageId, localPath)
  void Function(String attachmentId, String messageId, String localPath)?
      onDownloadCompleted;

  final Map<String, double> _progress = {};
  final Map<String, Future<File?>> _active = {};

  double? progressFor(String attachmentId) => _progress[attachmentId];
  bool isDownloading(String attachmentId) => _active.containsKey(attachmentId);

  /// بررسی بدون دانلود: آیا فایل قبلاً روی دستگاه هست؟
  Future<File?> resolveLocalFile(MediaAttachmentModel attachment) async {
    final explicit = await _storage.resolveExisting(attachment.localPath);
    if (explicit != null) return explicit;
    return await _storage.getCachedFileForAttachment(attachment.id, attachment.fileName);
  }

  /// دانلود + ذخیره در کش + به‌روزرسانی DB.
  Future<File?> downloadAndCache(MediaAttachmentModel attachment) async {
    // 1) قبلاً روی دستگاه هست؟ — مسیر را در DB تضمین کن.
    final existing = await resolveLocalFile(attachment);
    if (existing != null) {
      try { await _dao.updateAttachmentLocalPath(attachment.id, existing.path); } catch (_) {}
      return existing;
    }

    // 2) همان فایل در حال دانلود است؟ به همان وصل شو.
    if (_active.containsKey(attachment.id)) {
      return _active[attachment.id];
    }

    _progress[attachment.id] = 0.0;
    notifyListeners();

    final future = _performDownload(attachment);
    _active[attachment.id] = future;

    try {
      final file = await future;
      if (file != null) {
        try { await _dao.updateAttachmentLocalPath(attachment.id, file.path); } catch (_) {}
        onDownloadCompleted?.call(attachment.id, attachment.messageId, file.path);
      }
      return file;
    } finally {
      _active.remove(attachment.id);
      _progress.remove(attachment.id);
      notifyListeners();
    }
  }

  Future<File?> _performDownload(MediaAttachmentModel attachment) async {
    try {
      final targetPath = await _storage.getTargetPathForAttachment(
        attachment.id, attachment.fileName,
      );
      return await _remote.downloadToFile(
        attachment: attachment,
        targetPath: targetPath,
        onProgress: (p) {
          _progress[attachment.id] = p;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[MediaDownload] Failed: $e');
      return null;
    }
  }

  /// کش کردن فایل آپلودی (پس از آپلود موفق، تا فایل با attachmentId سرور ذخیره شود).
  Future<File?> cacheUploadedFile({
    required String attachmentId,
    required String sourcePath,
    required String originalFileName,
  }) async {
    try {
      final saved = await _storage.saveFileFromPathForAttachment(
        sourcePath, attachmentId, originalFileName,
      );
      if (saved != null) {
        try { await _dao.updateAttachmentLocalPath(attachmentId, saved.path); } catch (_) {}
        notifyListeners();
      }
      return saved;
    } catch (e) {
      debugPrint('[MediaDownload] Cache upload failed: $e');
      return null;
    }
  }

  Future<void> deleteLocalFile(String localPath) async {
    await _storage.deleteLocalFile(localPath);
    notifyListeners();
  }

  MediaLocalStorage get storage => _storage;
}