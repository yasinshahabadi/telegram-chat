import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../config.dart';
import '../domain/models/media_attachment_model.dart';
import 'media_local_storage.dart';

typedef ProgressCallback = void Function(double progress);

/// نتیجه آپلود فایل رسانه‌ای به سرور
class MediaUploadResult {
  final bool isSuccess;
  final String? messageId;
  final String? r2Key;
  final String? mediaUrl;
  final String? error;

  const MediaUploadResult({
    required this.isSuccess,
    this.messageId,
    this.r2Key,
    this.mediaUrl,
    this.error,
  });
}

/// سرویس شبکه مدیریت آپلود، دانلود و استریم فایل‌های چندرسانه‌ای
class MediaRemoteService {
  final http.Client _client;
  final MediaLocalStorage _localStorage;
  final String _baseUrl;

  MediaRemoteService({
    http.Client? client,
    MediaLocalStorage? localStorage,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _localStorage = localStorage ?? MediaLocalStorage(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// دریافت آدرس کامل استریم فایل از R2
  String getMediaStreamUrl(String r2Key) {
    return '$_baseUrl/api/media/file?key=${Uri.encodeComponent(r2Key)}';
  }

  /// آپلود فایل به سرور و باکت R2 همراه با گزارش پیشرفت
  Future<MediaUploadResult> uploadFile({
    required File file,
    required String sessionToken,
    required String mediaType, // 'photo', 'video', 'voice', 'audio', 'document'
    String caption = '',
    Map<String, dynamic>? replyTo,
    ProgressCallback? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/media/upload');

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $sessionToken';

      request.fields['caption'] = caption;
      request.fields['mediaType'] = mediaType;
      if (replyTo != null) {
        request.fields['replyTo'] = jsonEncode(replyTo);
      }

      final fileName = p.basename(file.path);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();

      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: fileName,
      );
      request.files.add(multipartFile);

      onProgress?.call(0.1);

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      onProgress?.call(1.0);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['ok'] == true) {
          return MediaUploadResult(
            isSuccess: true,
            messageId: data['messageId'] as String?,
            r2Key: data['r2Key'] as String?,
            mediaUrl: data['mediaUrl'] as String?,
          );
        }
      }

      final errData = jsonDecode(response.body);
      return MediaUploadResult(
        isSuccess: false,
        error: errData['error']?['message']?.toString() ?? 'خطا در آپلود فایل به سرور',
      );
    } catch (e) {
      return MediaUploadResult(
        isSuccess: false,
        error: 'خطای شبکه در ارسال فایل: $e',
      );
    }
  }

  /// دانلود هوشمند فایل به صورت استریم مستقیم روی دیسک (با بررسی کش و گزارش درصد پیشرفت)
  Future<File?> downloadMedia({
    required MediaAttachmentModel attachment,
    ProgressCallback? onProgress,
  }) async {
    // ۱. بررسی کش محلی (اگر قبلاً دانلود شده باشد، بدون مصرف اینترنت برگردانده می‌شود)
    final cached = await _localStorage.getCachedFile(attachment.fileName);
    if (cached != null) {
      onProgress?.call(1.0);
      return cached;
    }

    final downloadUrl = attachment.getDownloadUrl(_baseUrl);
    if (downloadUrl.isEmpty) return null;

    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        return null;
      }

      final totalBytes = response.contentLength ?? attachment.fileSize ?? 0;
      final targetPath = await _localStorage.getTargetPath(attachment.fileName);
      final tempFile = File('$targetPath.tmp');
      final sink = tempFile.openWrite();

      int receivedBytes = 0;

      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      // تغییر نام فایل موقت به فایل دائمی کش
      final finalFile = await tempFile.rename(targetPath);
      onProgress?.call(1.0);
      return finalFile;
    } catch (e) {
      return null;
    }
  }
}
