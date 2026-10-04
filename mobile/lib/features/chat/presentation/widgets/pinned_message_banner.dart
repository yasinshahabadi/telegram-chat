import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';

/// بنر بالای لیست پیام‌ها که آخرین پیام پین‌شده را نشان می‌دهد.
///
/// اگر پیامی پین نشده باشد، فضایی اشغال نمی‌کند (`SizedBox.shrink`).
/// خودش به `ChatRepository` گوش می‌دهد.
class PinnedMessageBanner extends StatelessWidget {
  final ChatRepository chatRepository;

  const PinnedMessageBanner({
    super.key,
    required this.chatRepository,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatRepository,
      builder: (context, _) => _buildBanner(context),
    );
  }

  Widget _buildBanner(BuildContext context) {
    final theme = Theme.of(context);
    final pinned = chatRepository.pinnedMessage;

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
            onPressed: () => chatRepository.unpinMessage(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}