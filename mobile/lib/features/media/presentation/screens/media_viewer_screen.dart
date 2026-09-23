import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// صفحه نمایش تمام‌صفحه عکس با بزرگ‌نمایی، چرخش و swipe-to-dismiss
class MediaViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? localPath;
  final String? heroTag;
  final String? fileName;

  const MediaViewerScreen({
    super.key,
    required this.imageUrl,
    this.localPath,
    this.heroTag,
    this.fileName,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  bool _isZoomed = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        if (_animation != null) {
          _transformController.value = _animation!.value;
        }
      });

    _transformController.addListener(() {
      final scale = _transformController.value.getMaxScaleOnAxis();
      if ((scale > 1.01) != _isZoomed) {
        setState(() => _isZoomed = scale > 1.01);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ));
    } else {
      final position = _doubleTapDetails!.localPosition;
      final zoom = 2.5;
      final x = -position.dx * (zoom - 1);
      final y = -position.dy * (zoom - 1);
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: Matrix4.identity()
          ..translate(x, y)
          ..scale(zoom),
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ));
    }
    _animationController.forward(from: 0);
  }

  Widget _buildImage() {
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      return Image.file(
        File(widget.localPath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildNetworkImage(),
      );
    }
    return _buildNetworkImage();
  }

  Widget _buildNetworkImage() {
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
            SizedBox(height: 12),
            Text('خطا در بارگذاری تصویر', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  /// ✅ بستن با انیمیشن نرم به سمت بالا
  void _dismissViewer() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ از AnnotatedRegion برای رنگ آیکون‌های نوار وضعیت استفاده می‌کنیم
    // (بدون مخفی کردن نوار سیستم → عدم جابجایی layout)
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
        // ✅ جلوگیری از تغییر اندازه layout پایین صفحه
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          // ✅ Swipe UP (به جای Swipe Down) برای بستن
          onVerticalDragUpdate: _isZoomed
              ? null
              : (details) {
                  final newOffset = _dragOffset + details.delta.dy;
                  // فقط اجازه کشیدن به بالا (مقدار منفی)
                  if (newOffset <= 0) {
                    setState(() => _dragOffset = newOffset);
                  }
                },
          onVerticalDragEnd: _isZoomed
              ? null
              : (details) {
                  // ✅ اگر بیش از ۸۰ پیکسل به بالا کشیده شد → بستن
                  if (_dragOffset < -80) {
                    _dismissViewer();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                },
          child: Stack(
            children: [
              // تصویر با قابلیت بزرگ‌نمایی
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    clipBehavior: Clip.none,
                    child: Center(
                      child: widget.heroTag != null
                          ? Hero(
                              tag: widget.heroTag!,
                              child: _buildImage(),
                            )
                          : _buildImage(),
                    ),
                  ),
                ),
              ),

              // دکمه بستن (بالا راست)
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

              // نام فایل (بالا چپ)
              if (widget.fileName != null)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 70,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),

              // راهنمای Swipe Up (پایین وسط)
              if (_dragOffset == 0 && !_isZoomed)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}