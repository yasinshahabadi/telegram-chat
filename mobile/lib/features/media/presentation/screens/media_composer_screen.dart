import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:telegram_chat_mobile/features/media/domain/media_upload_limits.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_send_payload.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/picked_media.dart';

/// صفحهٔ پیش‌نمایش و کپشن قبل از ارسال.
///
/// کاربر می‌تواند آیتم‌ها را حذف کند، بین آن‌ها جابه‌جا شود، کپشن بنویسد
/// و در صورت نیاز به گالری برگردد و انتخاب را تغییر دهد.
class MediaComposerScreen extends StatefulWidget {
  final List<PickedMedia> media;
  final bool allowAddMore;

  const MediaComposerScreen({
    super.key,
    required this.media,
    this.allowAddMore = false,
  });

  static Future<MediaSendPayload?> show(
    BuildContext context, {
    required List<PickedMedia> media,
    bool allowAddMore = false,
  }) {
    return Navigator.of(context).push<MediaSendPayload>(
      PageRouteBuilder<MediaSendPayload>(
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => MediaComposerScreen(
          media: media,
          allowAddMore: allowAddMore,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MediaComposerScreen> createState() => _MediaComposerScreenState();
}

class _MediaComposerScreenState extends State<MediaComposerScreen> {
  static const Color _previewBackground = Color(0xFF0B141A);

  late final List<PickedMedia> _items;
  late final PageController _pageController;
  final TextEditingController _captionController = TextEditingController();

  int _currentIndex = 0;
  bool _isPreparing = false;

  @override
  void initState() {
    super.initState();
    _items = List<PickedMedia>.from(widget.media);
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _removeAt(int index) {
    if (_items.length <= 1) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _items.removeAt(index);
      if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_currentIndex);
    });
  }

  Future<void> _submit() async {
    if (_isPreparing || _items.isEmpty) return;

    if (_items.length > MediaUploadLimits.maxFiles) {
      _showError(
        'حداکثر ${MediaUploadLimits.maxFiles} فایل در هر پیام مجاز است.',
      );
      return;
    }

    setState(() => _isPreparing = true);

    try {
      var totalBytes = 0;
      for (final item in _items) {
        final file = await item.resolveFile();
        if (file == null || !await file.exists()) {
          throw _ComposerException(
            'فایل «${item.fileName}» در دسترس نیست. لطفاً دوباره انتخاب کنید.',
          );
        }
        totalBytes += await file.length();
      }

      if (totalBytes > MediaUploadLimits.maxTotalBytes) {
        throw _ComposerException(
          'مجموع حجم انتخاب‌شده ${MediaUploadLimits.formatBytes(totalBytes)} است؛ '
          'حداکثر مجاز ${MediaUploadLimits.formatBytes(MediaUploadLimits.maxTotalBytes)} است.',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        MediaSendPayload(
          media: List<PickedMedia>.unmodifiable(_items),
          caption: _captionController.text.trim(),
        ),
      );
    } on _ComposerException catch (e) {
      if (!mounted) return;
      setState(() => _isPreparing = false);
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPreparing = false);
      _showError('خطا در آماده‌سازی فایل‌ها: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: TextDirection.rtl),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _previewBackground,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(theme),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _items.length,
                  onPageChanged: (index) {
                    if (index != _currentIndex) {
                      setState(() => _currentIndex = index);
                    }
                  },
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: _MediaPreview(item: _items[index]),
                    );
                  },
                ),
              ),
              _buildComposerPanel(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            tooltip: 'بازگشت',
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'پیش‌نمایش',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_items.length} مورد انتخاب‌شده',
                  style: TextStyle(
                    color: Colors.white.withAlpha(160),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeAt(_currentIndex),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.white.withAlpha(220),
            ),
            tooltip: 'حذف این مورد',
          ),
        ],
      ),
    );
  }

  Widget _buildComposerPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThumbnailStrip(theme),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      textDirection: TextDirection.rtl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                      decoration: InputDecoration(
                        hintText: 'افزودن کپشن...',
                        hintStyle: TextStyle(
                          color:
                              theme.colorScheme.onSurfaceVariant.withAlpha(170),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSendButton(theme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: theme.colorScheme.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _isPreparing ? null : _submit,
            child: SizedBox(
              width: 50,
              height: 50,
              child: _isPreparing
                  ? Padding(
                      padding: const EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: 22,
                    ),
            ),
          ),
        ),
        if (_items.length > 1)
          Positioned(
            top: -4,
            left: -4,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
              child: Text(
                '${_items.length}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: theme.colorScheme.onTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnailStrip(ThemeData theme) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _items.length + (widget.allowAddMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return _AddMoreTile(
              onTap: () => Navigator.of(context).maybePop(),
            );
          }

          return _ComposerThumbnail(
            item: _items[index],
            isCurrent: index == _currentIndex,
            onTap: () {
              setState(() => _currentIndex = index);
              if (_pageController.hasClients) {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            onRemove: () => _removeAt(index),
          );
        },
      ),
    );
  }
}

class _ComposerException implements Exception {
  final String message;

  const _ComposerException(this.message);
}

class _MediaPreview extends StatelessWidget {
  final PickedMedia item;

  const _MediaPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isPhoto) {
      if (item.asset != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AssetEntityImage(
            item.asset!,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(1200),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _UnavailablePreview(item: item),
          ),
        );
      }
      final file = item.sourceFile;
      if (file != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            cacheWidth: (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
            errorBuilder: (_, __, ___) => _UnavailablePreview(item: item),
          ),
        );
      }
    }

    if (item.isVideo && item.asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AssetEntityImage(
              item.asset!,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(1200),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _UnavailablePreview(item: item),
            ),
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(110),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(150)),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _PreviewChip(
                icon: Icons.videocam_rounded,
                label: _formatDuration(item.duration),
              ),
            ),
          ],
        ),
      );
    }

    return _UnavailablePreview(item: item);
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _UnavailablePreview extends StatelessWidget {
  final PickedMedia item;

  const _UnavailablePreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final icon = item.isAudio
        ? Icons.audiotrack_rounded
        : item.isVideo
            ? Icons.videocam_rounded
            : Icons.insert_drive_file_rounded;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(28)),
              ),
              child: Icon(icon, color: Colors.white.withAlpha(210), size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              item.fileName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(220),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _typeLabel(item),
              style: TextStyle(
                color: Colors.white.withAlpha(130),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(PickedMedia item) {
    if (item.isAudio) return 'فایل صوتی';
    if (item.isVideo) return 'ویدیو';
    return 'سند';
  }
}

class _PreviewChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerThumbnail extends StatelessWidget {
  final PickedMedia item;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ComposerThumbnail({
    required this.item,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(80),
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildThumb(theme),
              ),
            ),
          ),
          Positioned(
            top: -5,
            left: -5,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(180),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (item.isVideo)
            const Positioned(
              left: 4,
              bottom: 4,
              child: Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumb(ThemeData theme) {
    if (item.isPhoto) {
      if (item.asset != null) {
        return AssetEntityImage(
          item.asset!,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(180),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _iconThumb(theme, Icons.image_outlined),
        );
      }
      if (item.sourceFile != null) {
        return Image.file(
          item.sourceFile!,
          fit: BoxFit.cover,
          cacheWidth: 180,
          errorBuilder: (_, __, ___) => _iconThumb(theme, Icons.image_outlined),
        );
      }
    }

    if (item.isVideo && item.asset != null) {
      return AssetEntityImage(
        item.asset!,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(180),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            _iconThumb(theme, Icons.videocam_outlined),
      );
    }

    if (item.isAudio) {
      return _iconThumb(theme, Icons.audiotrack_rounded);
    }

    return _iconThumb(theme, Icons.insert_drive_file_rounded);
  }

  Widget _iconThumb(ThemeData theme, IconData icon) {
    return Center(
      child: Icon(
        icon,
        size: 24,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AddMoreTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddMoreTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 62,
      height: 62,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                Text(
                  'افزودن',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: theme.colorScheme.onSurfaceVariant,
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
