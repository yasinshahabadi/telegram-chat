import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/media/data/media_download_manager.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';
import '../screens/media_viewer_screen.dart';
import '../screens/video_player_screen.dart';

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

  File? _localFile;
  bool _isDownloading = false;
  double _progress = 0.0;
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    _checkLocal();
    MediaDownloadManager.instance.addListener(_onManagerUpdate);
  }

  @override
  void dispose() {
    MediaDownloadManager.instance.removeListener(_onManagerUpdate);
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (!mounted) return;
    final msgId = widget.attachment.messageId;
    final downloading = MediaDownloadManager.instance.isDownloading(msgId);
    final progress = MediaDownloadManager.instance.progressFor(msgId) ?? 0.0;
    if (downloading != _isDownloading || (progress - _progress).abs() > 0.01) {
      setState(() {
        _isDownloading = downloading;
        _progress = progress;
      });
    }
  }

  void _checkLocal() {
    final path = widget.attachment.localPath;
    if (path != null && File(path).existsSync()) {
      _localFile = File(path);
    }
  }

  bool get _hasLocal => _localFile != null;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _downloadFailed = false;
    });

    final file = await MediaDownloadManager.instance.downloadAndCache(
      messageId: widget.attachment.messageId,
      attachment: widget.attachment,
    );

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      if (file != null) {
        _localFile = file;
      } else {
        _downloadFailed = true;
      }
    });

    if (_downloadFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطا در دانلود فایل. لطفاً دوباره تلاش کنید.')),
      );
    }
  }

  void _openImageViewer() {
    final url = widget.attachment.getDownloadUrl(widget.baseUrl);
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => MediaViewerScreen(
          imageUrl: url,
          localPath: _localFile?.path,
          heroTag: 'media_${widget.attachment.id}',
          fileName: widget.attachment.fileName,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _openVideoPlayer() {
    final url = widget.attachment.getDownloadUrl(widget.baseUrl);
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: url,
          localPath: _localFile?.path,
          title: widget.attachment.fileName,
        ),
      ),
    );
  }

  Future<void> _toggleAudio() async {
    final att = widget.attachment;
    final url = _localFile?.path ?? att.getDownloadUrl(widget.baseUrl);
    if (url.isEmpty) return;

    if (!_hasLocal) {
      await _startDownload();
      if (!_hasLocal) return;
    }

    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      });
      _audioPlayer!.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
    }

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play(DeviceFileSource(_localFile!.path));
    }
  }

  // ─────────────────────────────────────────────
  // Placeholder + Download Button (مثل تلگرام)
  // ─────────────────────────────────────────────
  Widget _buildPlaceholder({
    required IconData icon,
    required int height,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: height.toDouble(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.brown.shade800.withAlpha(200),
            Colors.brown.shade900.withAlpha(220),
          ],
        ),
      ),
      child: Stack(
        children: [
          // آیکون پس‌زمینه
          Positioned(
            left: -20,
            bottom: -20,
            child: Icon(icon, size: 120, color: Colors.white.withAlpha(20)),
          ),

          // اطلاعات فایل (بالا)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: Colors.white.withAlpha(220)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (widget.attachment.formattedSize.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(
                      widget.attachment.formattedSize,
                      style: TextStyle(
                        color: Colors.white.withAlpha(160),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // دکمه دانلود / درصد پیشرفت (وسط)
          Center(
            child: _isDownloading
                ? _buildProgressCircle()
                : Material(
                    color: Colors.black.withAlpha(120),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _startDownload,
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(
                          _downloadFailed
                              ? Icons.refresh_rounded
                              : Icons.arrow_downward_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCircle() {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: _progress > 0 ? _progress : null,
              strokeWidth: 3,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          Text(
            '${(_progress * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    final theme = Theme.of(context);

    // ─── عکس ───
    if (att.isPhoto) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280, minWidth: 200),
          child: _hasLocal
              ? GestureDetector(
                  onTap: _openImageViewer,
                  child: Hero(
                    tag: 'media_${att.id}',
                    child: Image.file(
                      _localFile!,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                    ),
                  ),
                )
              : _buildPlaceholder(icon: Icons.image_rounded, height: 200),
        ),
      );
    }

    // ─── ویدیو ───
    if (att.isVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280, minWidth: 220),
          child: _hasLocal
              ? GestureDetector(
                  onTap: _openVideoPlayer,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(color: Colors.black87, height: 180),
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 36),
                      ),
                      if (att.duration > 0)
                        Positioned(
                          bottom: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(att.formattedDuration,
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                )
              : _buildPlaceholder(icon: Icons.videocam_rounded, height: 180),
        ),
      );
    }

    // ─── ویس / صوت ───
    if (att.isVoice || att.isAudio) {
      final currentSeconds = _position.inSeconds;
      final totalSeconds = att.duration > 0 ? att.duration : 1;
      final progress = (currentSeconds / totalSeconds).clamp(0.0, 1.0);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isMe
              ? theme.colorScheme.primaryContainer.withAlpha(100)
              : theme.colorScheme.surface.withAlpha(80),
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
                icon: _isDownloading
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 22,
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
                      style: TextStyle(fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (att.formattedSize.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(att.formattedSize,
                          style: TextStyle(fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(160))),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ─── سند ───
    if (!_hasLocal && !_isDownloading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 220),
          child: _buildPlaceholder(icon: Icons.insert_drive_file_rounded, height: 90),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? theme.colorScheme.primaryContainer.withAlpha(100)
            : theme.colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_rounded, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(att.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                if (att.formattedSize.isNotEmpty)
                  Text(att.formattedSize,
                      style: TextStyle(fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}