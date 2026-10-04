import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/state/unread_flow_controller.dart'
    show DividerPhase;
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/message_bubble.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/unread_divider.dart';

/// لیست پیام‌های چت + empty/loading state + item builder.
///
/// تمام state مربوط به divider (کدام پیام اولین نخوانده، چند نخوانده، در چه
/// فازی) از بیرون تزریق می‌شود تا این ویجت کاملاً stateless بماند.
class ChatMessageList extends StatelessWidget {
  final ChatRepository chatRepository;
  final AuthUser? currentUser;
  final ScrollController? scrollController;
  final bool chatReady;

  // ── Unread divider context ──
  final DividerPhase dividerPhase;
  final String? snapshotFirstUnreadId;
  final int snapshotUnreadCount;
  final GlobalKey firstUnreadKey;

  // ── Highlight ──
  final String? highlightedMessageId;

  // ── Item callbacks ──
  final ValueChanged<ChatMessageModel> onReply;
  final ValueChanged<ChatMessageModel>? onEdit;
  final ValueChanged<ChatMessageModel>? onDelete;
  final ValueChanged<ChatMessageModel>? onRetry;
  final ValueChanged<ChatMessageModel> onPin;
  final ValueChanged<String> onTapReplyMessage;
  final void Function(String messageId, String emoji) onToggleReaction;

  const ChatMessageList({
    super.key,
    required this.chatRepository,
    required this.currentUser,
    required this.scrollController,
    required this.chatReady,
    required this.dividerPhase,
    required this.snapshotFirstUnreadId,
    required this.snapshotUnreadCount,
    required this.firstUnreadKey,
    required this.highlightedMessageId,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
    required this.onPin,
    required this.onTapReplyMessage,
    required this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatRepository,
      builder: (context, _) => _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final messages = chatRepository.messages;

    if (!chatReady || scrollController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty && chatRepository.isLoading) {
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
      controller: scrollController,
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return RepaintBoundary(
          key: ValueKey(message.id),
          child: _buildMessageItem(context, message),
        );
      },
    );
  }

  Widget _buildMessageItem(BuildContext context, ChatMessageModel message) {
    final user = currentUser;
    final isMe = user != null &&
        (message.senderId == user.id ||
            message.senderName == user.fullName);
    final canDelete = isMe || (user?.isAdmin == true);

    final isFirstUnread = message.id == snapshotFirstUnreadId;
    final showDivider = isFirstUnread &&
        dividerPhase != DividerPhase.done &&
        dividerPhase != DividerPhase.idle;

    final bubble = MessageBubble(
      message: message,
      isMe: isMe,
      isSenderOnline: chatRepository.isUserOnline(message.senderId),
      isHighlighted: highlightedMessageId == message.id,
      canDelete: canDelete,
      onReply: () => onReply(message),
      onEdit: (isMe && onEdit != null) ? () => onEdit!(message) : null,
      onDelete: (canDelete && onDelete != null)
          ? () => onDelete!(message)
          : null,
      onPin: () => onPin(message),
      onRetry: (message.isFailed && onRetry != null)
          ? () => onRetry!(message)
          : null,
      onTapReplyMessage: message.replyToMessageId != null
          ? () => onTapReplyMessage(message.replyToMessageId!)
          : null,
      onToggleReaction: (emoji) => onToggleReaction(message.id, emoji),
    );

    if (showDivider) {
      return KeyedSubtree(
        key: firstUnreadKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UnreadDivider(
              visible: dividerPhase != DividerPhase.fading,
              count: snapshotUnreadCount,
            ),
            bubble,
          ],
        ),
      );
    }

    return bubble;
  }
}