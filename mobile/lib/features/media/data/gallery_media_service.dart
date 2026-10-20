import 'package:photo_manager/photo_manager.dart';

import '../domain/models/picked_media.dart';

/// نتیجهٔ آماده‌سازی گالری.
class GalleryInitResult {
  final PermissionState permission;
  final List<AssetEntity> assets;
  final int totalCount;

  const GalleryInitResult({
    required this.permission,
    required this.assets,
    required this.totalCount,
  });
}

/// دسترسی به گالری دستگاه با صفحه‌بندی سبک.
///
/// فقط [AssetType.image] و [AssetType.video] درخواست می‌شوند تا از
/// پرسیدن مجوز صوتی غیرضروری جلوگیری شود.
class GalleryMediaService {
  static const int pageSize = 72;

  AssetPathEntity? _album;

  static final PMFilter _filter = FilterOptionGroup(
    imageOption: const FilterOption(needTitle: true),
    videoOption: const FilterOption(needTitle: true),
    orders: const [
      OrderOption(type: OrderOptionType.createDate, asc: false),
    ],
  );

  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  /// بارگذاری اولین صفحه از رسانه‌ها.
  ///
  /// اگر گالری خالی باشد، [totalCount] صفر و لیست خالی برمی‌گردد.
  Future<GalleryInitResult> initialize() async {
    final permission = await requestPermission();
    if (!permission.hasAccess) {
      return GalleryInitResult(
        permission: permission,
        assets: const [],
        totalCount: 0,
      );
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: _filter,
    );

    if (albums.isEmpty) {
      return GalleryInitResult(
        permission: permission,
        assets: const [],
        totalCount: 0,
      );
    }

    _album = albums.first;
    final total = await _album!.assetCountAsync;
    final assets = await _album!.getAssetListPaged(page: 0, size: pageSize);

    return GalleryInitResult(
      permission: permission,
      assets: assets,
      totalCount: total,
    );
  }

  /// بارگذاری صفحهٔ بعد. لیست خالی یعنی به انتهای گالری رسیده‌ایم.
  Future<List<AssetEntity>> loadMore(int page) async {
    final album = _album;
    if (album == null) return const [];
    return album.getAssetListPaged(page: page, size: pageSize);
  }

  /// تبدیل آیتم‌های گالری به مدل قابل ارسال.
  ///
  /// این متد سبک است و فایل اصلی را باز نمی‌کند؛ resolve واقعی در
  /// زمان ارسال انجام می‌شود.
  List<PickedMedia> toPickedMedia(List<AssetEntity> assets) {
    return assets.map(PickedMedia.fromAsset).toList(growable: false);
  }
}
