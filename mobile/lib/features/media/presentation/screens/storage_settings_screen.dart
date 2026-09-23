import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/media/data/media_download_manager.dart';
import 'package:telegram_chat_mobile/features/media/data/media_local_storage.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  final MediaLocalStorage _storage = MediaLocalStorage();

  int _totalSize = 0;
  Map<String, int> _sizes = {};
  int _fileCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final total = await _storage.getTotalSize();
    final sizes = await _storage.getSizeByCategory();
    final count = await _storage.getFileCount();
    if (!mounted) return;
    setState(() {
      _totalSize = total;
      _sizes = sizes;
      _fileCount = count;
      _loading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _clearCategory(String category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌سازی'),
        content: Text('همه فایل‌های دسته "${_label(category)}" پاک شوند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
        ],
      ),
    );
    if (confirm != true) return;
    await _storage.clearByCategory(category);
    await _load();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌سازی همه فایل‌ها'),
        content: const Text('تمام فایل‌های ذخیره‌شده پاک شوند؟ این عمل قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاک کن'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _storage.clearAll();
    await _load();
  }

  String _label(String cat) {
    switch (cat) {
      case 'photo': return 'عکس‌ها';
      case 'video': return 'ویدیوها';
      case 'voice': return 'پیام‌های صوتی';
      case 'audio': return 'فایل‌های صوتی';
      case 'document': return 'اسناد';
      default: return cat;
    }
  }

  IconData _icon(String cat) {
    switch (cat) {
      case 'photo': return Icons.image_rounded;
      case 'video': return Icons.videocam_rounded;
      case 'voice': return Icons.mic_rounded;
      case 'audio': return Icons.music_note_rounded;
      case 'document': return Icons.insert_drive_file_rounded;
      default: return Icons.folder_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxBytes = MediaLocalStorage.maxCacheBytes;
    final percent = maxBytes > 0 ? (_totalSize / maxBytes).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت حافظه'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // کارت حجم کل
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withAlpha(80),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('حجم مصرفی',
                                style: theme.textTheme.titleMedium),
                            Text('$_fileCount فایل',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _formatBytes(_totalSize),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.onSurface.withAlpha(30),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('از ${_formatBytes(maxBytes)}',
                                style: theme.textTheme.bodySmall),
                            Text('${(percent * 100).toInt()}%',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Text('دسته‌بندی', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),

                // کارت‌های دسته‌بندی
                ...['photo', 'video', 'voice', 'audio', 'document'].map((cat) {
                  final size = _sizes[cat] ?? 0;
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(_icon(cat), color: theme.colorScheme.primary),
                      ),
                      title: Text(_label(cat)),
                      subtitle: Text(_formatBytes(size)),
                      trailing: size > 0
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _clearCategory(cat),
                            )
                          : null,
                    ),
                  );
                }),

                const SizedBox(height: 24),

                // دکمه پاک‌سازی همه
                OutlinedButton.icon(
                  onPressed: _totalSize > 0 ? _clearAll : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('پاک‌سازی همه فایل‌ها'),
                ),

                const SizedBox(height: 24),

                // توضیح
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: theme.colorScheme.onSurfaceVariant, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'فایل‌های مدیا فقط زمانی ذخیره می‌شوند که شما روی دکمه دانلود بزنید. با فعال بودن محدودیت ۲۰۰ مگابایت، فایل‌های قدیمی‌تر به‌صورت خودکار پاک می‌شوند.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
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