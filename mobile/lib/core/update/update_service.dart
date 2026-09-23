import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String changelog;
  final String downloadUrl;
  final int fileSize;
  final bool isUpdateAvailable;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.fileSize,
    required this.isUpdateAvailable,
  });
}

class UpdateService {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  // ⚠️ این دو مقدار را با اطلاعات ریپوی خودتان جایگزین کنید
  static const String githubOwner = 'yasinshahabadi';
  static const String githubRepo = 'telegram-chat';

  /// بررسی وجود نسخه جدید در GitHub Releases
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      final body = data['body'] as String? ?? 'بدون توضیحات';
      final assets = (data['assets'] as List?) ?? [];

      Map<String, dynamic>? apkAsset;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkAsset = asset as Map<String, dynamic>;
          break;
        }
      }

      if (apkAsset == null) return null;

      final downloadUrl = apkAsset['browser_download_url'] as String? ?? '';
      final fileSize = apkAsset['size'] as int? ?? 0;

      final isNewer = _isNewerVersion(tagName, currentVersion);

      return UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        changelog: body,
        downloadUrl: downloadUrl,
        fileSize: fileSize,
        isUpdateAvailable: isNewer,
      );
    } catch (e) {
      debugPrint('[Update] Check failed: $e');
      return null;
    }
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// دانلود APK با گزارش پیشرفت
  Future<File?> downloadApk({
    required String url,
    required Function(double) onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/update.apk';
      final apkFile = File(apkPath);

      if (await apkFile.exists()) await apkFile.delete();

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) return null;

      final totalBytes = response.contentLength ?? 0;
      final sink = apkFile.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress(received / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      onProgress(1.0);
      return apkFile;
    } catch (e) {
      debugPrint('[Update] Download failed: $e');
      return null;
    }
  }

  /// نصب APK
  Future<bool> installApk(File apkFile) async {
    try {
      final result = await OpenFilex.open(apkFile.path);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('[Update] Install failed: $e');
      return false;
    }
  }
}