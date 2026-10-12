import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/config.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/reply_thumbnail.dart';
import 'package:telegram_chat_mobile/features/media/data/voice_record_service.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final ChatMessageModel? replyMessage;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onSend;
  final VoidCallback onTyping;
  final VoidCallback? onAttachment;
  final VoiceRecordService voiceRecordService;
  final VoidCallback onStartRecordVoice;
  final VoidCallback onStopAndSendVoice;
  final VoidCallback onCancelRecordVoice;

  const ChatInputBar({
    super.key,
    required this.controller,
    this.replyMessage,
    required this.onCancelReply,
    required this.onSend,
    required this.onTyping,
    this.onAttachment,
    required this.voiceRecordService,
    required this.onStartRecordVoice,
    required this.onStopAndSendVoice,
    required this.onCancelRecordVoice,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final FocusNode _inputFocusNode = FocusNode();
  bool _isEmojiPanelOpen = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onFocusChanged);
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// وقتی کاربر روی TextField ضربه می‌زند (کیبورد می‌خواهد بیاید)،
  /// پنل ایموجی بسته می‌شود.
  void _onFocusChanged() {
    if (!mounted) return;
    if (_inputFocusNode.hasFocus && _isEmojiPanelOpen) {
      setState(() => _isEmojiPanelOpen = false);
    }
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      widget.controller.clear();
    }
  }

  /// toggle پنل ایموجی.
  ///
  /// - اگر پنل باز است → بسته می‌شود + کیبورد باز می‌شود تا کاربر
  ///   بتواند به تایپ ادامه بدهد.
  /// - اگر پنل بسته است → کیبورد بسته می‌شود و پنل باز می‌شود.
  void _toggleEmojiPanel() {
    if (_isEmojiPanelOpen) {
      // ✅ ابتدا پنل را ببند (setState)، سپس فوکوس بده تا کیبورد بیاید.
      //    ترتیب مهم است: اگر برعکس عمل کنیم، listener روی FocusNode
      //    ممکن است پنل را دوباره باز کند.
      setState(() => _isEmojiPanelOpen = false);
      _inputFocusNode.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _isEmojiPanelOpen = true);
    }
  }

  void _closeEmojiPanel() {
    if (_isEmojiPanelOpen) {
      setState(() => _isEmojiPanelOpen = false);
    }
  }

  /// درج ایموجی در محل cursor فعلی متن.
  /// اگر cursor معتبر نبود (مثلاً TextField هرگز فوکوس نگرفته)،
  /// در انتهای متن درج می‌شود.
  void _insertEmoji(String emoji) {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;

    final cursorPos = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;

    final newText =
        text.substring(0, cursorPos) + emoji + text.substring(cursorPos);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorPos + emoji.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: widget.voiceRecordService,
        builder: (context, _) {
          final isRecording = widget.voiceRecordService.isRecording;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // نوار ریپلای
              if (widget.replyMessage != null && !isRecording) ...[
                _buildReplyBar(theme, widget.replyMessage!),
              ],

              // نوار حالت ضبط صدا یا کادر تایپ
              if (isRecording) ...[
                _buildRecordingBar(theme),
              ] else ...[
                _buildInputRow(theme),
                _buildEmojiPanel(theme),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecordingBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            tooltip: 'لغو ضبط',
            onPressed: widget.onCancelRecordVoice,
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.voiceRecordService.formattedDuration,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const Spacer(),
          const Text(
            'در حال ضبط ویس...',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary,
            radius: 20,
            child: IconButton(
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
              onPressed: widget.onStopAndSendVoice,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Row(
        children: [
          // دکمهٔ attachment
          IconButton(
            icon: Icon(
              Icons.attach_file_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              _closeEmojiPanel();
              widget.onAttachment?.call();
            },
          ),
          // دکمهٔ ایموجی — کنار attachment
          IconButton(
            icon: Icon(
              _isEmojiPanelOpen
                  ? Icons.keyboard_rounded
                  : Icons.emoji_emotions_outlined,
              color: _isEmojiPanelOpen
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: _isEmojiPanelOpen ? 'بستن ایموجی' : 'ایموجی',
            onPressed: _toggleEmojiPanel,
          ),
          // کادر تایپ
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _inputFocusNode,
              textDirection: TextDirection.rtl,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => widget.onTyping(),
              decoration: InputDecoration(
                hintText: 'پیام...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface.withAlpha(30),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // دکمهٔ ارسال / میکروفن
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;

              return CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                radius: 22,
                child: IconButton(
                  icon: Icon(
                    hasText ? Icons.send_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: hasText
                      ? _submit
                      : () {
                          _closeEmojiPanel();
                          widget.onStartRecordVoice();
                        },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPanel(ThemeData theme) {
    final colors = theme.colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: _isEmojiPanelOpen
          ? SizedBox(
              height: 300,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    top: BorderSide(
                      color: colors.outlineVariant.withAlpha(120),
                      width: 1,
                    ),
                  ),
                ),
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) =>
                      _insertEmoji(emoji.emoji),
                  config: Config(
                    height: 300,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: colors.surface,
                      emojiSizeMax: 26,
                      verticalSpacing: 4,
                      horizontalSpacing: 4,
                      gridPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      noRecents: Text(
                        'اخیراً استفاده‌شده‌ای وجود ندارد',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: colors.surface,
                      dividerColor: colors.outlineVariant,
                      indicatorColor: colors.primary,
                      iconColor: colors.onSurfaceVariant,
                      iconColorSelected: colors.primary,
                      backspaceColor: colors.onSurfaceVariant,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: colors.surface,
                      buttonIconColor: colors.onSurfaceVariant,
                      hintText: 'جستجوی ایموجی...',
                      inputTextStyle: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildReplyBar(ThemeData theme, ChatMessageModel reply) {
    final hasMedia = reply.attachments.isNotEmpty;
    final firstAtt = hasMedia ? reply.attachments.first : null;
    final hasText = reply.text.trim().isNotEmpty;
    final label = hasText
        ? reply.text
        : (hasMedia
            ? ReplyPreviewHelpers.labelFor(firstAtt!.mediaType)
            : 'پیام');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface.withAlpha(40),
      child: Row(
        children: [
          if (hasMedia) ...[
            ReplyThumbnail(
              mediaType: firstAtt!.mediaType,
              attachmentId: firstAtt.id,
              telegramFileId: firstAtt.telegramFileId,
              fileName: firstAtt.fileName,
              baseUrl: AppConfig.baseUrl,
              size: 40,
            ),
            const SizedBox(width: 10),
          ] else ...[
            Icon(
              Icons.reply_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'پاسخ به ${reply.senderName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: widget.onCancelReply,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}