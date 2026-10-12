import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سرویس شخصی‌سازی ایموجی‌های ری‌اکشن (per-device).
///
/// - ذخیره‌سازی: SharedPreferences (محلی). هیچ چیزی به سرور ارسال نمی‌شود.
/// - کلید نسخه‌دار: `reaction_emojis_v1` — برای migration ساختار داده در آینده.
/// - Singleton + ChangeNotifier: مطابق الگوی `MediaDownloadManager` و
///   `NetworkMonitor` در همین پروژه.
///
/// قوانین:
///   - حداکثر [maxEmojis] = 12
///   - حداقل [minEmojis] = 1 (حذف آخرین ایموجی ممنوع)
///   - بدون تکرار (duplicate)
class ReactionEmojiSettings extends ChangeNotifier {
  static final ReactionEmojiSettings instance =
      ReactionEmojiSettings._internal();
  ReactionEmojiSettings._internal();

  static const String _prefsKey = 'reaction_emojis_v1';
  static const int maxEmojis = 12;
  static const int minEmojis = 1;

  /// لیست پیش‌فرض — همان چیزی که قبل از این تغییر hardcode بود.
  static const List<String> defaultEmojis = [
    '👍', '❤️', '😂', '🔥', '😢', '👏', '🎉', '💯',
  ];

  List<String> _emojis = List<String>.from(defaultEmojis);
  bool _initialized = false;

  List<String> get emojis => List<String>.unmodifiable(_emojis);
  bool get isInitialized => _initialized;

  bool get canAddMore => _emojis.length < maxEmojis;
  bool get canRemove => _emojis.length > minEmojis;

  bool get isDefault {
    if (_emojis.length != defaultEmojis.length) return false;
    for (int i = 0; i < _emojis.length; i++) {
      if (_emojis[i] != defaultEmojis[i]) return false;
    }
    return true;
  }

  /// بارگذاری از SharedPreferences. اگر داده‌ای نبود، پیش‌فرض حفظ می‌شود.
  /// این متد باید یک بار در `main()` قبل از `runApp` صدا زده شود.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = decoded
              .whereType<String>()
              .where((e) => e.trim().isNotEmpty)
              .toList();
          if (loaded.isNotEmpty) {
            _emojis = loaded.take(maxEmojis).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[ReactionEmojiSettings] load failed: $e');
      _emojis = List<String>.from(defaultEmojis);
    }
    _initialized = true;
    notifyListeners();
  }

  /// افزودن ایموجی جدید. false اگر تکراری باشد یا سقف پر باشد.
  Future<bool> addEmoji(String emoji) async {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return false;
    if (_emojis.length >= maxEmojis) return false;
    if (_emojis.contains(trimmed)) return false;

    _emojis.add(trimmed);
    notifyListeners();
    await _persist();
    return true;
  }

  /// حذف ایموجی. false اگر لیست به حداقل رسیده باشد یا ایموجی موجود نباشد.
  Future<bool> removeEmoji(String emoji) async {
    if (_emojis.length <= minEmojis) return false;
    final removed = _emojis.remove(emoji);
    if (!removed) return false;

    notifyListeners();
    await _persist();
    return true;
  }

  /// جابجایی ایموجی.
  ///
  /// ⚠️ این متد با `ReorderableListView.onReorderItem` (API جدید Flutter 3.41+)
  /// هماهنگ است. در این API، `newIndex` از قبل برای آیتم حذف‌شده تنظیم شده
  /// است؛ یعنی مقدار `newIndex` همان موقعیت نهایی در لیست پس از حذف است.
  /// پس ما خودمان نباید دوباره اصلاح کنیم.
  Future<void> reorderEmojis(int oldIndex, int newIndex) async {
    final len = _emojis.length;
    if (oldIndex < 0 || oldIndex >= len) return;
    if (newIndex < 0 || newIndex >= len) return;
    if (oldIndex == newIndex) return;

    final item = _emojis.removeAt(oldIndex);
    _emojis.insert(newIndex, item);

    notifyListeners();
    await _persist();
  }

  /// بازگردانی به لیست پیش‌فرض.
  Future<void> resetToDefault() async {
    _emojis = List<String>.from(defaultEmojis);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_emojis));
    } catch (e) {
      debugPrint('[ReactionEmojiSettings] persist failed: $e');
    }
  }
}