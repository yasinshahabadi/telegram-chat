import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _launching = false;

  /// ✅ باز کردن لینک دانلود در مرورگر پیش‌فرض
  Future<void> _openInBrowser() async {
    if (_launching) return;
    setState(() => _launching = true);

    try {
      final uri = Uri.parse(widget.updateInfo.downloadUrl);
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      if (opened) {
        // پس از باز شدن مرورگر، دیالوگ را ببند
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('امکان باز کردن مرورگر وجود ندارد.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در باز کردن لینک: $e')),
      );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.system_update_alt_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'به‌روزرسانی جدید',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // نسخه‌ها و حجم
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نسخه جدید',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'v${widget.updateInfo.latestVersion}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'نسخه فعلی',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'v${widget.updateInfo.currentVersion}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.updateInfo.formattedSize.isNotEmpty)
                  Text(
                    'حجم فایل: ${widget.updateInfo.formattedSize}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                const SizedBox(height: 16),

                // تغییرات به صورت Markdown
                Row(
                  children: [
                    Icon(Icons.article_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'تغییرات این نسخه:',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(80),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Markdown(
                    data: widget.updateInfo.changelog,
                    shrinkWrap: true,
                    selectable: true,
                    padding: EdgeInsets.zero,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodySmall?.copyWith(height: 1.7),
                      h1: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                      h2: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      h3: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: theme.textTheme.bodySmall,
                      blockSpacing: 8,
                      code: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        backgroundColor:
                            theme.colorScheme.surface.withAlpha(150),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: theme.colorScheme.surface.withAlpha(120),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant,
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: _launching
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('بعداً'),
          ),
          ElevatedButton.icon(
            onPressed: _launching ? null : _openInBrowser,
            icon: _launching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.open_in_browser_rounded, size: 18),
            label: const Text('دانلود از مرورگر'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(140, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}