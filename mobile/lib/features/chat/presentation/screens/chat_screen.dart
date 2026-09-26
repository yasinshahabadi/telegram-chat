import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/notifications/data/firebase_messaging_service.dart';
import 'package:telegram_chat_mobile/features/auth/data/auth_repository.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_websocket_client.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/message_bubble.dart';
import 'package:telegram_chat_mobile/features/media/data/media_download_manager.dart';
import 'package:telegram_chat_mobile/features/media/data/media_remote_service.dart';
import 'package:telegram_chat_mobile/features/media/data/voice_record_service.dart';
import 'package:telegram_chat_mobile/features/media/presentation/screens/storage_settings_screen.dart';
import 'package:telegram_chat_mobile/features/notifications/data/notification_service.dart';

class ChatScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final ChatRepository chatRepository;
  final VoidCallback onLogout;

  const ChatScreen({
    super.key,
    required this.authRepository,
    required this.chatRepository,
    required this.onLogout,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final VoiceRecordService _voiceRecordService = VoiceRecordService();
  final MediaRemoteService _mediaRemoteService = MediaRemoteService();

  ChatMessageModel? _replyingMessage;
  bool _isMarkingRead = false;
  bool _isAppVisible = true;

  Timer? _markReadDebounce;
  final Set<String> _pendingMarkReadIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    widget.chatRepository.addListener(_onChatUpdate);
  }

  Future<void> _initializeChat() async {
    final currentUser = widget.authRepository.currentUser;
    if (currentUser != null) {
      await widget.chatRepository.initialize(currentUser);
      await _markUnreadMessagesAsRead();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.chatRepository.removeListener(_onChatUpdate);
    _markReadDebounce?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _voiceRecordService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isVisible = state == AppLifecycleState.resumed;
    if (_isAppVisible != isVisible) {
      _isAppVisible = isVisible;
      debugPrint('[ChatScreen] App visibility: $_isAppVisible ($state)');

      if (_isAppVisible) {
        _markReadDebounce?.cancel();
        _flushMarkRead();
      } else {
        _markReadDebounce?.cancel();
      }
    }
  }

  void _onChatUpdate() {
    if (!_isAppVisible) return;

    final user = widget.authRepository.currentUser;
    if (user == null) return;

    final messages = widget.chatRepository.messages;
    if (messages.isNotEmpty && _scrollController.hasClients) {
      if (!_scrollController.position.isScrollingNotifier.value) {
        _scrollToBottom();
      }
    }

    final unreadIds = messages
        .where((m) => m.senderId != user.id && m.readAt == null)
        .map((m) => m.id)
        .toSet();

    if (unreadIds.isEmpty) return;

    _pendingMarkReadIds.addAll(unreadIds);

    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 800), () {
      _flushMarkRead();
    });
  }

  Future<void> _flushMarkRead() async {
    if (!_isAppVisible) return;
    if (_isMarkingRead) return;
    if (_pendingMarkReadIds.isEmpty) return;

    final idsToMark = _pendingMarkReadIds.toList();
    _pendingMarkReadIds.clear();

    _isMarkingRead = true;
    try {
      await widget.chatRepository.markMessagesAsRead(idsToMark);
    } finally {
      _isMarkingRead = false;
    }
  }

  Future<void> _markUnreadMessagesAsRead() async {
    if (!_isAppVisible) return;
    if (_isMarkingRead) return;

    final user = widget.authRepository.currentUser;
    if (user == null) return;

    final unreadIds = widget.chatRepository.messages
        .where((m) => m.senderId != user.id && m.readAt == null)
        .map((m) => m.id)
        .toList();

    if (unreadIds.isEmpty) return;

    _isMarkingRead = true;
    try {
      await widget.chatRepository.markMessagesAsRead(unreadIds);
    } finally {
      _isMarkingRead = false;
    }
  }

  void _handleSendMessage(String text) {
    final user = widget.authRepository.currentUser;
    if (user == null) return;

    widget.chatRepository.sendMessage(
      text: text,
      currentUser: user,
      replyTo: _replyingMessage,
    );

    setState(() => _replyingMessage = null);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showNotificationDebugMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🛠️ پنل دیباگ و تست اعلان‌ها',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.notifications_active, color: Colors.green),
                  title: const Text('تست ۱: اعلان مستقیم محلی'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await NotificationService.instance.showChatNotification(
                      id: 101,
                      senderName: 'تست ۱: محلی',
                      messageText: 'موتور اعلان داخلی کار می‌کند! ✅',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vpn_key_rounded, color: Colors.amber),
                  title: const Text('تست ۳: دریافت توکن FCM'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final token = await FirebaseMessagingService.instance.getToken();
                    if (mounted && token != null) {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('توکن FCM دستگاه'),
                          content: SelectableText(token),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('بستن'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════
  //  ضبط ویس
  // ═════════════════════════════════════════════

  Future<void> _handleStartRecordVoice() async {
    final started = await _voiceRecordService.startRecording();
    if (!started && mounted) {
      _showError('دسترسی به میکروفون داده نشد.');
    }
  }

  Future<void> _handleStopAndSendVoice() async {
    final path = await _voiceRecordService.stopRecording();
    if (path == null) return;

    final user = widget.authRepository.currentUser;
    final token = widget.authRepository.sessionToken;
    if (user == null || token == null) {
      _showError('جلسه منقضی شده است. لطفاً مجدداً وارد شوید.');
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    await _uploadFilesWithOptimisticUI(
      files: [file],
      mediaTypes: ['voice'],
      originalNames: [file.uri.pathSegments.last],
      token: token,
      user: user,
    );
  }

  // ═════════════════════════════════════════════
  //  انتخاب و آپلود فایل
  // ═════════════════════════════════════════════

  Future<void> _handleAttachmentPick() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded, color: Colors.blue),
                title: const Text('ارسال عکس یا ویدیو'),
                subtitle: const Text('می‌توانید چند فایل انتخاب کنید'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFiles(FileType.media);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_rounded, color: Colors.amber),
                title: const Text('ارسال فایل و اسناد'),
                subtitle: const Text('می‌توانید چند فایل انتخاب کنید'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFiles(FileType.any);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendFiles(FileType type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final validFiles = <File>[];
      final mediaTypes = <String>[];
      final originalNames = <String>[];

      for (final pf in result.files) {
        if (pf.path == null) continue;
        final file = File(pf.path!);
        if (!await file.exists()) continue;

        final name = pf.name;
        final ext = name.split('.').last.toLowerCase();
        String mediaType = 'document';
        if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'].contains(ext)) {
          mediaType = 'photo';
        } else if (['mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v'].contains(ext)) {
          mediaType = 'video';
        } else if (['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'].contains(ext)) {
          mediaType = 'audio';
        }

        validFiles.add(file);
        mediaTypes.add(mediaType);
        originalNames.add(name);
      }

      if (validFiles.isEmpty) return;

      final user = widget.authRepository.currentUser;
      final token = widget.authRepository.sessionToken;
      if (user == null || token == null) {
        _showError('جلسه منقضی شده است. لطفاً مجدداً وارد شوید.');
        return;
      }

      await _uploadFilesWithOptimisticUI(
        files: validFiles,
        mediaTypes: mediaTypes,
        originalNames: originalNames,
        token: token,
        user: user,
      );
    } catch (e) {
      _showError('خطا در انتخاب فایل: $e');
    }
  }

  Future<void> _uploadFilesWithOptimisticUI({
    required List<File> files,
    required List<String> mediaTypes,
    required List<String> originalNames,
    required String token,
    required AuthUser user,
  }) async {
    final optimistic = widget.chatRepository.addOptimisticMultiUpload(
      files: files,
      mediaTypes: mediaTypes,
      currentUser: user,
      replyTo: _replyingMessage,
    );
    final tempId = optimistic.id;
    final clientMessageId = optimistic.clientMessageId;

    setState(() => _replyingMessage = null);
    _scrollToBottom();

    try {
      final result = await _mediaRemoteService.uploadFiles(
        files: files,
        mediaTypes: mediaTypes,
        originalNames: originalNames,
        sessionToken: token,
        clientMessageId: clientMessageId,
        onProgress: (p) {
          widget.chatRepository.updateUploadProgress(tempId, p);
        },
      );

      if (!mounted) return;

      if (!result.isSuccess || result.messageId == null) {
        widget.chatRepository.failUpload(tempId, result.error ?? 'خطا');
        _showError(result.error ?? 'خطا در آپلود فایل');
        return;
      }

      widget.chatRepository.finalizeMultiUpload(
        tempId: tempId,
        clientMessageId: clientMessageId,
        realMessageId: result.messageId!,
        attachments: result.attachments,
      );

      // کش کردن فایل‌های ارسالی با attachmentId سرور.
      for (int i = 0; i < result.attachments.length && i < files.length; i++) {
        try {
          final cached = await MediaDownloadManager.instance.cacheUploadedFile(
            attachmentId: result.attachments[i].id,
            sourcePath: files[i].path,
            originalFileName: originalNames[i],
          );
          if (cached != null) {
            widget.chatRepository.setLocalPathForAttachment(
              result.messageId!,
              result.attachments[i].id,
              cached.path,
            );
          }
        } catch (e) {
          debugPrint('Cache uploaded file failed: $e');
        }
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      widget.chatRepository.failUpload(tempId, e.toString());
      _showError('خطا در ارسال فایل: $e');
    }
  }

  void _showEditDialog(ChatMessageModel message) {
    final editController = TextEditingController(text: message.text);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ویرایش پیام'),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'متن جدید پیام...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty && newText != message.text) {
                  widget.chatRepository.editMessage(message.id, newText);
                }
                Navigator.pop(ctx);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSubtitle(ThemeData theme) {
    final onlineCount = widget.chatRepository.onlineCount;

    if (widget.chatRepository.typingUserName != null) {
      return Text(
        '${widget.chatRepository.typingUserName} در حال نوشتن...',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.primary,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (onlineCount > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$onlineCount نفر آنلاین',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green.shade600,
            ),
          ),
        ],
      );
    }

    final state = widget.chatRepository.connectionState;
    switch (state) {
      case SocketConnectionState.connected:
        return Text(
          'متصل به گفتگوی زنده',
          style: TextStyle(fontSize: 12, color: Colors.green.shade600),
        );
      case SocketConnectionState.connecting:
      case SocketConnectionState.reconnecting:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'در حال اتصال مجدد...',
              style: TextStyle(fontSize: 12, color: Colors.amber),
            ),
          ],
        );
      case SocketConnectionState.disconnected:
        return const Text(
          'آفلاین (استفاده از حافظه دستگاه)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = widget.authRepository.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سوپرگروه تلگرام',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              AnimatedBuilder(
                animation: widget.chatRepository,
                builder: (_, __) => _buildStatusSubtitle(theme),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.storage_rounded),
              tooltip: 'مدیریت حافظه',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StorageSettingsScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.build_circle_rounded, color: Colors.amber),
              tooltip: 'پنل تست اعلان‌ها',
              onPressed: _showNotificationDebugMenu,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'خروج از حساب',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('خروج از حساب'),
                    content: const Text('آیا از خروج اطمینان دارید؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('خیر'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('خروج'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) widget.onLogout();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            AnimatedBuilder(
              animation: widget.chatRepository,
              builder: (_, __) {
                final pinned = widget.chatRepository.pinnedMessage;
                if (pinned == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: theme.colorScheme.primaryContainer.withAlpha(128),
                  child: Row(
                    children: [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'پیام پین‌شده: ${pinned.senderName}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              pinned.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => widget.chatRepository.unpinMessage(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              },
            ),

            Expanded(
              child: AnimatedBuilder(
                animation: widget.chatRepository,
                builder: (_, __) {
                  final messages = widget.chatRepository.messages;

                  if (messages.isEmpty && widget.chatRepository.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'هنوز پیامی وجود ندارد.\nنخستین پیام را ارسال کنید!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = currentUser != null &&
                          (message.senderId == currentUser.id ||
                              message.senderName == currentUser.fullName);

                      return RepaintBoundary(
                        key: ValueKey(message.id),
                        child: KeyedSubtree(
                          key: PageStorageKey('msg_${message.id}'),
                          child: MessageBubble(
                            message: message,
                            isMe: isMe,
                            isSenderOnline: widget.chatRepository.isUserOnline(message.senderId),
                            onReply: () => setState(() => _replyingMessage = message),
                            onEdit: isMe ? () => _showEditDialog(message) : null,
                            onPin: () => widget.chatRepository.pinMessage(message.id),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            ChatInputBar(
              controller: _inputController,
              replyMessage: _replyingMessage,
              onCancelReply: () => setState(() => _replyingMessage = null),
              onSend: _handleSendMessage,
              onTyping: () => widget.chatRepository.sendTyping(),
              onAttachment: _handleAttachmentPick,
              voiceRecordService: _voiceRecordService,
              onStartRecordVoice: _handleStartRecordVoice,
              onStopAndSendVoice: _handleStopAndSendVoice,
              onCancelRecordVoice: () => _voiceRecordService.cancelRecording(),
            ),
          ],
        ),
      ),
    );
  }
}