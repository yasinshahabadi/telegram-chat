import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/data/voice_record_service.dart';

/// نوار ورودی پایین صفحه چت با پشتیبانی از ضبط صدا و ارسال فایل
class ChatInputBar extends StatelessWidget {
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
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: voiceRecordService,
        builder: (context, _) {
          final isRecording = voiceRecordService.isRecording;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ۱. نوار ریپلای در صورت انتخاب پیام
              if (replyMessage != null && !isRecording) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: theme.colorScheme.surfaceVariant.withAlpha(100),
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

              // ۲. نوار حالت ضبط صدا
              if (isRecording) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        tooltip: 'لغو ضبط',
                        onPressed: onCancelRecordVoice,
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
                        voiceRecordService.formattedDuration,
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
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          onPressed: onStopAndSendVoice,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ۳. نوار استاندارد تایپ متن و الصاق مدیا
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
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant.withAlpha(70),
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

                      // دکمه تغییر هوشمند بین ارسال متن و ضبط ویس
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
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
                              onPressed: hasText ? _submit : onStartRecordVoice,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
