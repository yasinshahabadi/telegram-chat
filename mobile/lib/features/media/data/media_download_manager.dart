import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import 'media_remote_service.dart';
import 'media_local_storage.dart';

/// مدیر دانلود و کش مدیا - هماهنگی بین UI، سرور و حافظه محلی
class MediaDownloadManager extends ChangeNotifier {
  static final MediaDownloadManager instance = MediaDownloadManager._();
  MediaDownloadManager._();

  final MediaLocalStorage _storage = MediaLocalStorage();
  final MediaRemoteService _remote = MediaRemoteService();
  final LocalChatDao _dao = LocalChatDao();

  final Map<String, double> _progress = {};
  final Map<String, Future<File?>> _active = {};

  double? progressFor(String messageId) => _progress[messageId];
  bool isDownloading(String messageId) => _active.containsKey(messageId);

  /// دانلود فایل + ذخیره در حافظه محلی + به‌روزرسانی DB
  Future<File?> downloadAndCache({
    required String messageId,
    required MediaAttachmentModel attachment,
  }) async {
    // ۱. اگر فایل در حافظه هست، برگردان
    final cached = await _storage.getCachedFile(attachment.fileName);
    if (cached != null) return cached;

    // ۲. اگر در حال دانلود است، به همان وصل شو
    if (_active.containsKey(messageId)) {
      return _active[messageId];
    }

    _progress[messageId] = 0.0;
    notifyListeners();

    final future = _performDownload(messageId, attachment);
    _active[messageId] = future;

    try {
      return await future;
    } finally {
      _active.remove(messageId);
      _progress.remove(messageId);
      notifyListeners();
    }
  }

  Future<File?> _performDownload(String messageId, MediaAttachmentModel attachment) async {
    try {
      final file = await _remote.downloadMedia(
        attachment: attachment,
        onProgress: (p) {
          _progress[messageId] = p;
          notifyListeners();
        },
      );

      if (file != null) {
        try {
          await _dao.updateAttachmentLocalPath(attachment.id, file.path);
        } catch (_) {}
        notifyListeners();
      }

      return file;
    } catch (e) {
      debugPrint('[MediaDownload] Failed: $e');
      return null;
    }
  }

  /// کش فایل ارسالی (سمت فرستنده) - کپی از temp به telegram_media
  Future<File?> cacheUploadedFile({
    required String attachmentId,
    required String sourcePath,
    required String fileName,
  }) async {
    try {
      final saved = await _storage.saveFileFromPath(sourcePath, fileName);
      if (saved != null) {
        try {
          await _dao.updateAttachmentLocalPath(attachmentId, saved.path);
        } catch (_) {}
        notifyListeners();
      }
      return saved;
    } catch (e) {
      debugPrint('[MediaDownload] Cache upload failed: $e');
      return null;
    }
  }

  /// پاک‌سازی یک فایل خاص (اختیاری)
  Future<void> deleteLocalFile(String localPath) async {
    await _storage.deleteLocalFile(localPath);
    notifyListeners();
  }

  MediaLocalStorage get storage => _storage;
}