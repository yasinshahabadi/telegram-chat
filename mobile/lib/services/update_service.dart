// lib/services/update_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;
  final int fileSize;

  AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSize,
  });
}

class GitHubUpdateService {
  // آدرس ریپازیتوری شما در گیت‌هاب
  static const String repoOwner = "yasinshahabadi";
  static const String repoName = "telegram-chat";

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final url = Uri.parse("https://api.github.com/repos/$repoOwner/$repoName/releases/latest");
      final response = await http.get(url, headers: {
        "Accept": "application/vnd.github.v3+json",
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String tagName = (data['tag_name'] ?? '').toString().trim();
        // حذف پیشوند v در صورت وجود (مثلاً v1.0.1 -> 1.0.1)
        final cleanTagName = tagName.startsWith('v') ? tagName.substring(1) : tagName;

        if (_isNewerVersion(cleanTagName, currentVersion)) {
          final List assets = data['assets'] ?? [];
          // پیدا کردن فایل APK در میان فایل‌های ضمیمه‌شده
          final apkAsset = assets.firstWhere(
            (asset) => (asset['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return AppUpdateInfo(
              latestVersion: cleanTagName,
              currentVersion: currentVersion,
              releaseNotes: data['body'] ?? 'بهبود عملکرد و رفع ایرادات برنامه.',
              downloadUrl: apkAsset['browser_download_url'],
              fileSize: apkAsset['size'] ?? 0,
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Update check error: $e");
    }
    return null;
  }

  // مقایسه نگارش نسخه‌ها (مثلاً 1.0.1 بزرگتر از 1.0.0 است)
  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (var i = 0; i < latestParts.length; i++) {
        final cur = i < currentParts.length ? currentParts[i] : 0;
        if (latestParts[i] > cur) return true;
        if (latestParts[i] < cur) return false;
      }
    } catch (_) {}
    return false;
  }

  // دانلود در پس‌زمینه با گزارش پیشرفت و اجرای فایل نصبی
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    required String fileName,
    required void Function(double progress, int bytesDownloaded, int totalBytes) onProgress,
    required VoidCallback onCompleted,
    required void Function(String error) onError,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;
      List<int> bytes = [];

      final tempDir = await getTemporaryDirectory();
      final filePath = "${tempDir.path}/$fileName";
      final file = File(filePath);

      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          final progress = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(progress, downloadedBytes, totalBytes);
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      onCompleted();

      // باز کردن پنجره استاندارد نصب APK در اندروید
      await OpenFilex.open(filePath);
    } catch (e) {
      onError("خطا در دانلود یا نصب نسخه جدید: $e");
    }
  }
}