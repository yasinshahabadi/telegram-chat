import 'package:flutter/material.dart';

/// Divider نشان‌دهندهٔ مرز بین پیام‌های خوانده‌شده و نخوانده.
///
/// پس از پایان مهلت (که در `ChatScreen` تعیین می‌شود)، با انیمیشن محو می‌شود
/// و سپس از درخت حذف می‌شود (از طریق `visible`).
class UnreadDivider extends StatelessWidget {
  final bool visible;
  final int count;

  const UnreadDivider({
    super.key,
    this.visible = true,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final label = count > 1
        ? '$count پیام نخوانده'
        : 'پیام نخوانده';

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withAlpha(0),
                      accent.withAlpha(120),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withAlpha(35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withAlpha(80), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        size: 12, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withAlpha(120),
                      accent.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}