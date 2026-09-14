import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/auth/data/auth_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_websocket_client.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/message_bubble.dart';

/// صفحه اصلی گفتگوی سوپرگروه متصل به تلگرام
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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ChatMessageModel? _replyingMessage;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final currentUser = widget.authRepository.currentUser;
    if (currentUser != null) {
      await widget.chatRepository.initialize(currentUser);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSendMessage(String text) {
    final user = widget.authRepository.currentUser;
    if (user == null) return;

    widget.chatRepository.sendMessage(
      text: text,
      currentUser: user,
      replyTo: _replyingMessage,
    );

    setState(() {
      _replyingMessage = null;
    });

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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

                if (confirm == true) {
                  widget.onLogout();
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // بنر پیام پین‌شده
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

            // لیست پیام‌ها (معکوس جهت عملکرد چت واقعی)
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

                      return MessageBubble(
                        message: message,
                        isMe: isMe,
                        onReply: () {
                          setState(() {
                            _replyingMessage = message;
                          });
                        },
                        onEdit: isMe ? () => _showEditDialog(message) : null,
                        onPin: () => widget.chatRepository.pinMessage(message.id),
                      );
                    },
                  );
                },
              ),
            ),

            // نوار تایپ و ارسال
            ChatInputBar(
              controller: _inputController,
              replyMessage: _replyingMessage,
              onCancelReply: () {
                setState(() {
                  _replyingMessage = null;
                });
              },
              onSend: _handleSendMessage,
              onTyping: () => widget.chatRepository.sendTyping(),
              onAttachment: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سیستم ارسال فایل در فاز ۱۵ متصل می‌شود.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
