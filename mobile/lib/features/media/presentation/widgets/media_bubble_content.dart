import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// ویجت اختصاصی نمایش محتوای چندرسانه‌ای درون بالون پیام
class MediaBubbleContent extends StatefulWidget {
  final MediaAttachmentModel attachment;
  final bool isMe;
  final String baseUrl;
  final VoidCallback? onTap;

  const MediaBubbleContent({
    super.key,
    required this.attachment,
    required this.isMe,
    required this.baseUrl,
    this.onTap,
  });

  @override
  State<MediaBubbleContent> createState() => _MediaBubbleContentState();
}

class _MediaBubbleContentState extends State<MediaBubbleContent> {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    final att = widget.attachment;
    final url = att.localPath ?? att.getDownloadUrl(widget.baseUrl);
    if (url.isEmpty) return;

    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });
      _audioPlayer!.onPositionChanged.listen((pos) {
        if (mounted) {
          setState(() {
            _position = pos;
          });
        }
      });
    }

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      if (att.localPath != null && File(att.localPath!).existsSync()) {
        await _audioPlayer!.play(DeviceFileSource(att.localPath!));
      } else {
        await _audioPlayer!.play(UrlSource(url));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    final theme = Theme.of(context);

    // ۱. نمایش تصویر
    if (att.isPhoto) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
            child: att.localPath != null && File(att.localPath!).existsSync()
                ? Image.file(
                    File(att.localPath!),
                    fit: BoxFit.cover,
                  )
                : CachedNetworkImage(
                    imageUrl: att.getDownloadUrl(widget.baseUrl),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 180,
                      color: theme.colorScheme.surfaceVariant.withAlpha(80),
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 120,
                      color: Colors.black12,
                      child: const Icon(Icons.broken_image_rounded, size: 40),
                    ),
                  ),
          ),
        ),
      );
    }

    // ۲. نمایش و پخش ویس و فایل صوتی
    if (att.isVoice || att.isAudio) {
      final currentSeconds = _position.inSeconds;
      final totalSeconds = att.duration > 0 ? att.duration : 1;
      final progress = (currentSeconds / totalSeconds).clamp(0.0, 1.0);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isMe
              ? theme.colorScheme.primaryContainer.withAlpha(100)
              : theme.colorScheme.surfaceVariant.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              radius: 18,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _toggleAudio,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140,
                  child: LinearProgressIndicator(
                    value: _isPlaying ? progress : 0.0,
                    backgroundColor: theme.colorScheme.onSurface.withAlpha(30),
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _isPlaying
                          ? '${(currentSeconds ~/ 60).toString().padLeft(2, '0')}:${(currentSeconds % 60).toString().padLeft(2, '0')}'
                          : att.formattedDuration,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (att.formattedSize.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        att.formattedSize,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ۳. نمایش فایل و اسناد
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? theme.colorScheme.primaryContainer.withAlpha(100)
            : theme.colorScheme.surfaceVariant.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  att.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (att.formattedSize.isNotEmpty)
                  Text(
                    att.formattedSize,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
