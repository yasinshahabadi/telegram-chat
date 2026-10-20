import 'package:flutter/material.dart';

import 'attachment_action.dart';

/// نوار پیوست شناور و قابل‌گسترش.
///
/// با افزودن اکشن جدید به [actions]، آیتم به‌صورت خودکار در نوار
/// قرار می‌گیرد و در صورت کمبود فضا، نوار افقی اسکرول می‌شود.
class AttachmentPanel extends StatelessWidget {
  final List<AttachmentAction> actions;
  final VoidCallback? onActionSelected;

  const AttachmentPanel({
    super.key,
    required this.actions,
    this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C2733)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(14)
                  : theme.colorScheme.outlineVariant.withAlpha(90),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 70 : 18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: (constraints.maxWidth - 12).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final action in actions)
                        _AttachmentActionButton(
                          action: action,
                          onTap: () {
                            onActionSelected?.call();
                            action.onSelected();
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  final AttachmentAction action;
  final VoidCallback onTap;

  const _AttachmentActionButton({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = action.accentColor ?? theme.colorScheme.primary;

    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 78,
          height: 78,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withAlpha(
                    theme.brightness == Brightness.dark ? 34 : 24,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(action.icon, color: accent, size: 23),
              ),
              const SizedBox(height: 5),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
