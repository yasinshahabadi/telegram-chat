import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/config.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/swipe_to_reply.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/user_avatar.dart';
import 'package:telegram_chat_mobile/features/media/presentation/widgets/media_bubble_content.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final bool isSenderOnline;
  final bool isHighlighted;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onTapReplyMessage;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isSenderOnline = false,
    this.isHighlighted = false,
    this.onReply,
    this.onEdit,
    this.onPin,
    this.onTapReplyMessage,
  });

  Color _colorFromName(String name) {
    if (name.isEmpty) return const Color(0xFF0088CC);
    final hash = name.codeUnits.fold<int>(0, (prev, c) => prev + c);
    const colors = [
      Color(0xFFE17076),
      Color(0xFF7BC862),
      Color(0xFFE5CA77),
      Color(0xFF65AADD),
      Color(0xFFA695E7),
      Color(0xFFEE7AAE),
      Color(0xFF6EC9CB),
      Color(0xFFFAA774),
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final content = !isMe
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  userId: message.senderId,
                  fullName: message.senderName,
                  size: 36,
                  showOnlineBadge: true,
                  isOnline: isSenderOnline,
                ),
                const SizedBox(width: 8),
                Flexible(child: _buildBubble(context, isMe: false)),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildBubble(context, isMe: true),
            ),
          );

    return SwipeToReply(
      onReply: () => onReply?.call(),
      enabled: onReply != null,
      child: content,
    );
  }

  Widget _buildBubble(BuildContext context, {required bool isMe}) {
    final theme = Theme.of(context);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface.withAlpha(40),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onLongPress: () => _showContextMenu(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe) ...[
                    Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _colorFromName(message.senderName),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (message.replyToName != null) ...[
                    _buildReplyPreview(theme),
                    const SizedBox(height: 6),
                  ],

                  if (message.hasAttachments) ...[
                    if (message.isUploading) ...[
                      _buildUploadProgress(theme),
                    ] else if (message.attachments.length == 1) ...[
                      MediaBubbleContent(
                        attachment: message.attachments.first,
                        isMe: isMe,
                        baseUrl: AppConfig.baseUrl,
                      ),
                    ] else ...[
                      _buildMultiAttachments(theme, isMe),
                    ],
                    if (message.text.isNotEmpty) const SizedBox(height: 6),
                  ],

                  if (message.text.isNotEmpty) ...[
                    Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: isMe
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],

                  const SizedBox(height: 4),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.isEdited) ...[
                        Text(
                          'ویرایش‌شده ',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color:
                                theme.colorScheme.onSurfaceVariant.withAlpha(160),
                          ),
                        ),
                      ],
                      Text(
                        message.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              theme.colorScheme.onSurfaceVariant.withAlpha(180),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(theme),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isHighlighted ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Stack(
          children: [
            child!,
            if (value > 0.01)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha((value * 120).toInt()),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: bubble,
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    final tappable = onTapReplyMessage != null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withAlpha(16),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.reply_rounded,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.replyToName ?? 'کاربر',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  message.replyToText ?? 'پیام',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!tappable) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTapReplyMessage,
      child: content,
    );
  }

  Widget _buildMultiAttachments(ThemeData theme, bool isMe) {
    final atts = message.attachments;
    final rows = <Widget>[];

    for (int i = 0; i < atts.length; i += 2) {
      final left = atts[i];
      final right = (i + 1 < atts.length) ? atts[i + 1] : null;

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildAttachmentCell(left, isMe)),
            const SizedBox(width: 4),
            Expanded(
              child: right != null
                  ? _buildAttachmentCell(right, isMe)
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < atts.length) rows.add(const SizedBox(height: 4));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _buildAttachmentCell(dynamic att, bool isMe) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: MediaBubbleContent(
          attachment: att,
          isMe: isMe,
          baseUrl: AppConfig.baseUrl,
        ),
      ),
    );
  }

  Widget _buildUploadProgress(ThemeData theme) {
    final count = message.attachments.length;
    final firstAtt = message.attachments.first;
    final label = count > 1 ? 'در حال ارسال $count فایل…' : firstAtt.fileName;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                firstAtt.isPhoto
                    ? Icons.image_rounded
                    : firstAtt.isVideo
                        ? Icons.videocam_rounded
                        : firstAtt.isVoice
                            ? Icons.mic_rounded
                            : Icons.insert_drive_file_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${(message.uploadProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: message.uploadProgress,
              minHeight: 4,
              backgroundColor: theme.colorScheme.onSurface.withAlpha(30),
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme) {
    if (message.isPending || message.isSending) {
      return Icon(
        Icons.access_time_rounded,
        size: 13,
        color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
      );
    }

    if (message.isSynced && message.isRead) {
      return Icon(
        Icons.done_all_rounded,
        size: 15,
        color: theme.colorScheme.primary,
      );
    }

    if (message.isSynced) {
      return Icon(
        Icons.done_rounded,
        size: 14,
        color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
      );
    }

    return const Icon(
      Icons.error_outline_rounded,
      size: 14,
      color: Colors.redAccent,
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('پاسخ (Reply)'),
              onTap: () {
                Navigator.pop(ctx);
                onReply?.call();
              },
            ),
            if (isMe && message.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('ویرایش متن'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.push_pin_rounded),
              title: Text(message.isPinned ? 'حذف پین' : 'سنجاق کردن (Pin)'),
              onTap: () {
                Navigator.pop(ctx);
                onPin?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}