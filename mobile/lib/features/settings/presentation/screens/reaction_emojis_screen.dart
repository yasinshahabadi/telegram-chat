import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import 'package:telegram_chat_mobile/core/settings/reaction_emoji_settings.dart';

/// صفحهٔ تنظیم ایموجی‌های ری‌اکشن.
///
/// امکانات:
///   - نمایش شمارندهٔ «تعداد فعلی / حداکثر»
///   - افزودن ایموجی با `emoji_picker_flutter`
///   - حذف ایموجی (با رعایت حداقل ۱)
///   - جابجایی با long-press + drag
///   - بازگشت به لیست پیش‌فرض با تأیید
class ReactionEmojisScreen extends StatelessWidget {
  const ReactionEmojisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: ReactionEmojiSettings.instance,
        builder: (context, _) {
          final settings = ReactionEmojiSettings.instance;
          return Scaffold(
            appBar: _buildAppBar(context, settings),
            body: Column(
              children: [
                _Header(settings: settings),
                const Divider(height: 1),
                Expanded(child: _EmojiList(settings: settings)),
              ],
            ),
            floatingActionButton: _buildAddButton(context, settings),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ReactionEmojiSettings settings,
  ) {
    final canReset = !settings.isDefault;
    return AppBar(
      title: const Text('تنظیم ایموجی‌های ری‌اکشن'),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_backup_restore_rounded),
          tooltip: 'بازگشت به پیش‌فرض',
          onPressed: canReset ? () => _confirmReset(context) : null,
        ),
      ],
    );
  }

  Widget _buildAddButton(
    BuildContext context,
    ReactionEmojiSettings settings,
  ) {
    final canAdd = settings.canAddMore;
    return FloatingActionButton.extended(
      onPressed: canAdd ? () => _showEmojiPicker(context) : null,
      icon: const Icon(Icons.add_rounded),
      label: const Text('افزودن ایموجی'),
      backgroundColor: canAdd
          ? null
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  // ═════════════════════════════════════════════
  //  Reset
  // ═════════════════════════════════════════════

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('بازگشت به پیش‌فرض'),
          content: const Text(
            'همهٔ ایموجی‌های فعلی حذف و ایموجی‌های پیش‌فرض جایگزین می‌شوند. '
            'این عمل قابل بازگشت نیست.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('بازگشت'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await ReactionEmojiSettings.instance.resetToDefault();
      if (context.mounted) {
        _showSnack(context, 'لیست ایموجی‌ها به پیش‌فرض بازگشت.');
      }
    }
  }

  // ═════════════════════════════════════════════
  //  Emoji picker
  // ═════════════════════════════════════════════

  Future<void> _showEmojiPicker(BuildContext context) async {
    if (!ReactionEmojiSettings.instance.canAddMore) {
      _showSnack(context, 'حداکثر ${ReactionEmojiSettings.maxEmojis} ایموجی مجاز است.');
      return;
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            height: 560,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // نوار کشیدن
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // عنوان
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_reaction_outlined,
                        color: colors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'انتخاب ایموجی',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (context) {
                          final count =
                              ReactionEmojiSettings.instance.emojis.length;
                          return Text(
                            '$count / ${ReactionEmojiSettings.maxEmojis}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.outlineVariant),
                Expanded(
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) =>
                        _handleEmojiSelected(context, emoji),
                    config: Config(
                      height: 460,
                      checkPlatformCompatibility: true,
                      // ✅ پیکربندی رنگ‌های تم تاریک برای هماهنگی با برنامه
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor: colors.surface,
                        emojiSizeMax: 28,
                        verticalSpacing: 4,
                        horizontalSpacing: 4,
                        gridPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        noRecents: Text(
                          'اخیراً استفاده‌شده‌ای وجود ندارد',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: colors.surface,
                        dividerColor: colors.outlineVariant,
                        indicatorColor: colors.primary,
                        iconColor: colors.onSurfaceVariant,
                        iconColorSelected: colors.primary,
                        backspaceColor: colors.onSurfaceVariant,
                        tabIndicatorAnimDuration:
                            const Duration(milliseconds: 180),
                        categoryIcons: const CategoryIcons(),
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: colors.surface,
                        buttonIconColor: colors.onSurfaceVariant,
                        hintText: 'جستجوی ایموجی...',
                        inputTextStyle: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                        ),
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleEmojiSelected(
    BuildContext sheetContext,
    Emoji emoji,
  ) async {
    final settings = ReactionEmojiSettings.instance;
    final value = emoji.emoji;

    if (settings.emojis.contains(value)) {
      _showSnack(sheetContext, 'این ایموجی قبلاً اضافه شده است.');
      return;
    }

    if (!settings.canAddMore) {
      _showSnack(sheetContext, 'حداکثر ${ReactionEmojiSettings.maxEmojis} ایموجی مجاز است.');
      return;
    }

    final ok = await settings.addEmoji(value);
    if (ok && sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
      _showSnack(sheetContext, '«$value» افزوده شد.');
    }
  }

  // ═════════════════════════════════════════════
  //  Helper
  // ═════════════════════════════════════════════

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
//  Header
// ═════════════════════════════════════════════

class _Header extends StatelessWidget {
  final ReactionEmojiSettings settings;
  const _Header({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = settings.emojis.length;
    final ratio = count / ReactionEmojiSettings.maxEmojis;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_emotions_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'شخصی‌سازی ری‌اکشن‌ها',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count / ${ReactionEmojiSettings.maxEmojis}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // نوار پیشرفت ظریف
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'ایموجی‌های دلخواه خود را برای ری‌اکشن روی پیام‌ها انتخاب کنید. '
            'برای جابجایی، هر ایموجی را نگه دارید و بکشید.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
//  Emoji list (reorderable)
// ═════════════════════════════════════════════

class _EmojiList extends StatelessWidget {
  final ReactionEmojiSettings settings;
  const _EmojiList({required this.settings});

  @override
  Widget build(BuildContext context) {
    final emojis = settings.emojis;

    // این حالت نباید رخ دهد (حداقل ۱ اجباری)، ولی برای امنیت نمایش می‌دهیم.
    if (emojis.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('هنوز هیچ ایموجی‌ای اضافه نشده است.'),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: emojis.length,
      // ✅ API جدید Flutter 3.41+: onReorderItem مقدار newIndex را
      // برای آیتم حذف‌شده تنظیم می‌کند. پس دیگر نیازی به محاسبه در
      // سرویس نیست.
      onReorderItem: (oldIndex, newIndex) =>
          settings.reorderEmojis(oldIndex, newIndex),
      buildDefaultDragHandles: true,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return _EmojiRow(
          key: ValueKey('emoji_row_$emoji'),
          emoji: emoji,
          canRemove: settings.canRemove,
          onRemove: () => _confirmRemove(context, emoji),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, String emoji) async {
    final ok = await settings.removeEmoji(emoji);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '«$emoji» حذف شد.',
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}

// ═════════════════════════════════════════════
//  Emoji row
// ═════════════════════════════════════════════

class _EmojiRow extends StatelessWidget {
  final String emoji;
  final bool canRemove;
  final VoidCallback onRemove;

  const _EmojiRow({
    super.key,
    required this.emoji,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // ✅ آیکون drag-handle (غیرتعاملی، فقط نشانه). Flutter کل
              // ردیف را با long-press قابل‌کشیدن می‌کند.
              Icon(
                Icons.drag_indicator_rounded,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                size: 22,
              ),
              const SizedBox(width: 6),
              // حباب ایموجی
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(140),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
              const SizedBox(width: 14),
              // spacer + متن راهنما
              Expanded(
                child: Text(
                  'برای جابجایی نگه دارید',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // دکمهٔ حذف
              IconButton(
                tooltip: canRemove
                    ? 'حذف «$emoji»'
                    : 'حداقل یک ایموجی لازم است',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: canRemove
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant.withAlpha(80),
                ),
                onPressed: canRemove ? onRemove : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}