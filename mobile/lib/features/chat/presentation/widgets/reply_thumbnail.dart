import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/media/data/media_download_manager.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// برچسب فارسی برای نوع مدیا (مطابق با الگوی تلگرام).
class ReplyPreviewHelpers {
  static String labelFor(String? mediaType) {
    switch ((mediaType ?? '').toLowerCase()) {
      case 'photo':    return 'عکس';
      case 'video':    return 'ویدیو';
      case 'voice':    return 'پیام صوتی';
      case 'audio':    return 'صدا';
      case 'document': return 'فایل';
      default:         return 'پیام';
    }
  }
}

/// تصویر کوچک پیش‌نمایش مدیا در ریپلای.
///
/// ترتیب تلاش:
///   1) کش محلی (توسط MediaDownloadManager)
///   2) شبکه (با CachedNetworkImage روی endpoint تلگرام)
///   3) placeholder آیکون (بر اساس نوع مدیا)
class ReplyThumbnail extends StatefulWidget {
  final String? mediaType;
  final String? attachmentId;
  final String? telegramFileId;
  final String? fileName;
  final String baseUrl;
  final double size;

  const ReplyThumbnail({
    super.key,
    this.mediaType,
    this.attachmentId,
    this.telegramFileId,
    this.fileName,
    required this.baseUrl,
    this.size = 40,
  });

  @override
  State<ReplyThumbnail> createState() => _ReplyThumbnailState();
}

class _ReplyThumbnailState extends State<ReplyThumbnail> {
  File? _localFile;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(ReplyThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentId != widget.attachmentId ||
        oldWidget.telegramFileId != widget.telegramFileId) {
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    final id = widget.attachmentId;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    final synth = MediaAttachmentModel(
      id: id,
      messageId: '',
      mediaType: widget.mediaType ?? 'document',
      telegramFileId: widget.telegramFileId,
      fileName: widget.fileName ?? 'file',
      createdAt: 0,
    );

    final f = await MediaDownloadManager.instance.resolveLocalFile(synth);
    if (!mounted) return;
    setState(() {
      _localFile = f;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final theme = Theme.of(context);
    final mt = (widget.mediaType ?? '').toLowerCase();

    Widget content;

    if (mt == 'photo') {
      if (_localFile != null) {
        content = Image.file(
          _localFile!,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).toInt(),
          errorBuilder: (_, __, ___) => _iconPlaceholder(theme, Icons.image_rounded),
        );
      } else if (!_checking &&
          widget.telegramFileId != null &&
          widget.telegramFileId!.isNotEmpty) {
        final url =
            '${widget.baseUrl}/api/media/file?fileId=${Uri.encodeComponent(widget.telegramFileId!)}';
        content = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: (size * 3).toInt(),
          placeholder: (_, __) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) =>
              _iconPlaceholder(theme, Icons.broken_image_rounded),
        );
      } else {
        content = _iconPlaceholder(theme, Icons.image_rounded);
      }
    } else if (mt == 'video') {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black87),
          Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white.withAlpha(220),
              size: size * 0.5,
            ),
          ),
        ],
      );
    } else if (mt == 'voice') {
      content = _iconPlaceholder(theme, Icons.mic_rounded);
    } else if (mt == 'audio') {
      content = _iconPlaceholder(theme, Icons.music_note_rounded);
    } else if (mt == 'document') {
      content = _iconPlaceholder(theme, Icons.insert_drive_file_rounded);
    } else {
      content = Container(color: theme.colorScheme.surfaceContainerHighest);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: content,
      ),
    );
  }

  Widget _iconPlaceholder(ThemeData theme, IconData icon) {
    return Container(
      color: theme.colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: theme.colorScheme.primary,
        size: widget.size * 0.5,
      ),
    );
  }
}