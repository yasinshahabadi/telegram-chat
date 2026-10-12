import 'package:flutter/material.dart';

import 'package:telegram_chat_mobile/core/settings/reaction_emoji_settings.dart';

/// نمایش چیپ‌های واکنش زیر پیام + کلیک برای toggle.
class ReactionBar extends StatelessWidget {
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final ValueChanged<String> onToggle;
  final bool isMe;

  const ReactionBar({
    super.key,
    required this.reactions,
    required this.myReactions,
    required this.onToggle,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactions.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final isMine = myReactions.contains(emoji);

          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onToggle(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.primary.withAlpha(70)
                    : (isMe
                        ? theme.colorScheme.surface.withAlpha(100)
                        : theme.colorScheme.surfaceContainerHighest.withAlpha(140)),
                borderRadius: BorderRadius.circular(20),
                border: isMine
                    ? Border.all(color: theme.colorScheme.primary, width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 13)),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// ردیف انتخابگر واکنش که در منوی long-press نمایش داده می‌شود.
///
/// ✅ Stage 19 (مرحله ۱): لیست ایموجی‌ها از `ReactionEmojiSettings.instance`
/// خوانده می‌شود، نه hardcode. تغییرات کاربر در صفحهٔ تنظیمات، بلافاصله
/// اینجا منعکس می‌شود (چون `ListenableBuilder` به notifyListeners گوش می‌دهد).
///
/// ✅ همیشه به‌صورت افقی قابل اسکرول است.
/// وقتی همهٔ ایموجی‌ها در عرض صفحه جا شوند، `spaceEvenly` آن‌ها را وسط‌چین می‌کند.
/// وقتی جا نشوند، اسکرول افقی بدون هیچ overflow فعال می‌شود.
class ReactionPickerRow extends StatelessWidget {
  final ValueChanged<String> onPick;

  const ReactionPickerRow({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReactionEmojiSettings.instance,
      builder: (context, _) {
        final emojis = ReactionEmojiSettings.instance.emojis;

        // اگر کاربر همهٔ ایموجی‌ها را حذف کرده باشد (نباید اتفاق بیفتد،
        // چون حداقل ۱ اجباری است) — فضای خالی می‌دهیم.
        if (emojis.isEmpty) {
          return const SizedBox(height: 56);
        }

        return SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: emojis
                          .map((emoji) => _buildEmojiButton(emoji))
                          .toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => onPick(emoji),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}