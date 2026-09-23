import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// صفحه پخش تمام‌صفحه ویدیو با کنترل‌های کامل و Swipe Up برای بستن
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? localPath;
  final String? title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.localPath,
    this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _hideTimer;

  // ✅ برای Swipe Up
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      _controller = VideoPlayerController.file(File(widget.localPath!));
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    }

    try {
      await _controller.initialize();
      if (!mounted) return;

      setState(() => _isInitialized = true);
      _controller.play();
      _scheduleHideControls();

      _controller.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در پخش ویدیو: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
    } else {
      _controller.play();
      _scheduleHideControls();
    }
    setState(() {});
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _dismissViewer() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          // ✅ Swipe Up برای بستن
          onVerticalDragUpdate: (details) {
            final newOffset = _dragOffset + details.delta.dy;
            if (newOffset <= 0) {
              setState(() => _dragOffset = newOffset);
            }
          },
          onVerticalDragEnd: (details) {
            if (_dragOffset < -80) {
              _dismissViewer();
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          onTap: _toggleControls,
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Stack(
              children: [
                // ویدیو
                Center(
                  child: _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : const CircularProgressIndicator(color: Colors.white),
                ),

                // کنترل‌ها
                if (_showControls && _isInitialized)
                  Container(
                    color: Colors.black38,
                    child: Stack(
                      children: [
                        // دکمه بستن
                        Positioned(
                          top: 8,
                          right: 8,
                          child: SafeArea(
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                                onPressed: _dismissViewer,
                              ),
                            ),
                          ),
                        ),

                        // عنوان
                        if (widget.title != null)
                          Positioned(
                            top: 12,
                            left: 16,
                            right: 70,
                            child: SafeArea(
                              child: Text(
                                widget.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                        // دکمه Play/Pause در وسط
                        Center(
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _togglePlay,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // کنترل پایین
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 12,
                              bottom: MediaQuery.of(context).padding.bottom + 12,
                            ),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black87, Colors.transparent],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.white,
                                    bufferedColor: Colors.white38,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(_controller.value.position),
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    Text(
                                      _formatDuration(_controller.value.duration),
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // لودینگ اولیه
                if (!_isInitialized)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),

                // راهنمای Swipe Up
                if (_dragOffset == 0 && !_showControls && _isInitialized)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.keyboard_arrow_up_rounded,
                                  color: Colors.white70, size: 20),
                              SizedBox(width: 6),
                              Text('برای بستن به بالا بکشید',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}