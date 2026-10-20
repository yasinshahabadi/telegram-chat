import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:telegram_chat_mobile/features/media/data/gallery_media_service.dart';
import 'package:telegram_chat_mobile/features/media/domain/media_upload_limits.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_send_payload.dart';
import 'package:telegram_chat_mobile/features/media/presentation/screens/media_composer_screen.dart';
import 'package:telegram_chat_mobile/features/media/presentation/widgets/gallery_media_tile.dart';

/// گالری اختصاصی شبیه تلگرام.
///
/// - انتخاب چندتایی با شمارهٔ ترتیبی
/// - بارگذاری صفحه‌بندی‌شده (۷۲ آیتم در هر صفحه)
/// - مدیریت مجوز، حالت دسترسی محدود، گالری خالی و خطا
class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  static Future<MediaSendPayload?> show(BuildContext context) {
    return Navigator.of(context).push<MediaSendPayload>(
      PageRouteBuilder<MediaSendPayload>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const MediaPickerScreen(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen>
    with WidgetsBindingObserver {
  final GalleryMediaService _service = GalleryMediaService();
  final ScrollController _scrollController = ScrollController();

  final List<AssetEntity> _assets = [];
  final Set<String> _assetIds = {};
  final List<AssetEntity> _selected = [];

  PermissionState? _permission;
  int _totalCount = 0;
  int _page = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _reloadWhenResumed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    // آزادسازی بندانگشتی‌های گالری از کش مشترک تصویر تا حافظه پس از خروج
    // پایین بیاید؛ تصاویر در حال نمایش (چت زیر صفحه) دست‌نخورده می‌مانند.
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache
      ..clear()
      ..clearLiveImages();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _reloadWhenResumed &&
        !_isLoading) {
      _reloadWhenResumed = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final result = await _service.initialize();
      if (!mounted) return;

      setState(() {
        _permission = result.permission;
        _assets
          ..clear()
          ..addAll(result.assets);
        _assetIds
          ..clear()
          ..addAll(result.assets.map((a) => a.id));
        _selected.clear();
        _totalCount = result.totalCount;
        _page = 0;
        _hasMore = result.assets.length >= GalleryMediaService.pageSize &&
            result.assets.length < result.totalCount;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'خطا در بازکردن گالری: $e';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 700) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_permission?.hasAccess != true) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final pageAssets = await _service.loadMore(nextPage);
      if (!mounted) return;

      final fresh = <AssetEntity>[];
      for (final asset in pageAssets) {
        if (_assetIds.add(asset.id)) fresh.add(asset);
      }

      setState(() {
        _page = nextPage;
        _assets.addAll(fresh);
        // اگر صفحهٔ ناقص یا تکراری دریافت شد، به انتهای گالری رسیده‌ایم.
        _hasMore = pageAssets.length >= GalleryMediaService.pageSize &&
            fresh.isNotEmpty &&
            _assets.length < _totalCount;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _toggleSelection(AssetEntity asset) {
    final existing = _selected.indexWhere((a) => a.id == asset.id);
    if (existing >= 0) {
      setState(() => _selected.removeAt(existing));
      return;
    }

    if (_selected.length >= MediaUploadLimits.maxFiles) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'حداکثر ${MediaUploadLimits.maxFiles} فایل در هر پیام مجاز است.',
              textDirection: TextDirection.rtl,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() => _selected.add(asset));
  }

  int _orderOf(AssetEntity asset) {
    final index = _selected.indexWhere((a) => a.id == asset.id);
    return index < 0 ? 0 : index + 1;
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  Future<void> _openComposer() async {
    if (_selected.isEmpty) return;

    final payload = await MediaComposerScreen.show(
      context,
      media: _service.toPickedMedia(List<AssetEntity>.from(_selected)),
      allowAddMore: true,
    );

    if (payload != null && mounted) {
      Navigator.of(context).pop(payload);
    }
  }

  Future<void> _requestPermissionAgain() async {
    await _initialize();
  }

  Future<void> _openSettings() async {
    _reloadWhenResumed = true;
    await PhotoManager.openSetting();
  }

  Future<void> _manageLimitedAccess() async {
    try {
      await PhotoManager.presentLimited(type: RequestType.common);
    } catch (_) {
      _reloadWhenResumed = true;
      await PhotoManager.openSetting();
    }
    if (mounted) await _initialize();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _buildHeader(theme),
            ),
            if (_permission?.isLimited == true) _buildLimitedBanner(theme),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildContent(theme)),
                  _buildSelectionBar(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final selectedCount = _selected.length;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'بازگشت',
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCount > 0 ? '$selectedCount مورد انتخاب شد' : 'گالری',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  selectedCount > 0
                      ? 'حداکثر ${MediaUploadLimits.maxFiles} مورد در هر پیام'
                      : _isLoading
                          ? 'در حال بارگذاری...'
                          : _permission?.hasAccess != true
                              ? 'دسترسی به گالری'
                              : '$_totalCount عکس و ویدیو',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selectedCount > 0)
            IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'لغو انتخاب',
            ),
        ],
      ),
    );
  }

  Widget _buildLimitedBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'دسترسی محدود؛ فقط بخشی از گالری نمایش داده می‌شود.',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: _manageLimitedAccess,
            child: const Text('مدیریت'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _StateMessage(
        icon: Icons.error_outline_rounded,
        title: 'بازکردن گالری ممکن نشد',
        message: _error!,
        actionLabel: 'تلاش دوباره',
        onAction: _initialize,
      );
    }

    final permission = _permission;
    if (permission == null || !permission.hasAccess) {
      final denied = permission == PermissionState.denied ||
          permission == PermissionState.restricted;
      return _StateMessage(
        icon: Icons.photo_library_outlined,
        title: 'دسترسی به گالری',
        message: denied
            ? 'برای انتخاب عکس و ویدیو، اجازهٔ دسترسی به گالری را فعال کنید.'
            : 'برای مشاهدهٔ عکس‌ها و ویدیوهای گوشی، دسترسی لازم است.',
        actionLabel: 'اجازهٔ دسترسی',
        onAction: _requestPermissionAgain,
        secondaryLabel: 'تنظیمات',
        onSecondary: _openSettings,
      );
    }

    if (_assets.isEmpty) {
      return const _StateMessage(
        icon: Icons.image_not_supported_outlined,
        title: 'گالری خالی است',
        message: 'عکس یا ویدیویی در گالری دستگاه پیدا نشد.',
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: _assets.length,
            itemBuilder: (context, index) {
              final asset = _assets[index];
              return GalleryMediaTile(
                key: ValueKey(asset.id),
                asset: asset,
                selectionOrder: _orderOf(asset),
                onTap: () => _toggleSelection(asset),
              );
            },
          ),
        ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: _selected.isEmpty ? 24 : 92,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionBar(ThemeData theme) {
    final visible = _selected.isNotEmpty && !_isLoading;

    return Positioned(
      left: 14,
      right: 14,
      bottom: MediaQuery.of(context).padding.bottom + 12,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0, 1.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: visible ? 1 : 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                height: 62,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF22303D)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_selected.length}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'برای ارسال آماده است',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _openComposer,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('ادامه'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 54,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
