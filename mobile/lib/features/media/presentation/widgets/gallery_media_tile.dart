import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// یک سلول گالری با بندانگشتی، مدت‌زمان ویدیو و نشان انتخاب.
///
/// بندانگشتی‌ها با [AssetEntityImageProvider] کش می‌شوند و با اندازهٔ
/// کوچک (۳۲۰px) decode می‌شوند تا حافظهٔ گرید پایین بماند.
class GalleryMediaTile extends StatelessWidget {
  final AssetEntity asset;
  final int selectionOrder;
  final VoidCallback onTap;

  const GalleryMediaTile({
    super.key,
    required this.asset,
    required this.selectionOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selectionOrder > 0;
    final primary = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: isSelected
          ? 'انتخاب‌شده، مورد $selectionOrder'
          : (asset.type == AssetType.video ? 'ویدیو' : 'عکس'),
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: AssetEntityImage(
                  asset,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(320),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.broken_image_outlined,
                    size: 24,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  frameBuilder: (context, child, frame, syncLoaded) {
                    if (syncLoaded) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                ),
              ),
              if (isSelected)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: primary.withAlpha(46),
                      border: Border.all(color: primary, width: 2),
                    ),
                  ),
                ),
              if (asset.type == AssetType.video)
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: _VideoDurationBadge(duration: asset.duration),
                ),
              Positioned(
                top: 5,
                right: 5,
                child: _SelectionBadge(
                  order: selectionOrder,
                  primary: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  final int order;
  final Color primary;

  const _SelectionBadge({required this.order, required this.primary});

  @override
  Widget build(BuildContext context) {
    final isSelected = order > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? primary : Colors.black.withAlpha(56),
        border: Border.all(
          color: Colors.white.withAlpha(isSelected ? 255 : 220),
          width: 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? Text(
              '$order',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            )
          : null,
    );
  }
}

class _VideoDurationBadge extends StatelessWidget {
  final int duration;

  const _VideoDurationBadge({required this.duration});

  @override
  Widget build(BuildContext context) {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    final label =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_arrow_rounded,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
