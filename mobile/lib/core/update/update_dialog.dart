import 'package:flutter/material.dart';
import 'update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
    });

    final file = await UpdateService.instance.downloadApk(
      url: widget.updateInfo.downloadUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;

    if (file == null) {
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطا در دانلود به‌روزرسانی')),
      );
      return;
    }

    final success = await UpdateService.instance.installApk(file);

    if (!mounted) return;
    setState(() => _downloading = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'برای نصب، به تنظیمات بروید و اجازه نصب از منابع نامعلوم را فعال کنید.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.system_update_alt_rounded,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('به‌روزرسانی جدید')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('نسخه جدید: ', style: theme.textTheme.bodyMedium),
                  Text(
                    'v${widget.updateInfo.latestVersion}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatBytes(widget.updateInfo.fileSize),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'نسخه فعلی: v${widget.updateInfo.currentVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              if (_downloading) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  'در حال دانلود... ${(_progress * 100).toInt()}%',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text('تغییرات:', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.updateInfo.changelog,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_downloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بعداً'),
            ),
          if (!_downloading)
            ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('دانلود و نصب'),
            ),
        ],
      ),
    );
  }
}