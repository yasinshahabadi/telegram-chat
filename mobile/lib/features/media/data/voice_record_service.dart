import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'media_local_storage.dart';

/// سرویس مدیریت ضبط پیام‌های صوتی (ویس)
class VoiceRecordService extends ChangeNotifier {
  final AudioRecorder _audioRecorder;
  final MediaLocalStorage _localStorage;

  bool _isRecording = false;
  int _durationSeconds = 0;
  Timer? _timer;
  String? _currentRecordingPath;

  VoiceRecordService({
    AudioRecorder? audioRecorder,
    MediaLocalStorage? localStorage,
  })  : _audioRecorder = audioRecorder ?? AudioRecorder(),
        _localStorage = localStorage ?? MediaLocalStorage();

  bool get isRecording => _isRecording;
  int get durationSeconds => _durationSeconds;
  String? get currentRecordingPath => _currentRecordingPath;

  /// قالب‌بندی زمان ضبط به دقیقه و ثانیه (مثلاً 00:25)
  String get formattedDuration {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// شروع ضبط صدا با تنظیمات بهینه AAC
  Future<bool> startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        return false;
      }

      final mediaDir = await _localStorage.mediaDirectory;
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final targetPath = p.join(mediaDir.path, fileName);

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: targetPath,
      );

      _isRecording = true;
      _currentRecordingPath = targetPath;
      _durationSeconds = 0;
      notifyListeners();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _durationSeconds++;
        notifyListeners();
      });

      return true;
    } catch (e) {
      _cleanup();
      return false;
    }
  }

  /// توقف ضبط و بازگرداندن مسیر فایل ضبط‌شده
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _audioRecorder.stop();
      final recordedPath = path ?? _currentRecordingPath;
      _cleanup();
      return recordedPath;
    } catch (e) {
      _cleanup();
      return null;
    }
  }

  /// لغو ضبط و حذف فایل ناتمام از حافظه
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();
      final filePath = path ?? _currentRecordingPath;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {} finally {
      _cleanup();
    }
  }

  void _cleanup() {
    _isRecording = false;
    _durationSeconds = 0;
    _currentRecordingPath = null;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    _audioRecorder.dispose();
    super.dispose();
  }
}
