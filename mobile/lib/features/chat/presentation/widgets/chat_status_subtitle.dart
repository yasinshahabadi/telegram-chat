import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_websocket_client.dart';

/// زیرعنوان وضعیت زیر نام چت در AppBar.
///
/// اولویت نمایش:
///   ۱) در حال نوشتن کاربر دیگر
///   ۲) تعداد کاربران آنلاین
///   ۳) وضعیت اتصال سوکت (connected / connecting / disconnected)
///
/// خودش به `ChatRepository` گوش می‌دهد و در صورت تغییر rebuild می‌کند.
class ChatStatusSubtitle extends StatelessWidget {
  final ChatRepository chatRepository;

  const ChatStatusSubtitle({
    super.key,
    required this.chatRepository,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatRepository,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final onlineCount = chatRepository.onlineCount;

    if (chatRepository.typingUserName != null) {
      return Text(
        '${chatRepository.typingUserName} در حال نوشتن...',
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

    final state = chatRepository.connectionState;
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
}