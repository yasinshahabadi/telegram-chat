import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../config.dart';
import '../domain/models/media_attachment_model.dart';

typedef ProgressCallback = void Function(double progress);

class MediaUploadResult {
  final bool isSuccess;
  final String? messageId;
  final String? clientMessageId;
  final List<MediaAttachmentModel> attachments;
  final String? error;

  const MediaUploadResult({
    required this.isSuccess,
    this.messageId,
    this.clientMessageId,
    this.attachments = const [],
    this.error,
  });
}

class MediaRemoteService {
  final http.Client _client;
  final String _baseUrl;

  MediaRemoteService({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.baseUrl;

  String getMediaStreamUrl(String fileId) {
    return '$_baseUrl/api/media/file?fileId=${Uri.encodeComponent(fileId)}';
  }

  static String _guessMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'webp': return 'image/webp';
      case 'gif':  return 'image/gif';
      case 'bmp':  return 'image/bmp';
      case 'heic': return 'image/heic';
      case 'mp4':  return 'video/mp4';
      case 'mov':  return 'video/quicktime';
      case 'mkv':  return 'video/x-matroska';
      case 'webm': return 'video/webm';
      case 'avi':  return 'video/x-msvideo';
      case '3gp':  return 'video/3gpp';
      case 'mp3':  return 'audio/mpeg';
      case 'm4a':  return 'audio/mp4';
      case 'wav':  return 'audio/wav';
      case 'ogg':  return 'audio/ogg';
      case 'aac':  return 'audio/aac';
      case 'opus': return 'audio/opus';
      case 'pdf':  return 'application/pdf';
      case 'zip':  return 'application/zip';
      default:     return 'application/octet-stream';
    }
  }

  Stream<List<int>> _progressTrackingStream(
    Stream<List<int>> source,
    void Function(int chunkSize) onChunk,
  ) async* {
    await for (final chunk in source) {
      onChunk(chunk.length);
      yield chunk;
    }
  }

  Future<MediaUploadResult> uploadFiles({
    required List<File> files,
    required List<String> mediaTypes,
    required List<String> originalNames,
    required String sessionToken,
    String caption = '',
    Map<String, dynamic>? replyTo,
    String? clientMessageId,
    ProgressCallback? onProgress,
  }) async {
    if (files.isEmpty) {
      return const MediaUploadResult(isSuccess: false, error: 'هیچ فایلی انتخاب نشده است.');
    }

    final uri = Uri.parse('$_baseUrl/api/media/upload');

    try {
      final sizes = <int>[];
      for (final f in files) {
        sizes.add(await f.length());
      }
      final totalBytes = sizes.fold<int>(0, (a, b) => a + b);
      final sentBytes = List<int>.filled(files.length, 0);

      void reportProgress() {
        if (onProgress == null || totalBytes <= 0) return;
        final sum = sentBytes.fold<int>(0, (a, b) => a + b);
        onProgress((sum / totalBytes).clamp(0.0, 1.0));
      }

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $sessionToken';

      if (caption.isNotEmpty) request.fields['caption'] = caption;
      if (clientMessageId != null) request.fields['clientMessageId'] = clientMessageId;
      if (replyTo != null) request.fields['replyTo'] = jsonEncode(replyTo);

      final meta = <Map<String, String>>[];
      for (int i = 0; i < files.length; i++) {
        meta.add({
          'mediaType': mediaTypes[i],
          'fileName': originalNames[i],
        });
      }
      request.fields['fileMeta'] = jsonEncode(meta);

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final fileName = originalNames[i];
        final length = sizes[i];

        final stream = _progressTrackingStream(file.openRead(), (chunkSize) {
          sentBytes[i] += chunkSize;
          reportProgress();
        });

        final mimeString = _guessMimeType(fileName);
        final mimeParts = mimeString.split('/');

        request.files.add(http.MultipartFile(
          'files',
          http.ByteStream(stream),
          length,
          filename: fileName,
          contentType: MediaType(mimeParts[0], mimeParts[1]),
        ));
      }

      onProgress?.call(0.0);

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['ok'] == true) {
          final List<MediaAttachmentModel> atts = [];
          if (data['attachments'] is List) {
            for (final a in (data['attachments'] as List)) {
              if (a is Map<String, dynamic>) {
                atts.add(MediaAttachmentModel.fromJson(a));
              }
            }
          } else if (data['attachment'] is Map<String, dynamic>) {
            atts.add(MediaAttachmentModel.fromJson(data['attachment'] as Map<String, dynamic>));
          }

          onProgress?.call(1.0);

          return MediaUploadResult(
            isSuccess: true,
            messageId: data['messageId'] as String?,
            clientMessageId: data['clientMessageId'] as String?,
            attachments: atts,
          );
        }
      }

      String errMsg = 'خطا در آپلود فایل به سرور';
      try {
        final errData = jsonDecode(response.body);
        errMsg = errData['error']?['message']?.toString() ?? errMsg;
      } catch (_) {}

      return MediaUploadResult(isSuccess: false, error: errMsg);
    } catch (e) {
      return MediaUploadResult(
        isSuccess: false,
        error: 'خطای شبکه در ارسال فایل: $e',
      );
    }
  }

  Future<File?> downloadToFile({
    required MediaAttachmentModel attachment,
    required String targetPath,
    ProgressCallback? onProgress,
  }) async {
    final downloadUrl = attachment.getDownloadUrl(_baseUrl);
    if (downloadUrl.isEmpty) return null;

    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) return null;

      final totalBytes = response.contentLength ?? attachment.fileSize ?? 0;
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