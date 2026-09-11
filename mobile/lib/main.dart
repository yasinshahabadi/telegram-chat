// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import 'config.dart';
import 'models/chat_message.dart';
import 'services/notification_service.dart';
import 'services/foreground_service.dart';

List<CameraDescription> _availableCameras = [];

// کلاس اختصاصی ارسال چندبخشی با گزارش درصد پیشرفت زنده
class ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes)? onProgress;

  ProgressMultipartRequest(super.method, super.url, {this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    if (onProgress == null) return byteStream;

    final total = contentLength;
    int bytesSent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytesSent += data.length;
        onProgress!(bytesSent, total);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF17212B),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0E1621),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    _availableCameras = await availableCameras();
  } catch (_) {}

  ForegroundServiceManager.init();

  runApp(const TelegramChatApp());
}

class TelegramChatApp extends StatelessWidget {
  const TelegramChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'گفتگوی گروه',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1621),
        primaryColor: const Color(0xFF50A2E9),
        fontFamily: 'Roboto',
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fa', 'IR')],
      locale: const Locale('fa', 'IR'),
      home: const ChatHomeScreen(),
    );
  }
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> with WidgetsBindingObserver {
  static const MethodChannel _vibrateChannel = MethodChannel('app.telegram_chat/vibrate');

  String? _sessionToken;
  String? _fingerprint;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  String _statusMessage = "در حال بارگذاری...";
  Timer? _authPollTimer;
  Timer? _pollingTimer;
  Timer? _pingTimer;

  WebSocketChannel? _wsChannel;
  bool _isConnected = false;
  int _onlineUsersCount = 0;
  String? _typingStatus;
  Timer? _typingTimer;
  bool _isAppResumed = true;

  final List<ChatMessage> _messages = [];
  final Set<String> _seenMessageIds = {};
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _msgFocusNode = FocusNode();

  // بهینه‌سازی دکمه ارسال
  bool _hasTextContent = false;

  // تولتیپ شناور تلگرام
  String? _floatingHintText;
  Timer? _floatingHintTimer;

  // گزارش زنده درصد آپلود
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  int _uploadBytesSent = 0;
  int _uploadTotalBytes = 0;

  // پلیر و صوت ایزوله‌شده
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingMsgId;
  PlayerState _playerState = PlayerState.stopped;
  final ValueNotifier<Duration> _audioPosNotifier = ValueNotifier(Duration.zero);
  Duration _audioDuration = Duration.zero;

  // وضعیت دانلود مدیا
  final Set<String> _downloadedMediaIds = {};
  final Set<String> _downloadingMediaIds = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, int> _downloadedBytes = {};
  final Map<String, String> _localMediaPaths = {};
  final Map<String, http.Client> _activeClients = {};

  // ضبط ویس و ویدیو مسیج
  late final AudioRecorder _audioRecorder;
  bool _isRecordingAudio = false;
  int _audioRecordSeconds = 0;
  Timer? _audioRecordTimer;

  bool _isVideoNoteMode = false;
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;
  bool _isRecordingVideoNote = false;
  int _videoRecordSeconds = 0;
  Timer? _videoRecordTimer;
  bool _isSwitchingCamera = false;

  // قفل کردن ضبط تلگرام (Lock Mode)
  bool _isRecordingLocked = false;

  // کیبورد ایموجی
  bool _showEmojiKeyboard = false;

  ChatMessage? _replyTarget;
  ChatMessage? _editingMessage;
  ChatMessage? _pinnedMessage;
  File? _selectedAttachment;
  String? _highlightedMessageId;
  int _avatarCacheBuster = DateTime.now().millisecondsSinceEpoch;

  static const List<Color> tgColors = [
    Color(0xFFE5823D),
    Color(0xFF4FAE4E),
    Color(0xFF50A2E9),
    Color(0xFFE55B8A),
    Color(0xFFA66ED8),
    Color(0xFF00BFA5),
    Color(0xFFE5A83D),
  ];

  Color _getUserColor(String name) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return tgColors[hash.abs() % tgColors.length];
  }

  void _triggerVibration({int duration = 50}) {
    try {
      _vibrateChannel.invokeMethod('vibrate', {'duration': duration});
    } catch (_) {
      HapticFeedback.vibrate();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showFloatingHint(String text) {
    setState(() => _floatingHintText = text);
    _floatingHintTimer?.cancel();
    _floatingHintTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _floatingHintText = null);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioRecorder = AudioRecorder();

    _msgController.addListener(() {
      final has = _msgController.text.trim().isNotEmpty;
      if (has != _hasTextContent) {
        setState(() => _hasTextContent = has);
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      _audioPosNotifier.value = pos;
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      _audioDuration = dur;
    });

    NotificationService().init(onNotificationTap: (messageId) {
      if (messageId != null) {
        _scrollToMessage(messageId);
      }
    });

    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authPollTimer?.cancel();
    _pollingTimer?.cancel();
    _pingTimer?.cancel();
    _typingTimer?.cancel();
    _audioRecordTimer?.cancel();
    _videoRecordTimer?.cancel();
    _floatingHintTimer?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _cameraController?.dispose();
    _wsChannel?.sink.close();
    _msgController.dispose();
    _msgFocusNode.dispose();
    _scrollController.dispose();
    _audioPosNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = (state == AppLifecycleState.resumed);
    ForegroundServiceManager.setAppLifecycle(_isAppResumed);

    if (_isAppResumed) {
      _sendPresence(true);
      _fetchLatestMessages();
      _markVisibleUnreadMessages();
    } else {
      _sendPresence(false);
    }
  }

  void _sendPresence(bool isOnline) {
    if (_wsChannel != null && _isConnected) {
      _wsChannel!.sink.add(jsonEncode({
        "type": "presence",
        "status": isOnline ? "online" : "offline"
      }));
    }
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString('chat_token');
    if (_sessionToken == null) {
      _sessionToken = const Uuid().v4().replaceAll('-', '');
      await prefs.setString('chat_token', _sessionToken!);
    }

    _fingerprint = prefs.getString('fingerprint');
    if (_fingerprint == null) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _fingerprint = "DEVICE_${androidInfo.model}_${androidInfo.id}".replaceAll(" ", "_");
      } else {
        _fingerprint = "DEVICE_${const Uuid().v4().substring(0, 8)}";
      }
      await prefs.setString('fingerprint', _fingerprint!);
    }

    await _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/api/auth/verify-device"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "fingerprint": _fingerprint,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['status'] == 'ok') {
        _authPollTimer?.cancel();
        setState(() {
          _currentUser = data['user'];
          _isLoading = false;
          _avatarCacheBuster = DateTime.now().millisecondsSinceEpoch;
        });

        ForegroundServiceManager.start(
          userName: data['user']['full_name'] ?? 'کاربر',
          userId: data['user']['id'],
          tgId: data['user']['telegram_id']?.toString(),
        );

        _connectWebSocket();
        _fetchInitialMessages();
        _startPolling();
      } else if (data['status'] == 'pending') {
        setState(() {
          _isLoading = false;
          _statusMessage = "درخواست شما ثبت شده و در انتظار تایید مدیر در تلگرام است...";
        });
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = "جهت استفاده از برنامه، وارد حساب تلگرام شوید.";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "خطا در اتصال به سرور. آدرس دامنه در config.dart را بررسی کنید.";
      });
    }
  }

  void _openTelegramLogin() async {
    final Uri tgAppUri = Uri.parse("tg://resolve?domain=${AppConfig.botUsername}&start=auth_$_sessionToken");
    final Uri webUri = Uri.parse("https://t.me/${AppConfig.botUsername}?start=auth_$_sessionToken");

    try {
      if (await canLaunchUrl(tgAppUri)) {
        await launchUrl(tgAppUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
      _authPollTimer?.cancel();
      _authPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkAuthStatus());
    } catch (_) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF182533),
        title: const Text("خروج از حساب", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text("آیا مطمئن هستید که می‌خواهید خارج شوید؟", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("انصراف")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("خروج", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await http.post(
          Uri.parse("${AppConfig.baseUrl}/api/auth/logout"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"sessionToken": _sessionToken}),
        );
      } catch (_) {}

      ForegroundServiceManager.stop();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_token');
      _wsChannel?.sink.close();
      setState(() {
        _currentUser = null;
        _messages.clear();
        _statusMessage = "خارج شدید.";
      });
      _initApp();
    }
  }

  void _connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));

      _wsChannel!.stream.listen((message) {
        final data = jsonDecode(message);
        _handleWsEvent(data);
      }, onDone: () {
        if (mounted) {
          setState(() => _isConnected = false);
          Future.delayed(const Duration(seconds: 3), () {
            if (_currentUser != null) _connectWebSocket();
          });
        }
      }, onError: (_) {
        if (mounted) setState(() => _isConnected = false);
      });

      _wsChannel!.sink.add(jsonEncode({
        "type": "identify",
        "userName": _currentUser?['full_name'] ?? 'کاربر',
        "userId": _currentUser?['id'],
        "tgId": _currentUser?['telegram_id']
      }));

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        if (_wsChannel != null && _isConnected) {
          _wsChannel!.sink.add(jsonEncode({"type": "presence", "status": _isAppResumed ? "online" : "offline"}));
        }
      });

      setState(() => _isConnected = true);
    } catch (_) {
      setState(() => _isConnected = false);
    }
  }

  void _handleWsEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'new_message' && data['message'] != null) {
      final msg = ChatMessage.fromJson(data['message']);
      if (!_seenMessageIds.contains(msg.id)) {
        _seenMessageIds.add(msg.id);
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();

        if (msg.timestamp > 0) {
          ForegroundServiceManager.syncLastMessageTime(msg.timestamp);
        }

        if (_isAppResumed) {
          _markAsRead([msg.id]);
        }
      }
    } else if (type == 'messages_read' && data['messageIds'] != null) {
      final List ids = data['messageIds'];
      final int? readAtTime = data['readAt'];
      setState(() {
        for (var m in _messages) {
          if (ids.contains(m.id)) {
            m.isRead = 1;
            if (readAtTime != null) m.readAt = readAtTime;
          }
        }
      });
    } else if (type == 'reaction_updated') {
      final msgId = data['messageId'];
      dynamic rx = data['reactions'];
      if (rx is String) {
        try {
          rx = jsonDecode(rx);
        } catch (_) {}
      }
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1 && rx is Map) {
          Map<String, List<String>> newRx = {};
          rx.forEach((k, v) {
            if (v is List) newRx[k.toString()] = v.map((e) => e.toString()).toList();
          });
          _messages[idx].reactions = newRx;
        }
      });
    } else if (type == 'message_edited') {
      final msgId = data['messageId'];
      final newText = data['text'] ?? '';
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) {
          _messages[idx].text = newText;
          _messages[idx].isEdited = true;
        }
      });
    } else if (type == 'message_pinned' && data['message'] != null) {
      setState(() {
        _pinnedMessage = ChatMessage.fromJson(data['message']);
      });
    } else if (type == 'message_unpinned') {
      setState(() {
        _pinnedMessage = null;
      });
    } else if (type == 'online_users') {
      final List users = data['users'] ?? [];
      setState(() {
        _onlineUsersCount = users.length;
      });
    } else if (type == 'typing') {
      final name = data['userName'] ?? 'شخصی';
      setState(() {
        _typingStatus = "$name در حال نوشتن...";
      });
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _typingStatus = null);
      });
    }
  }

  void _markAsRead(List<String> ids) {
    if (_wsChannel != null && _isConnected && ids.isNotEmpty && _isAppResumed) {
      _wsChannel!.sink.add(jsonEncode({
        "type": "mark_read",
        "messageIds": ids,
      }));
    }
  }

  void _markVisibleUnreadMessages() {
    if (!_isAppResumed) return;
    final myName = _currentUser?['full_name'] ?? '';
    final unreadIds = _messages
        .where((m) => m.isRead == 0 && m.senderName != myName)
        .map((m) => m.id)
        .toList();
    if (unreadIds.isNotEmpty) {
      _markAsRead(unreadIds);
    }
  }

  Future<void> _fetchInitialMessages() async {
    try {
      final res = await http.get(Uri.parse("${AppConfig.baseUrl}/api/messages?limit=40"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['messages'] ?? [];
        if (data['pinned'] != null) {
          _pinnedMessage = ChatMessage.fromJson(data['pinned']);
        }
        _messages.clear();
        _seenMessageIds.clear();
        for (var item in list) {
          final m = ChatMessage.fromJson(item);
          _seenMessageIds.add(m.id);
          _messages.add(m);
        }
        setState(() {});
        _scrollToBottom();
        _markVisibleUnreadMessages();

        if (_messages.isNotEmpty) {
          ForegroundServiceManager.syncLastMessageTime(_messages.last.timestamp);
        }
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchLatestMessages());
  }

  Future<void> _fetchLatestMessages() async {
    if (_messages.isEmpty) return;
    final lastTime = _messages.last.timestamp;
    try {
      final res = await http.get(Uri.parse("${AppConfig.baseUrl}/api/messages?since=$lastTime"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['messages'] ?? [];
        bool added = false;
        for (var item in list) {
          final m = ChatMessage.fromJson(item);
          if (!_seenMessageIds.contains(m.id)) {
            _seenMessageIds.add(m.id);
            _messages.add(m);
            added = true;
          }
        }
        if (added) {
          setState(() {});
          _scrollToBottom();
          _markVisibleUnreadMessages();
          ForegroundServiceManager.syncLastMessageTime(_messages.last.timestamp);
        }
      }
    } catch (_) {}
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();

    if (_editingMessage != null) {
      if (text.isEmpty) return;
      _wsChannel?.sink.add(jsonEncode({
        "type": "edit_message",
        "messageId": _editingMessage!.id,
        "newText": text,
      }));
      setState(() => _editingMessage = null);
      _msgController.clear();
      return;
    }

    // ارسال پیوست چه با متن و چه بدون متن
    if (_selectedAttachment != null) {
      final fileToSend = _selectedAttachment!;
      setState(() {
        _selectedAttachment = null;
        _replyTarget = null;
      });
      _msgController.clear();
      _uploadMedia(file: fileToSend, caption: text);
      return;
    }

    if (text.isEmpty || _wsChannel == null) return;

    Map<String, dynamic>? replyData;
    if (_replyTarget != null) {
      replyData = {
        "id": _replyTarget!.id,
        "name": _replyTarget!.senderName,
        "text": _replyTarget!.text.isNotEmpty ? _replyTarget!.text : (_replyTarget!.mediaType ?? 'مدیا'),
        "tgMsgId": _replyTarget!.tgMsgId,
      };
    }

    _wsChannel!.sink.add(jsonEncode({
      "type": "chat_message",
      "text": text,
      "replyTo": replyData,
    }));

    _msgController.clear();
    setState(() => _replyTarget = null);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'jpeg', 'webp', 'mp4', 'mov', 'mp3', 'ogg', 'm4a', 'pdf', 'zip', 'doc', 'docx'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final length = await file.length();
      if (length > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("حجم فایل نباید بیش از ۲۰ مگابایت باشد")),
          );
        }
        return;
      }
      setState(() {
        _selectedAttachment = file;
      });
    }
  }

  MediaType _resolveMediaType(String path, {String? customType}) {
    if (customType == "voice") return MediaType('audio', 'm4a');
    if (customType == "video_note") return MediaType('video', 'mp4');

    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'ogg':
        return MediaType('audio', 'ogg');
      case 'm4a':
        return MediaType('audio', 'mp4');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  // آپلود هوشمند با نمایش نوار پیشرفت زنده و رعایت سقف ۲۰ مگابایت برای کل برنامه
  Future<void> _uploadMedia({required File file, String caption = '', String? customType}) async {
    try {
      final fileSize = await file.length();
      if (fileSize > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("حجم فایل بیش از ۲۰ مگابایت است و ارسال نشد")),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
        _uploadBytesSent = 0;
        _uploadTotalBytes = fileSize;
      });

      final uri = Uri.parse("${AppConfig.baseUrl}/api/upload");
      final request = ProgressMultipartRequest(
        "POST",
        uri,
        onProgress: (bytesSent, totalBytes) {
          if (mounted) {
            setState(() {
              _uploadBytesSent = bytesSent;
              _uploadTotalBytes = totalBytes;
              if (totalBytes > 0) {
                _uploadProgress = (bytesSent / totalBytes).clamp(0.0, 1.0);
              }
            });
          }
        },
      );

      request.fields['sessionToken'] = _sessionToken ?? '';
      request.fields['caption'] = caption;
      if (customType != null) {
        request.fields['mediaType'] = customType;
      }

      if (_replyTarget != null) {
        request.fields['replyTo'] = jsonEncode({
          "id": _replyTarget!.id,
          "name": _replyTarget!.senderName,
          "text": _replyTarget!.text.isNotEmpty ? _replyTarget!.text : (_replyTarget!.mediaType ?? 'مدیا'),
          "tgMsgId": _replyTarget!.tgMsgId,
        });
      }

      final mime = _resolveMediaType(file.path, customType: customType);
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: mime,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("خطا در ارسال مدیا: ${response.statusCode}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطای شبکه در آپلود فایل")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _startRecordingAudio() async {
    if (await _audioRecorder.hasPermission()) {
      _triggerVibration(duration: 40);
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: filePath,
      );

      setState(() {
        _isRecordingAudio = true;
        _isRecordingLocked = false;
        _audioRecordSeconds = 0;
      });

      _audioRecordTimer?.cancel();
      _audioRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _audioRecordSeconds++);
      });
    }
  }

  Future<void> _stopRecordingAudio({bool cancel = false}) async {
    _audioRecordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecordingAudio = false;
      _isRecordingLocked = false;
    });

    if (!cancel && path != null) {
      _triggerVibration(duration: 50);
      await _uploadMedia(file: File(path), customType: "voice");
    }
  }

  Future<void> _initCamera([int? cameraIndex]) async {
    if (_availableCameras.isEmpty) return;
    _selectedCameraIndex = cameraIndex ?? 0;
    _cameraController = CameraController(
      _availableCameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  // سوئیچ کاملاً امن بین دوربین‌ها بدون کرش کردن
  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2 || _isSwitchingCamera) return;
    _isSwitchingCamera = true;
    _triggerVibration(duration: 30);

    try {
      final nextIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
      final wasRecording = _isRecordingVideoNote && (_cameraController?.value.isRecordingVideo ?? false);

      if (wasRecording) {
        await _cameraController!.stopVideoRecording();
      }

      await _cameraController?.dispose();
      _cameraController = null;

      _selectedCameraIndex = nextIndex;
      final newController = CameraController(
        _availableCameras[_selectedCameraIndex],
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await newController.initialize();
      _cameraController = newController;

      if (wasRecording && mounted) {
        await _cameraController!.startVideoRecording();
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _startRecordingVideoNote() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      int frontCam = _availableCameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      await _initCamera(frontCam != -1 ? frontCam : 0);
    }

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _triggerVibration(duration: 40);
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecordingVideoNote = true;
        _isRecordingLocked = false;
        _videoRecordSeconds = 0;
      });

      _videoRecordTimer?.cancel();
      _videoRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _videoRecordSeconds++);
      });
    }
  }

  Future<void> _stopRecordingVideoNote({bool cancel = false}) async {
    _videoRecordTimer?.cancel();
    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      final file = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecordingVideoNote = false;
        _isRecordingLocked = false;
      });

      if (!cancel) {
        _triggerVibration(duration: 50);
        await _uploadMedia(file: File(file.path), customType: "video_note");
      }
    }
  }

  // استریم آنی با فال‌بک کش
  Future<void> _toggleAudioPlay(ChatMessage msg) async {
    final audioSourceUrl = _localMediaPaths[msg.id] ?? msg.mediaUrl;
    if (audioSourceUrl == null) return;

    if (_currentlyPlayingMsgId == msg.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      _triggerVibration(duration: 30);
      _currentlyPlayingMsgId = msg.id;

      try {
        if (_localMediaPaths.containsKey(msg.id)) {
          await _audioPlayer.play(DeviceFileSource(_localMediaPaths[msg.id]!));
        } else {
          await _audioPlayer.play(UrlSource(msg.mediaUrl!));
        }
      } catch (_) {
        _startDownloadingMedia(msg).then((_) {
          if (_localMediaPaths.containsKey(msg.id)) {
            _audioPlayer.play(DeviceFileSource(_localMediaPaths[msg.id]!));
          }
        });
      }
    }
  }

  void _toggleReaction(String messageId, String emoji) {
    _triggerVibration(duration: 40);
    if (_wsChannel != null && _isConnected) {
      _wsChannel!.sink.add(jsonEncode({
        "type": "toggle_reaction",
        "messageId": messageId,
        "emoji": emoji,
      }));
    }
  }

  void _showContextMenu(ChatMessage msg) {
    _triggerVibration(duration: 60);
    final myName = _currentUser?['full_name'] ?? '';
    final isMe = msg.senderName == myName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF182533),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['❤️', '👍', '👎', '🔥', '🥰', '👏', '😁'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleReaction(msg.id, emoji);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    msg.isRead == 1
                        ? "✓✓ خوانده شده در ${msg.formattedReadTime}"
                        : "✓ ارسال شده (در انتظار خوانده شدن)",
                    style: TextStyle(
                      fontSize: 12,
                      color: msg.isRead == 1 ? const Color(0xFF50A2E9) : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Color(0xFF50A2E9)),
              title: const Text("پاسخ (Reply)", style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyTarget = msg;
                  _editingMessage = null;
                });
              },
            ),
            if (isMe && msg.mediaType == null)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.amber),
                title: const Text("ویرایش (Edit)", style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingMessage = msg;
                    _replyTarget = null;
                    _msgController.text = msg.text;
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.push_pin_rounded, color: Colors.orangeAccent),
              title: const Text("سنجاق کردن (Pin)", style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _wsChannel?.sink.add(jsonEncode({
                  "type": "pin_message",
                  "messageId": msg.id,
                }));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToMessage(String targetId) {
    final cleanId = targetId.startsWith('tg_') ? targetId.replaceFirst('tg_', '') : targetId;
    final index = _messages.indexWhere((m) => m.id == cleanId || m.tgMsgId?.toString() == cleanId);

    if (index == -1) return;

    final foundMsgId = _messages[index].id;

    if (_scrollController.hasClients) {
      final targetOffset = (index / _messages.length) * _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      ).then((_) {
        _triggerVibration(duration: 50);
        setState(() => _highlightedMessageId = foundMsgId);
        Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _highlightedMessageId = null);
        });
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startDownloadingMedia(ChatMessage msg) async {
    if (msg.mediaUrl == null) return;
    final client = http.Client();
    _activeClients[msg.id] = client;

    setState(() {
      _downloadingMediaIds.add(msg.id);
      _downloadProgress[msg.id] = 0.0;
      _downloadedBytes[msg.id] = 0;
    });

    try {
      final request = http.Request('GET', Uri.parse(msg.mediaUrl!));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? (msg.mediaFileSize ?? 0);
      List<int> bytes = [];

      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
        setState(() {
          _downloadedBytes[msg.id] = bytes.length;
          if (totalBytes > 0) {
            _downloadProgress[msg.id] = (bytes.length / totalBytes).clamp(0.0, 1.0);
          }
        });
      }

      final dir = await getApplicationDocumentsDirectory();
      String ext = 'bin';
      if (msg.mediaType == 'video' || msg.mediaType == 'video_note') ext = 'mp4';
      else if (msg.mediaType == 'photo') ext = 'jpg';
      else if (msg.mediaType == 'voice') ext = 'm4a';
      else if (msg.mediaType == 'audio') ext = 'mp3';

      final fileName = msg.mediaFileName ?? "media_${msg.id.substring(0, 8)}.$ext";
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(bytes);

      setState(() {
        _localMediaPaths[msg.id] = file.path;
        _downloadingMediaIds.remove(msg.id);
        _downloadedMediaIds.add(msg.id);
        _activeClients.remove(msg.id);
      });

      _triggerVibration(duration: 45);
    } catch (_) {
      setState(() {
        _downloadingMediaIds.remove(msg.id);
        _activeClients.remove(msg.id);
      });
    }
  }

  void _cancelDownload(String msgId) {
    _activeClients[msgId]?.close();
    _activeClients.remove(msgId);
    setState(() {
      _downloadingMediaIds.remove(msgId);
      _downloadProgress.remove(msgId);
      _downloadedBytes.remove(msgId);
    });
  }

  void _openLightbox({String? url, String? localPath, required String fileName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black87,
            title: Text(fileName, style: const TextStyle(fontSize: 14)),
            actions: [
              if (url != null)
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () {
                    launchUrl(
                      Uri.parse("$url&download=1&name=${Uri.encodeComponent(fileName)}"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: localPath != null
                  ? Image.file(File(localPath), fit: BoxFit.contain)
                  : CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFF50A2E9))),
                      errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _openVideoPlayer({String? videoUrl, String? localPath, required String fileName, bool isCircular = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerModal(
          videoUrl: videoUrl,
          localPath: localPath,
          fileName: fileName,
          isCircular: isCircular,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF50A2E9))),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_rounded, size: 84, color: Color(0xFF50A2E9)),
                const SizedBox(height: 24),
                const Text(
                  "ورود به گفتگوی گروه",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _openTelegramLogin,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text("ورود از طریق تلگرام", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B5278),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final myName = _currentUser!['full_name'] ?? 'کاربر';
    final tgId = _currentUser!['telegram_id']?.toString() ?? '';

    // دکمه ارسال چه با متن و چه با فایل فوراً فعال می‌شود
    final bool canSend = _hasTextContent || _selectedAttachment != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF17212B),
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: _getUserColor(myName),
              child: ClipOval(
                child: tgId.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: "${AppConfig.baseUrl}/api/avatar?userId=$tgId&v=$_avatarCacheBuster",
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                          child: Text(myName.isNotEmpty ? myName[0].toUpperCase() : '👤',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(myName.isNotEmpty ? myName[0].toUpperCase() : '👤',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    : Text(myName.isNotEmpty ? myName[0].toUpperCase() : '👤',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    myName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _typingStatus ??
                        (_isConnected
                            ? (_onlineUsersCount > 0 ? "$_onlineUsersCount کاربر آنلاین" : "آنلاین")
                            : "در حال اتصال..."),
                    style: TextStyle(
                      fontSize: 11,
                      color: _typingStatus != null
                          ? const Color(0xFF50A2E9)
                          : (_isConnected ? const Color(0xFF4FAE4E) : Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded, color: Colors.grey),
            tooltip: "خروج",
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_pinnedMessage != null)
                GestureDetector(
                  onTap: () => _scrollToMessage(_pinnedMessage!.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: const Color(0xFF17212B).withOpacity(0.95),
                    child: Row(
                      children: [
                        const Icon(Icons.push_pin_rounded, size: 18, color: Color(0xFF50A2E9)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("پیام سنجاق شده",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF50A2E9))),
                              Text(
                                _pinnedMessage!.text.isNotEmpty
                                    ? _pinnedMessage!.text
                                    : (_pinnedMessage!.mediaType ?? 'مدیا'),
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                          onPressed: () {
                            _wsChannel?.sink.add(jsonEncode({"type": "unpin_message"}));
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              // لیست فوق روان چت با بهینه‌سازی ۱۲۰ هرتز
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  cacheExtent: 600,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg.senderName == myName;
                    return _buildMessageRow(msg, isMe, myName);
                  },
                ),
              ),

              if (_replyTarget != null || _editingMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: const Color(0xFF17212B),
                  child: Row(
                    children: [
                      Icon(
                        _editingMessage != null ? Icons.edit_rounded : Icons.reply_rounded,
                        color: _editingMessage != null ? Colors.amber : const Color(0xFF50A2E9),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editingMessage != null ? "ویرایش پیام" : _replyTarget!.senderName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _editingMessage != null ? Colors.amber : const Color(0xFF50A2E9),
                              ),
                            ),
                            Text(
                              _editingMessage != null
                                  ? _editingMessage!.text
                                  : (_replyTarget!.text.isNotEmpty
                                      ? _replyTarget!.text
                                      : (_replyTarget!.mediaType ?? 'مدیا')),
                              style: const TextStyle(fontSize: 12, color: Colors.white60),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _replyTarget = null;
                            _editingMessage = null;
                            _msgController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),

              if (_selectedAttachment != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: const Color(0xFF17212B),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, color: Color(0xFF50A2E9)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedAttachment!.path.split(Platform.pathSeparator).last,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                        onPressed: () => setState(() => _selectedAttachment = null),
                      ),
                    ],
                  ),
                ),

              // نوار زنده درصد پیشرفت آپلود در کل برنامه
              if (_isUploading)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: const Color(0xFF17212B),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF50A2E9)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "در حال ارسال... ${(_uploadProgress * 100).toInt()}% (${_formatBytes(_uploadBytesSent)} / ${_formatBytes(_uploadTotalBytes)})",
                            style: const TextStyle(fontSize: 11, color: Color(0xFF50A2E9), fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          const Text("حداکثر ۲۰ مگابایت", style: TextStyle(fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: Colors.white10,
                        color: const Color(0xFF50A2E9),
                        minHeight: 2.5,
                      ),
                    ],
                  ),
                ),

              // تولتیپ شناور بالای کادر
              if (_floatingHintText != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _floatingHintText!,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),

              _buildTelegramInputBar(canSend),

              if (_showEmojiKeyboard)
                SizedBox(
                  height: 270,
                  child: EmojiPicker(
                    textEditingController: _msgController,
                    config: Config(
                      height: 270,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: const EmojiViewConfig(
                        backgroundColor: Color(0xFF17212B),
                        columns: 7,
                      ),
                      categoryViewConfig: const CategoryViewConfig(
                        backgroundColor: Color(0xFF17212B),
                        indicatorColor: Color(0xFF50A2E9),
                        iconColorSelected: Color(0xFF50A2E9),
                        iconColor: Colors.grey,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          if (_isRecordingVideoNote && _cameraController != null && _cameraController!.value.isInitialized)
            _buildCircularCameraOverlay(),
        ],
      ),
    );
  }

  Widget _buildTelegramInputBar(bool canSend) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: const Color(0xFF17212B),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF242F3D),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmojiKeyboard ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                      color: const Color(0xFF8E9BA8),
                      size: 24,
                    ),
                    onPressed: () {
                      if (_showEmojiKeyboard) {
                        setState(() => _showEmojiKeyboard = false);
                        _msgFocusNode.requestFocus();
                      } else {
                        FocusScope.of(context).unfocus();
                        setState(() => _showEmojiKeyboard = true);
                      }
                    },
                  ),
                  Expanded(
                    child: _isRecordingAudio
                        ? Container(
                            height: 44,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  "${_audioRecordSeconds ~/ 60}:${(_audioRecordSeconds % 60).toString().padLeft(2, '0')}",
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                if (_isRecordingLocked)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                    onPressed: () => _stopRecordingAudio(cancel: true),
                                  )
                                else
                                  const Text("◀ به راست بکشید برای لغو", style: TextStyle(color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          )
                        : TextField(
                            controller: _msgController,
                            focusNode: _msgFocusNode,
                            maxLines: 4,
                            minLines: 1,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            onTap: () {
                              if (_showEmojiKeyboard) setState(() => _showEmojiKeyboard = false);
                            },
                            onChanged: (_) {
                              _wsChannel?.sink.add(jsonEncode({"type": "typing"}));
                            },
                            decoration: const InputDecoration(
                              hintText: "Message",
                              hintStyle: TextStyle(color: Color(0xFF8E9BA8), fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                            ),
                          ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8E9BA8), size: 24),
                    onPressed: _pickAttachment,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // دکمه هوشمند تلگرام با کشیدن به راست برای لغو و کشیدن به بالا برای قفل
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // راهنمای قفل شدن هنگام نگه داشتن
              if ((_isRecordingAudio || _isRecordingVideoNote) && !_isRecordingLocked)
                Positioned(
                  bottom: 54,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text("▲ به بالا بکشید برای قفل", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

              GestureDetector(
                onTap: () {
                  if (canSend) {
                    _sendMessage();
                  } else if (_isRecordingLocked) {
                    if (_isVideoNoteMode) _stopRecordingVideoNote();
                    else _stopRecordingAudio();
                  } else {
                    _triggerVibration(duration: 30);
                    setState(() {
                      _isVideoNoteMode = !_isVideoNoteMode;
                    });
                    _showFloatingHint(
                      _isVideoNoteMode ? "Hold to record video. Tap to switch to audio." : "Hold to record audio. Tap to switch to video."
                    );
                  }
                },
                onLongPressStart: (_) {
                  if (!canSend && !_isRecordingLocked) {
                    if (_isVideoNoteMode) {
                      _startRecordingVideoNote();
                    } else {
                      _startRecordingAudio();
                    }
                  }
                },
                onLongPressMoveUpdate: (details) {
                  // در حالت فارسی، کشیدن به بالا برای قفل، کشیدن به راست برای لغو
                  if (details.localOffsetFromOrigin.dy < -50 && !_isRecordingLocked) {
                    _triggerVibration(duration: 40);
                    setState(() => _isRecordingLocked = true);
                  }
                  if (details.localOffsetFromOrigin.dx > 65 && !_isRecordingLocked) {
                    _triggerVibration(duration: 40);
                    if (_isVideoNoteMode) _stopRecordingVideoNote(cancel: true);
                    else _stopRecordingAudio(cancel: true);
                  }
                },
                onLongPressEnd: (details) {
                  if (!canSend && !_isRecordingLocked) {
                    final bool cancel = details.localPosition.dx > 65;
                    if (_isVideoNoteMode) {
                      _stopRecordingVideoNote(cancel: cancel);
                    } else {
                      _stopRecordingAudio(cancel: cancel);
                    }
                  }
                },
                child: CircleAvatar(
                  radius: 23,
                  backgroundColor: const Color(0xFF50A2E9),
                  child: Icon(
                    canSend || _isRecordingLocked
                        ? Icons.send_rounded
                        : (_isVideoNoteMode ? Icons.videocam_rounded : Icons.mic_rounded),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularCameraOverlay() {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF50A2E9), width: 3.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, spreadRadius: 5),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: _cameraController != null && _cameraController!.value.isInitialized && !_isSwitchingCamera
                      ? CameraPreview(_cameraController!)
                      : const Center(child: CircularProgressIndicator(color: Color(0xFF50A2E9))),
                ),
              ),
              Positioned(
                top: 12,
                child: GestureDetector(
                  onTap: _switchCamera,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    child: const Icon(Icons.flip_camera_android_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: GestureDetector(
                  onTap: () => _stopRecordingVideoNote(cancel: true),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.redAccent.withOpacity(0.8),
                    child: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${_videoRecordSeconds ~/ 60}:${(_videoRecordSeconds % 60).toString().padLeft(2, '0')}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageRow(ChatMessage msg, bool isMe, String currentUserName) {
    final senderColor = _getUserColor(msg.senderName);
    final isHighlighted = _highlightedMessageId == msg.id;

    final avatarTgId = isMe
        ? (_currentUser?['telegram_id']?.toString() ?? '')
        : (msg.isFromTelegram ? msg.senderId : '');

    final bool hasMedia = msg.mediaType != null && msg.mediaUrl != null;
    final bool hasCaption = msg.text.trim().isNotEmpty;
    final bool isFrameless = hasMedia && !hasCaption && msg.replyToName == null && (msg.mediaType == 'photo' || msg.mediaType == 'video' || msg.mediaType == 'video_note');

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 4 : 16),
      bottomRight: Radius.circular(isMe ? 16 : 4),
    );

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isMe) ...[
              _buildAvatar(avatarTgId, msg.senderName, senderColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: GestureDetector(
                onTap: () => _showContextMenu(msg),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: isFrameless
                        ? (isHighlighted ? const Color(0xFF50A2E9).withOpacity(0.4) : Colors.transparent)
                        : (isHighlighted
                            ? const Color(0xFF50A2E9).withOpacity(0.55)
                            : (isMe ? const Color(0xFF2B5278) : const Color(0xFF182533))),
                    border: isHighlighted
                        ? Border.all(color: const Color(0xFF50A2E9), width: 2.5)
                        : null,
                    boxShadow: isHighlighted
                        ? [
                            BoxShadow(
                              color: const Color(0xFF50A2E9).withOpacity(0.6),
                              blurRadius: 16,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                    borderRadius: borderRadius,
                  ),
                  padding: isFrameless
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe && !isFrameless)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              msg.senderName,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: senderColor),
                            ),
                          ),
                        if (msg.replyToName != null)
                          GestureDetector(
                            onTap: () {
                              if (msg.replyToId != null) _scrollToMessage(msg.replyToId!);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2, left: 4),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(6),
                                border: const Border(
                                  right: BorderSide(color: Color(0xFF50A2E9), width: 3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.replyToName!,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF50A2E9)),
                                  ),
                                  Text(
                                    msg.replyToText ?? '',
                                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (hasMedia) _buildMediaContent(msg, isFrameless, isMe),
                        if (msg.text.isNotEmpty)
                          Padding(
                            padding: isFrameless ? const EdgeInsets.all(8.0) : EdgeInsets.zero,
                            child: Text(
                              msg.text,
                              style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.35),
                            ),
                          ),
                        if (!isFrameless) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isMe) ...[
                                Text(
                                  msg.isRead == 1 ? "✓✓" : "✓",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: msg.isRead == 1 ? const Color(0xFF50A2E9) : Colors.white60,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (msg.isEdited) ...[
                                const Text("edited", style: TextStyle(fontSize: 10, color: Colors.white54)),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                msg.formattedTime,
                                style: const TextStyle(fontSize: 10, color: Colors.white60),
                              ),
                            ],
                          ),
                        ],
                        if (msg.reactions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: msg.reactions.entries.map((entry) {
                              final count = entry.value.length;
                              final isMyReaction = entry.value.contains(currentUserName);
                              return GestureDetector(
                                onTap: () => _toggleReaction(msg.id, entry.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isMyReaction ? const Color(0xFF2B5278) : const Color(0xFF17212B),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isMyReaction ? const Color(0xFF50A2E9) : Colors.white12,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(entry.key, style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 3),
                                      Text(
                                        count.toString(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!isMe) ...[
              const SizedBox(width: 6),
              _buildAvatar(avatarTgId, msg.senderName, senderColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String tgId, String name, Color fallbackColor) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: fallbackColor,
      child: ClipOval(
        child: tgId.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: "${AppConfig.baseUrl}/api/avatar?userId=$tgId&v=$_avatarCacheBuster",
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                placeholder: (_, __) => Center(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '👤',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                errorWidget: (_, __, ___) => Center(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '👤',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              )
            : Text(name.isNotEmpty ? name[0].toUpperCase() : '👤',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTimeOverlay(ChatMessage msg, bool isMe) {
    return Positioned(
      bottom: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe) ...[
              Text(
                msg.isRead == 1 ? "✓✓" : "✓",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: msg.isRead == 1 ? const Color(0xFF50A2E9) : Colors.white70,
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (msg.isEdited) ...[
              const Text("edited", style: TextStyle(fontSize: 9, color: Colors.white60)),
              const SizedBox(width: 4),
            ],
            Text(
              msg.formattedTime,
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent(ChatMessage msg, bool isFrameless, bool isMe) {
    final type = msg.mediaType;
    final url = msg.mediaUrl;
    final fileName = msg.mediaFileName ?? (type == 'video' ? 'video.mp4' : 'file');

    final isDownloaded = _downloadedMediaIds.contains(msg.id) || _localMediaPaths.containsKey(msg.id);
    final isDownloading = _downloadingMediaIds.contains(msg.id);
    final progress = _downloadProgress[msg.id] ?? 0.0;
    final currentBytes = _downloadedBytes[msg.id] ?? 0;
    final localPath = _localMediaPaths[msg.id];

    // ۱. ویدیو مسیج دایره‌ای تلگرام
    if (type == 'video_note' && url != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: GestureDetector(
            onTap: () => _openVideoPlayer(videoUrl: isDownloaded ? null : url, localPath: localPath, fileName: "video_note.mp4", isCircular: true),
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF50A2E9), width: 2.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: msg.thumbUrl != null && msg.thumbUrl != url
                        ? CachedNetworkImage(imageUrl: msg.thumbUrl!, width: 210, height: 210, fit: BoxFit.cover)
                        : Container(color: Colors.black87, width: 210, height: 210),
                  ),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    child: const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
                  ),
                  _buildTimeOverlay(msg, isMe),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ۲. ویس تلگرام با شکل موج صوتی و ثانیه‌شمار ایزوله
    if (type == 'voice' && url != null) {
      final bool isPlayingThis = _currentlyPlayingMsgId == msg.id && _playerState == PlayerState.playing;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _toggleAudioPlay(msg),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF50A2E9),
                child: Icon(
                  isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<Duration>(
                    valueListenable: _audioPosNotifier,
                    builder: (context, pos, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(24, (i) {
                          final h = (math.sin(i * 0.7).abs() * 16 + 4).clamp(4.0, 22.0);
                          final bool played = isPlayingThis && (_audioDuration.inMilliseconds > 0) &&
                              (i / 24 <= pos.inMilliseconds / _audioDuration.inMilliseconds);
                          return Container(
                            width: 3,
                            height: h,
                            decoration: BoxDecoration(
                              color: played ? const Color(0xFF50A2E9) : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<Duration>(
                    valueListenable: _audioPosNotifier,
                    builder: (context, pos, _) {
                      return Text(
                        isPlayingThis
                            ? "${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')}"
                            : msg.formattedDuration,
                        style: const TextStyle(fontSize: 10, color: Colors.white60),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ۳. موزیک پلیر تلگرام
    if (type == 'audio' && url != null) {
      final bool isPlayingThis = _currentlyPlayingMsgId == msg.id && _playerState == PlayerState.playing;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _toggleAudioPlay(msg),
              child: CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFF2B5278),
                child: Icon(
                  isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF50A2E9),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  ValueListenableBuilder<Duration>(
                    valueListenable: _audioPosNotifier,
                    builder: (context, pos, _) {
                      return Text(
                        isPlayingThis
                            ? "${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')} / ${_audioDuration.inMinutes}:${(_audioDuration.inSeconds % 60).toString().padLeft(2, '0')}"
                            : msg.formattedFileSize,
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF50A2E9), size: 22),
              onPressed: () {
                launchUrl(
                  Uri.parse("$url&download=1&name=${Uri.encodeComponent(fileName)}"),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      );
    }

    // ۴. عکس
    if (type == 'photo' && url != null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 380),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF141F2B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isDownloaded)
              GestureDetector(
                onTap: () => _openLightbox(url: url, localPath: localPath, fileName: fileName),
                child: localPath != null
                    ? Image.file(File(localPath), fit: BoxFit.cover, width: double.infinity)
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFF50A2E9))),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      ),
              )
            else
              Container(
                color: const Color(0xFF141F2B),
                width: double.infinity,
                height: 260,
              ),

            if (!isDownloaded)
              isDownloading
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 24, color: Colors.white),
                          onPressed: () => _cancelDownload(msg.id),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => _startDownloadingMedia(msg),
                      child: CircleAvatar(
                        radius: 25,
                        backgroundColor: Colors.black.withOpacity(0.6),
                        child: const Icon(Icons.arrow_downward_rounded, size: 26, color: Colors.white),
                      ),
                    ),

            if (isFrameless) _buildTimeOverlay(msg, isMe),
          ],
        ),
      );
    }

    // ۵. ویدیو
    if (type == 'video' && url != null) {
      final thumb = msg.thumbUrl;

      return Container(
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 380),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF141F2B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumb != null && thumb != url)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
            else
              Container(color: const Color(0xFF141F2B), width: double.infinity, height: 260),

            Container(color: Colors.black.withOpacity(0.25)),

            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isDownloading
                      ? "${_formatBytes(currentBytes)} / ${msg.formattedFileSize}"
                      : (msg.mediaDuration != null && msg.mediaDuration! > 0
                          ? msg.formattedDuration
                          : msg.formattedFileSize),
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            if (!isDownloaded && !isDownloading)
              GestureDetector(
                onTap: () => _startDownloadingMedia(msg),
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.black.withOpacity(0.6),
                  child: const Icon(Icons.arrow_downward_rounded, size: 26, color: Colors.white),
                ),
              )
            else if (isDownloading)
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26, color: Colors.white),
                    onPressed: () => _cancelDownload(msg.id),
                  ),
                ],
              )
            else
              GestureDetector(
                onTap: () => _openVideoPlayer(localPath: localPath, fileName: fileName),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.black.withOpacity(0.6),
                  child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.white),
                ),
              ),

            if (isFrameless) _buildTimeOverlay(msg, isMe),
          ],
        ),
      );
    }

    // ۶. اسناد و فایل‌ها
    if (type == 'document') {
      return GestureDetector(
        onTap: () {
          if (url != null) {
            launchUrl(
              Uri.parse("$url&download=1&name=${Uri.encodeComponent(fileName)}"),
              mode: LaunchMode.externalApplication,
            );
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF50A2E9), size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(msg.formattedFileSize, style: const TextStyle(fontSize: 10, color: Colors.white60)),
                  ],
                ),
              ),
              const Icon(Icons.download_rounded, color: Color(0xFF50A2E9), size: 22),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class VideoPlayerModal extends StatefulWidget {
  final String? videoUrl;
  final String? localPath;
  final String fileName;
  final bool isCircular;

  const VideoPlayerModal({
    super.key,
    this.videoUrl,
    this.localPath,
    required this.fileName,
    this.isCircular = false,
  });

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      _controller = VideoPlayerController.file(File(widget.localPath!))
        ..initialize().then((_) {
          setState(() => _isInitialized = true);
          _controller.play();
        });
    } else if (widget.videoUrl != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
        ..initialize().then((_) {
          setState(() => _isInitialized = true);
          _controller.play();
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(widget.fileName, style: const TextStyle(fontSize: 14)),
        actions: [
          if (widget.videoUrl != null)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () {
                launchUrl(
                  Uri.parse("${widget.videoUrl}&download=1&name=${Uri.encodeComponent(widget.fileName)}"),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
        ],
      ),
      body: Center(
        child: _isInitialized
            ? (widget.isCircular
                ? ClipOval(
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller),
                          Center(
                            child: IconButton(
                              iconSize: 52,
                              icon: Icon(
                                _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller),
                        VideoProgressIndicator(_controller, allowScrubbing: true),
                        Center(
                          child: IconButton(
                            iconSize: 52,
                            icon: Icon(
                              _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _controller.value.isPlaying ? _controller.pause() : _controller.play();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ))
            : const CircularProgressIndicator(color: Color(0xFF50A2E9)),
      ),
    );
  }
}