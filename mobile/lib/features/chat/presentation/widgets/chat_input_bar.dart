import 'package:flutter/material.dart';
import '../../domain/models/chat_message_model.dart';

/// نوار ورودی پایین صفحه چت برای تایپ متن و پیش‌نمایش ریپلای
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final ChatMessageModel? replyMessage;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onSend;
  final VoidCallback onTyping;
  final VoidCallback? onAttachment;

  const ChatInputBar({
    super.key,
    required this.controller,
    this.replyMessage,
    required this.onCancelReply,
    required this.onSend,
    required this.onTyping,
    this.onAttachment,
  });

  void _submit() {
    final text = controller.text.trim();
    if (text.isNotEmpty) {
      onSend(text);
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // نوار ریپلای در صورت انتخاب پیام
          if (replyMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'پاسخ به ${replyMessage!.senderName}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          replyMessage!.text,
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
                    onPressed: onCancelReply,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],

          // کادر تایپ متن و دکمه‌های ارسال
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.attach_file_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onAttachment,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textDirection: TextDirection.rtl,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => onTyping(),
                    decoration: InputDecoration(
                      hintText: 'پیام...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
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
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
