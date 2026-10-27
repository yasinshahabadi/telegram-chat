import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:telegram_chat_mobile/core/storage/app_cache_manager.dart';
import 'package:telegram_chat_mobile/features/auth/data/auth_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/delete_confirm_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/edit_message_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/logout_confirm_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/notification_debug_sheet.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/dialogs/retry_upload_dialog.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/chat_upload_coordinator.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/message_scroll_controller.dart';
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
  final MessageScrollController _messageScroll = MessageScrollController();

  ChatMessageModel? _replyingMessage;

  String? _highlightedMessageId;
  Timer? _highlightClearTimer;

  /// شمارهٔ درخواست پرش فعلی؛ برای بی‌اثر شدن پرش‌های قدیمی وقتی کاربر
  /// پشت‌سرهم روی چند reply می‌زند.
  int _replyJumpSequence = 0;

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
    _messageScroll.cancel();
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
    // کلیدهای پیام‌های حذف‌شده را نگه نداریم (جلوگیری از رشد حافظه).
    _messageScroll.pruneTo(
      widget.chatRepository.messages.map((message) => message.id),
    );
    _unreadFlow.onChatUpdate();
  }

  // ═════════════════════════════════════════════
  //  Reply tap
  // ═════════════════════════════════════════════

  /// پرش به پیامِ ریپلای‌شده.
  ///
  /// مراحل:
  ///   1. اگر پیام در حافظه نیست، از DB (بازهٔ پیوسته) بارگذاری می‌شود؛
  ///      پیام‌های قدیمی‌تر از ۵۰ پیام آخر هم قابل نمایش می‌شوند.
  ///   2. اگر پیام واقعاً حذف شده باشد، پیام روشن به کاربر نشان داده می‌شود
  ///      و هیچ اسکرول/هایلایتی انجام نمی‌شود (بدون خطا).
  ///   3. موقعیت پیام با اندازه‌گیری واقعی ارتفاع آیتم‌ها محاسبه می‌شود؛
  ///      پس برای پیام‌های کوتاه/بلند و پیام‌های بسیار قدیمی درست کار می‌کند.
  Future<void> _handleTapReplyMessage(String parentMessageId) async {
    final sequence = ++_replyJumpSequence;
    _highlightClearTimer?.cancel();

    var status = widget.chatRepository.messages
            .any((message) => message.id == parentMessageId)
        ? ReplyTargetLoadResult.loaded
        : await widget.chatRepository.ensureMessageLoaded(parentMessageId);

    if (!mounted || sequence != _replyJumpSequence) return;

    if (status == ReplyTargetLoadResult.tooOld) {
      _clearHighlight();
      _showInfo('این پیام بسیار قدیمی است و امکان نمایش آن وجود ندارد.');
      return;
    }

    if (status != ReplyTargetLoadResult.loaded) {
      _clearHighlight();
      _showReplyUnavailable('این پیام دیگر موجود نیست (حذف شده است).');
      return;
    }

    setState(() => _highlightedMessageId = parentMessageId);
    _unreadFlow.setHighlightPresent(true);

    final scrollController = await _waitForScrollController();
    if (!mounted || sequence != _replyJumpSequence) return;

    final result = await _messageScroll.scrollToMessage(
      messageId: parentMessageId,
      readMessages: () => widget.chatRepository.messages,
      scrollController: scrollController,
    );

    if (!mounted || sequence != _replyJumpSequence) return;

    if (result != MessageScrollResult.reached) {
      _clearHighlight();
      if (result == MessageScrollResult.notInList) {
        _showReplyUnavailable('این پیام دیگر موجود نیست (حذف شده است).');
      } else if (result != MessageScrollResult.cancelled) {
        _showInfo('انتقال به پیام ممکن نشد. دوباره تلاش کنید.');
      }
      return;
    }

    // تایمر را بعد از رسیدن به مقصد شروع می‌کنیم تا هایلایت در طول اسکرول
    // محو نشود و کاربر حتماً پیام را ببیند.
    _highlightClearTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && _highlightedMessageId == parentMessageId) {
        _clearHighlight();
      }
    });
  }

  /// در لحظات اول باز شدن چت، لیست هنوز `ScrollController` متصل ندارد.
  /// کمی صبر می‌کنیم تا پرش به‌جای شکست خوردن، انجام شود.
  Future<ScrollController?> _waitForScrollController() async {
    for (int attempt = 0; attempt < 20; attempt++) {
      final controller = _unreadFlow.scrollController;
      if (controller != null && controller.hasClients) return controller;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return null;
    }
    return _unreadFlow.scrollController;
  }

  void _clearHighlight() {
    if (!mounted) return;
    _highlightClearTimer?.cancel();
    _highlightClearTimer = null;
    if (_highlightedMessageId == null) {
      _unreadFlow.setHighlightPresent(false);
      return;
    }
    setState(() => _highlightedMessageId = null);
    _unreadFlow.setHighlightPresent(false);
  }

  void _showReplyUnavailable(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: Colors.amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onInverseSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(message, textDirection: TextDirection.rtl),
      ),
    );
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
    try {
      final payload = await MediaPickerScreen.show(context);
      if (!mounted || payload == null) return;

      await _uploadCoordinator.sendPickedMedia(
        payload.media,
        caption: payload.caption,
      );
    } finally {
      // فایل‌های اصلی گالری پس از پایان ارسال (یا انصراف) دیگر لازم نیستند.
      // کمی تأخیر می‌دهیم تا انیمیشن بسته‌شدن گالری تمام شود و در صورت
      // پاک‌شدن کش بندانگشتی، تصاویر در حال محو‌شدن خالی نشوند.
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 400),
          AppCacheManager.instance.trimGalleryCache,
        ),
      );
    }
  }

  Future<void> _handleFilePick(FileType type) async {
    final picked = await _uploadCoordinator.pickFiles(type);
    if (!mounted || picked == null) return;

    try {
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
    } finally {
      // file_picker هر فایل را در cache کپی می‌کند. نسخهٔ دائمی پیش از
      // آپلود در UploadLifecycle ساخته می‌شود، بنابراین کپی‌های کش را
      // بعد از ارسال یا انصراف حذف می‌کنیم.
      await AppCacheManager.instance.releasePickedFiles(
        picked
            .map((item) => item.sourceFile?.path)
            .whereType<String>(),
      );
    }
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
                messageScrollController: _messageScroll,
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
