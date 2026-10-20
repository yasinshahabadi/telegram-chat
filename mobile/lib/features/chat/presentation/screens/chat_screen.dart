import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:telegram_chat_mobile/features/auth/data/auth_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/delete_confirm_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/edit_message_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/logout_confirm_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/notification_debug_sheet.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/retry_upload_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/chat_upload_coordinator.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/unread_flow_controller.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/attachment_action.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_app_bar.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_message_list.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/pinned_message_banner.dart';
import 'package:telegram_chat_mobile/features/media/data/voice_record_service.dart';
import 'package:telegram_chat_mobile/features/media/presentation/screens/media_composer_screen.dart';
import 'package:telegram_chat_mobile/features/media/presentation/screens/media_picker_screen.dart';
import 'package:telegram_chat_mobile/features/media/presentation/screens/storage_settings_screen.dart';
import 'package:telegram_chat_mobile/features/settings/presentation/widgets/app_drawer.dart';

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
  final VoiceRecordService _voiceRecordService = VoiceRecordService();

  late final ChatUploadCoordinator _uploadCoordinator;
  late final UnreadFlowController _unreadFlow;

  ChatMessageModel? _replyingMessage;

  String? _highlightedMessageId;
  Timer? _highlightClearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _unreadFlow = UnreadFlowController(
      getMessages: () => widget.chatRepository.messages,
      getCurrentUserId: () => widget.authRepository.currentUser?.id,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      onScrollToBottomRequest: _scrollToBottom,
    );
    _unreadFlow.onMarkReadRequest = (ids) async {
      await widget.chatRepository.markMessagesAsRead(ids);
    };

    _uploadCoordinator = ChatUploadCoordinator(
      authRepository: widget.authRepository,
      chatRepository: widget.chatRepository,
      voiceRecordService: _voiceRecordService,
      getReplyTarget: () => _replyingMessage,
      onClearReplyTarget: () {
        if (mounted) setState(() => _replyingMessage = null);
      },
      onError: _showError,
      onScrollToBottom: _scrollToBottom,
      isMounted: () => mounted,
    );

    _initializeChat();
    widget.chatRepository.addListener(_onChatUpdate);
  }

  Future<void> _initializeChat() async {
    final currentUser = widget.authRepository.currentUser;
    if (currentUser == null) return;

    await widget.chatRepository.initialize(currentUser);
    await _unreadFlow.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.chatRepository.removeListener(_onChatUpdate);
    _highlightClearTimer?.cancel();
    _inputController.dispose();
    _unreadFlow.dispose();
    _voiceRecordService.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════
  //  Lifecycle & chat updates
  // ═════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isVisible = state == AppLifecycleState.resumed;
    _unreadFlow.onAppVisibilityChanged(isVisible);
  }

  void _onChatUpdate() {
    _unreadFlow.onChatUpdate();
  }

  // ═════════════════════════════════════════════
  //  Reply tap
  // ═════════════════════════════════════════════

  Future<void> _handleTapReplyMessage(String parentMessageId) async {
    final messages = widget.chatRepository.messages;
    final index = messages.indexWhere((m) => m.id == parentMessageId);
    if (index == -1) {
      _showError('پیام اصلی در دسترس نیست.');
      return;
    }

    setState(() => _highlightedMessageId = parentMessageId);
    _unreadFlow.setHighlightPresent(true);

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightedMessageId == parentMessageId) {
        setState(() => _highlightedMessageId = null);
        _unreadFlow.setHighlightPresent(false);
      }
    });

    await _unreadFlow.animateToApproximateIndex(index);
  }

  // ═════════════════════════════════════════════
  //  Delete / Retry / Edit
  // ═════════════════════════════════════════════

  Future<void> _confirmDeleteMessage(ChatMessageModel message) async {
    final confirmed = await DeleteMessageDialog.show(context);
    if (confirmed) {
      await widget.chatRepository.deleteMessage(message.id);
    }
  }

  Future<void> _showRetryDialog(ChatMessageModel message) async {
    final newText = await RetryUploadDialog.show(
      context,
      initialText: message.text,
    );

    if (newText == null) return;

    await _uploadCoordinator.retryUpload(message, newText);
  }

  Future<void> _showEditDialog(ChatMessageModel message) async {
    final newText = await EditMessageDialog.show(
      context,
      initialText: message.text,
    );

    if (newText != null) {
      widget.chatRepository.editMessage(message.id, newText);
    }
  }

  // ═════════════════════════════════════════════
  //  Send / voice / pick
  // ═════════════════════════════════════════════

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
    _unreadFlow.scrollToBottom();
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

  Future<void> _handleStartRecordVoice() async {
    await _uploadCoordinator.startVoiceRecord();
  }

  Future<void> _handleStopAndSendVoice() async {
    await _uploadCoordinator.stopAndSendVoice();
  }

  Future<void> _handleGalleryPick() async {
    final payload = await MediaPickerScreen.show(context);
    if (!mounted || payload == null) return;

    await _uploadCoordinator.sendPickedMedia(
      payload.media,
      caption: payload.caption,
    );
  }

  Future<void> _handleFilePick(FileType type) async {
    final picked = await _uploadCoordinator.pickFiles(type);
    if (!mounted || picked == null) return;

    final payload = await MediaComposerScreen.show(
      context,
      media: picked,
      allowAddMore: false,
    );
    if (!mounted || payload == null) return;

    await _uploadCoordinator.sendPickedMedia(
      payload.media,
      caption: payload.caption,
    );
  }

  /// اکشن‌های نوار پیوست.
  ///
  /// برای افزودن گزینهٔ جدید در آینده (مثلاً موقعیت یا مخاطب) کافی است
  /// یک [AttachmentAction] دیگر به این لیست اضافه شود.
  List<AttachmentAction> _buildAttachmentActions(ThemeData theme) {
    return [
      AttachmentAction(
        id: 'gallery',
        label: 'گالری',
        icon: Icons.photo_library_rounded,
        accentColor: theme.colorScheme.primary,
        onSelected: _handleGalleryPick,
      ),
      AttachmentAction(
        id: 'file',
        label: 'فایل',
        icon: Icons.insert_drive_file_rounded,
        accentColor: const Color(0xFFE0A63A),
        onSelected: () => _handleFilePick(FileType.any),
      ),
      AttachmentAction(
        id: 'music',
        label: 'موزیک',
        icon: Icons.library_music_rounded,
        accentColor: const Color(0xFFB07CD6),
        onSelected: () => _handleFilePick(FileType.audio),
      ),
    ];
  }

  // ═════════════════════════════════════════════
  //  Build
  // ═════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.authRepository.currentUser;
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: ChatAppBar.build(
          chatRepository: widget.chatRepository,
          onOpenStorage: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StorageSettingsScreen(),
              ),
            );
          },
          onOpenDebug: () {
            NotificationDebugSheet.show(context);
          },
          onLogout: () async {
            final confirm = await LogoutConfirmDialog.show(context);
            if (confirm) widget.onLogout();
          },
        ),
        body: Column(
          children: [
            PinnedMessageBanner(chatRepository: widget.chatRepository),
            Expanded(
              child: ChatMessageList(
                chatRepository: widget.chatRepository,
                currentUser: currentUser,
                scrollController: _unreadFlow.scrollController,
                chatReady: _unreadFlow.chatReady,
                dividerPhase: _unreadFlow.dividerPhase,
                snapshotFirstUnreadId: _unreadFlow.snapshotFirstUnreadId,
                snapshotUnreadCount: _unreadFlow.snapshotUnreadCount,
                firstUnreadKey: _unreadFlow.firstUnreadKey,
                highlightedMessageId: _highlightedMessageId,
                onReply: (message) =>
                    setState(() => _replyingMessage = message),
                onEdit: _showEditDialog,
                onDelete: _confirmDeleteMessage,
                onRetry: _showRetryDialog,
                onPin: (message) =>
                    widget.chatRepository.pinMessage(message.id),
                onTapReplyMessage: _handleTapReplyMessage,
                onToggleReaction: (messageId, emoji) =>
                    widget.chatRepository.toggleReaction(messageId, emoji),
              ),
            ),
            ChatInputBar(
              controller: _inputController,
              replyMessage: _replyingMessage,
              onCancelReply: () => setState(() => _replyingMessage = null),
              onSend: _handleSendMessage,
              onTyping: () => widget.chatRepository.sendTyping(),
              attachmentActions: _buildAttachmentActions(theme),
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
