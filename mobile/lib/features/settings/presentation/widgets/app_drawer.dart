import 'package:flutter/material.dart';

import 'package:telegram_chat_mobile/features/settings/presentation/screens/reaction_emojis_screen.dart';

/// Drawer قابل‌گسترش برنامه.
///
/// طراحی:
///   - Header تمیز با آیکون گرادیانی، عنوان bold، و زیرعنوان.
///   - برچسب بخش (Section) برای دسته‌بندی آیتم‌ها.
///   - آیتم‌های ListTile-like با گوشه‌های گرد، آیکون در مربع رنگی،
///     عنوان bold و زیرعنوان کوتاه.
///   - Footer با نسخهٔ برنامه.
///
/// افزودن گزینه‌های جدید در آینده: فقط یک [_DrawerItem] به لیست `children`
/// در `_buildBody` اضافه کنید. نیازی به تغییر ساختار نیست.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          children: [
            const _DrawerHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
            const _DrawerFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const _SectionLabel('شخصی‌سازی'),
        _DrawerItem(
          icon: Icons.emoji_emotions_outlined,
          title: 'ایموجی‌های ری‌اکشن',
          subtitle: 'ایموجی‌های دلخواه خود را تنظیم کنید',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ReactionEmojisScreen(),
              ),
            );
          },
        ),
        // 🔽 گزینه‌های آیندهٔ Drawer اینجا اضافه می‌شوند.
        // مثلاً:
        // const _SectionLabel('ظاهر'),
        // _DrawerItem(icon: ..., title: ..., subtitle: ..., onTap: ...),
      ],
    );
  }
}

// ═════════════════════════════════════════════
//  Header
// ═════════════════════════════════════════════

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primary, primary.withAlpha(180)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.settings_rounded,
              color: theme.colorScheme.onPrimary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تنظیمات',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'شخصی‌سازی برنامه',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
//  Section label
// ═════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
//  Drawer item
// ═════════════════════════════════════════════

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(140),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  // در RTL، Material این آیکون را خودکار برمی‌گرداند
                  // و به سمت «جلو» (چپ) اشاره می‌کند.
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
//  Footer
// ═════════════════════════════════════════════

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
          ),
          const SizedBox(width: 6),
          Text(
            'Guysgram',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}