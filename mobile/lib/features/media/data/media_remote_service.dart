import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';   // ✅ برای MediaType
import 'package:path/path.dart' as p;
import '../../../config.dart';
import '../domain/models/media_attachment_model.dart';
import 'media_local_storage.dart';

typedef ProgressCallback = void Function(double progress);

class MediaUploadResult {
  final bool isSuccess;
  final String? messageId;
  final String? fileId;
  final String? r2Key;
  final String? mediaUrl;
  final String? error;

  const MediaUploadResult({
    required this.isSuccess,
    this.messageId,
    this.fileId,
    this.r2Key,
    this.mediaUrl,
    this.error,
  });
}

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

  String getMediaStreamUrl(String fileId) {
    return '$_baseUrl/api/media/file?fileId=${Uri.encodeComponent(fileId)}';
  }

  /// ✅ حدس MIME type از پسوند فایل
  static String _guessMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      case 'bmp': return 'image/bmp';
      case 'heic': return 'image/heic';
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      case 'avi': return 'video/x-msvideo';
      case '3gp': return 'video/3gpp';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'wav': return 'audio/wav';
      case 'ogg': return 'audio/ogg';
      case 'aac': return 'audio/aac';
      case 'opus': return 'audio/opus';
      case 'pdf': return 'application/pdf';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  Future<MediaUploadResult> uploadFile({
    required File file,
    required String sessionToken,
    required String mediaType,
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

      // ✅ ارسال MIME type صحیح
      final mimeString = _guessMimeType(fileName);
      final mimeParts = mimeString.split('/');

      final multipartFile = http.MultipartFile(
        'file',
        stream,
        length,
        filename: fileName,
        contentType: MediaType(mimeParts[0], mimeParts[1]),   // ✅ این خط کلید حل مشکل است
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
            fileId: data['fileId'] as String?,
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

  Future<File?> downloadMedia({
    required MediaAttachmentModel attachment,
    ProgressCallback? onProgress,
  }) async {
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

      if (response.statusCode != 200 && response.statusCode != 206) return null;

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

      final finalFile = await tempFile.rename(targetPath);
      onProgress?.call(1.0);
      return finalFile;
    } catch (e) {
      return null;
    }
  }
}