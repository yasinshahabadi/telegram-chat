// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/cache_service.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final VoidCallback onClearCache;

  const SettingsScreen({
    super.key,
    required this.currentUser,
    required this.onClearCache,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const MethodChannel _vibrateChannel = MethodChannel('app.telegram_chat/vibrate');

  Map<String, int> _cacheSizes = {
    'photos': 0,
    'videos': 0,
    'audios': 0,
    'documents': 0,
    'avatars': 0,
    'total': 0,
  };
  bool _isLoadingCache = true;
  String _appVersion = "1.0.0";
  String? _cachedAvatarPath;

  @override
  void initState() {
    super.initState();
    _loadCacheData();
    _loadAppInfo();
  }

  void _triggerVibration({int duration = 40}) {
    try {
      _vibrateChannel.invokeMethod('vibrate', {'duration': duration});
    } catch (_) {
      HapticFeedback.vibrate();
    }
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  Future<void> _loadCacheData() async {
    final breakdown = await CacheService.getCacheBreakdown();
    final avatarPath = await CacheService.getOrFetchAvatar(widget.currentUser['telegram_id']?.toString());
    if (mounted) {
      setState(() {
        _cacheSizes = breakdown;
        _cachedAvatarPath = avatarPath;
        _isLoadingCache = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF182533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("پاکسازی کش", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          "آیا مطمئن هستید که می‌خواهید تمام فایل‌ها، عکس‌ها و داده‌های موقت کش‌شده را پاک کنید؟\n(پیام‌های چت حذف نمی‌شوند).",
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("انصراف", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("پاکسازی کامل", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _triggerVibration(duration: 60);
      setState(() => _isLoadingCache = true);
      await CacheService.clearAllCache();
      widget.onClearCache();
      await _loadCacheData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF242F3D),
            content: Text("حافظه کش برنامه با موفقیت پاکسازی شد", style: TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myName = widget.currentUser['full_name'] ?? 'کاربر';
    final tgId = widget.currentUser['telegram_id']?.toString() ?? '';
    final username = widget.currentUser['username'] ?? '';

    final totalCache = _cacheSizes['total'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1621),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17212B),
        elevation: 1,
        title: const Text("تنظیمات و حافظه", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // ۱. کارت مشخصات کاربر
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF17212B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF50A2E9),
                  child: ClipOval(
                    child: _cachedAvatarPath != null && File(_cachedAvatarPath!).existsSync()
                        ? Image.file(File(_cachedAvatarPath!), width: 56, height: 56, fit: BoxFit.cover)
                        : Text(myName.isNotEmpty ? myName[0].toUpperCase() : '👤',
                            style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(myName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(
                        username.isNotEmpty ? "@$username" : "شناسه تلگرام: $tgId",
                        style: const TextStyle(fontSize: 12, color: Color(0xFF50A2E9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ۲. بخش مدیریت داده و کش
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              "مدیریت کش و حافظه (مطابق سرور ۲۴ ساعته)",
              style: TextStyle(fontSize: 12, color: Color(0xFF50A2E9), fontWeight: FontWeight.bold),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF17212B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("کل حافظه اشغال‌شده:", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    _isLoadingCache
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF50A2E9)))
                        : Text(
                            _formatBytes(totalCache),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF50A2E9)),
                          ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.white10),
                const SizedBox(height: 12),

                _buildStorageRow(Icons.image_outlined, "کش تصاویر", _cacheSizes['photos'] ?? 0, const Color(0xFF50A2E9)),
                _buildStorageRow(Icons.videocam_outlined, "کش ویدیوها", _cacheSizes['videos'] ?? 0, Colors.purpleAccent),
                _buildStorageRow(Icons.audiotrack_outlined, "کش موزیک و ویس‌ها", _cacheSizes['audios'] ?? 0, Colors.tealAccent),
                _buildStorageRow(Icons.insert_drive_file_outlined, "فایل‌ها و اسناد", _cacheSizes['documents'] ?? 0, Colors.orangeAccent),
                _buildStorageRow(Icons.account_circle_outlined, "کش آواتارهای تلگرام", _cacheSizes['avatars'] ?? 0, Colors.pinkAccent),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: totalCache > 0 ? const Color(0xFF2B5278) : Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: totalCache > 0 ? _confirmClearCache : null,
                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: const Text("پاکسازی حافظه کش", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ۳. اطلاعات نسخه
          Center(
            child: Text(
              "Guysgram Mobile • v$_appVersion\nهماهنگ‌شده با کلودفلر و تلگرام",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white30, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageRow(IconData icon, String title, int bytes, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.white))),
          Text(_formatBytes(bytes), style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}