import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/config.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/presentation/widgets/media_bubble_content.dart';

/// ویجت بالون نمایش پیام با بهینه‌سازی رندر و رنگ‌های متریال
class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onReply,
    this.onEdit,
    this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
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
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (message.replyToName != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withAlpha(16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border(
                          right: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.replyToName!,
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

                  // در متد build، جایگزین بخش attachment:
                  if (message.attachment != null) ...[
                    if (message.isUploading) ...[
                      // ✅ نمایش نوار پیشرفت آپلود (مثل تلگرام)
                      Container(
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
                                  message.attachment!.isPhoto
                                      ? Icons.image_rounded
                                      : message.attachment!.isVideo
                                          ? Icons.videocam_rounded
                                          : Icons.insert_drive_file_rounded,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    message.attachment!.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                  '${(message.uploadProgress * 100).toInt()}%',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
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
                      ),
                    ] else ...[
                      // نمایش مدیای واقعی پس از آپلود
                      MediaBubbleContent(
                        attachment: message.attachment!,
                        isMe: isMe,
                        baseUrl: AppConfig.baseUrl,
                      ),
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
                            color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                          ),
                        ),
                      ],
                      Text(
                        message.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
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
  }

Widget _buildStatusIcon(ThemeData theme) {
  // در حال ارسال یا معلق
  if (message.isPending || message.isSending) {
    return Icon(
      Icons.access_time_rounded,
      size: 13,
      color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
    );
  }

  // ارسال شده و خوانده‌شده (تیک دوم)
  if (message.isSynced && message.isRead) {
    return Icon(
      Icons.done_all_rounded,
      size: 15,
      color: theme.colorScheme.primary,
    );
  }

  // ارسال شده اما خوانده‌نشده (تیک اول)
  if (message.isSynced) {
    return Icon(
      Icons.done_rounded,
      size: 14,
      color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
    );
  }

  // خطا
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
