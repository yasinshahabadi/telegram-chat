import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';

/// Header بالای حباب پیام‌های forward شده.
///
/// نمایش:  [🔁] فوروارد شده از  [نام مبدأ]
///
/// اگر `message.hasForwardLink` true باشد، کل header کلیک‌پذیر است و
/// با لمس، تلگرام روی پیام مبدأ باز می‌شود. در غیر این‌صورت فقط متن
/// نمایش داده می‌شود (بدون تعامل).
class ForwardHeader extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final Color nameColor;

  const ForwardHeader({
    super.key,
    required this.message,
    required this.isMe,
    required this.nameColor,
  });

  Future<void> _openForwardSource(BuildContext context) async {
    final link = message.forwardDeepLink;
    if (link == null) return;

    try {
      final uri = Uri.parse(link);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _showError(context, 'امکان باز کردن تلگرام وجود ندارد');
      }
    } catch (e) {
      debugPrint('[ForwardHeader] Failed to open $link: $e');
      if (context.mounted) {
        _showError(context, 'خطا در باز کردن لینک');
      }
    }
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final title = (message.forwardFromChatTitle ?? '').trim().isNotEmpty
        ? message.forwardFromChatTitle!.trim()
        : 'کاربر';

    final isClickable = message.hasForwardLink;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.forward_rounded,
          size: 14,
          color: muted.withAlpha(200),
        ),
        const SizedBox(width: 4),
        Text(
          'فوروارد شده از',
          style: TextStyle(
            fontSize: 11,
            color: muted.withAlpha(200),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: nameColor,
            ),
          ),
        ),
        if (isClickable) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.open_in_new_rounded,
            size: 11,
            color: nameColor.withAlpha(180),
          ),
        ],
      ],
    );

    if (!isClickable) return row;

    return InkWell(
      onTap: () => _openForwardSource(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: row,
      ),
    );
  }
}