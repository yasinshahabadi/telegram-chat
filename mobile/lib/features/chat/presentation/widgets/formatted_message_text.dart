import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:telegram_chat_mobile/features/chat/domain/models/message_entity.dart';

/// ویجت متن پیام با رندر کامل entity های تلگرام.
///
/// تفاوت با LinkifiedText:
///   - LinkifiedText: خودش regex می‌زند و لینک/mention را تشخیص می‌دهد.
///   - FormattedMessageText: entity های تلگرام را رندر می‌کند (bold،
///     blockquote، text_link، code، ...). اگر entity نداشت، به
///     LinkifiedText برمی‌گردد.
class FormattedMessageText extends StatelessWidget {
  final String text;
  final List<MessageEntity> entities;
  final TextStyle? style;
  final TextStyle? linkStyle;

  const FormattedMessageText({
    super.key,
    required this.text,
    required this.entities,
    this.style,
    this.linkStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    // اگر entity نداریم، fallback به رفتار LinkifiedText (regex).
    if (entities.isEmpty) {
      return _FallbackLinkifiedText(
        text: text,
        style: style,
        linkStyle: linkStyle,
      );
    }

    final blocks = _partition(text, entities);

    // اگر فقط یک بلوک غیر-blockquote داریم → RichText ساده.
    if (blocks.length == 1 && !blocks.first.isBlockquote) {
      return RichText(
        text: TextSpan(
          style: style,
          children: _buildSpans(
            context,
            blocks.first.text,
            blocks.first.entities,
            style,
            linkStyle,
          ),
        ),
      );
    }

    // در غیر این صورت → Column با بلوک‌های blockquote و غیر blockquote.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks.map((b) {
        final richText = RichText(
          text: TextSpan(
            style: style,
            children: _buildSpans(context, b.text, b.entities, style, linkStyle),
          ),
        );
        if (b.isBlockquote) {
          return _BlockquoteBox(child: richText);
        }
        return richText;
      }).toList(),
    );
  }

  // ═════════════════════════════════════════════
  //  Partition into blocks
  // ═════════════════════════════════════════════

  List<_TextBlock> _partition(String text, List<MessageEntity> entities) {
    final blockquotes = entities.where((e) => e.isBlockquote).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (blockquotes.isEmpty) {
      return [_TextBlock(text: text, entities: entities)];
    }

    final result = <_TextBlock>[];
    int cursor = 0;

    for (final bq in blockquotes) {
      if (bq.offset < cursor) continue;
      if (bq.offset > cursor) {
        final segText = text.substring(cursor, bq.offset);
        final segEntities = _entitiesInRange(entities, cursor, bq.offset);
        if (segText.isNotEmpty) {
          result.add(_TextBlock(text: segText, entities: segEntities));
        }
      }

      final bqEnd = (bq.offset + bq.length).clamp(0, text.length);
      if (bq.offset >= text.length) break;
      final bqText = text.substring(bq.offset, bqEnd);
      final inner = <MessageEntity>[];
      for (final e in entities) {
        if (identical(e, bq)) continue;
        if (e.isBlockquote) continue;
        if (e.offset >= bq.offset && e.end <= bqEnd) {
          inner.add(e.shifted(-bq.offset));
        }
      }
      result.add(_TextBlock(
        text: bqText,
        entities: inner,
        isBlockquote: true,
      ));
      cursor = bqEnd;
    }

    if (cursor < text.length) {
      final segText = text.substring(cursor);
      final segEntities = _entitiesInRange(entities, cursor, text.length);
      if (segText.isNotEmpty) {
        result.add(_TextBlock(text: segText, entities: segEntities));
      }
    }

    return result;
  }

  List<MessageEntity> _entitiesInRange(
    List<MessageEntity> all,
    int start,
    int end,
  ) {
    final out = <MessageEntity>[];
    for (final e in all) {
      if (e.isBlockquote) continue;
      if (e.offset >= start && e.end <= end) {
        out.add(e.shifted(-start));
      }
    }
    return out;
  }

  // ═════════════════════════════════════════════
  //  Build TextSpans
  // ═════════════════════════════════════════════

  List<InlineSpan> _buildSpans(
    BuildContext context,
    String text,
    List<MessageEntity> entities,
    TextStyle? baseStyle,
    TextStyle? linkStyle,
  ) {
    if (entities.isEmpty) return [TextSpan(text: text)];

    final sorted = [...entities]..sort((a, b) {
      final c = a.offset.compareTo(b.offset);
      if (c != 0) return c;
      return b.length.compareTo(a.length);
    });

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final entity in sorted) {
      if (entity.offset < cursor) continue;
      if (entity.offset > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, entity.offset)));
      }
      final end = (entity.offset + entity.length).clamp(0, text.length);
      if (end <= entity.offset) continue;
      final segment = text.substring(entity.offset, end);
      spans.add(_spanFor(
        context,
        segment,
        entity,
        baseStyle,
        linkStyle,
      ));
      cursor = end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans;
  }

  InlineSpan _spanFor(
    BuildContext context,
    String segment,
    MessageEntity entity,
    TextStyle? baseStyle,
    TextStyle? linkStyle,
  ) {
    final theme = Theme.of(context);

    // blockquote داخل متن inline نباید بیاید — چون جدا مدیریت می‌شود.
    if (entity.isBlockquote) {
      return TextSpan(text: segment);
    }

    // لینک‌ها
    if (entity.isLink) {
      final url = _resolveLink(entity, segment);
      if (url != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _open(url);
        return TextSpan(
          text: segment,
          style: linkStyle ??
              TextStyle(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
          recognizer: recognizer,
        );
      }
    }

    // استایل‌های متنی
    TextStyle? style;

    if (entity.isBold) {
      style = (style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.bold,
      );
    }
    if (entity.isItalic) {
      style = (style ?? const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
      );
    }
    if (entity.isUnderline) {
      style = (style ?? const TextStyle()).copyWith(
        decoration: TextDecoration.underline,
      );
    }
    if (entity.isStrikethrough) {
      final existing = style?.decoration;
      style = (style ?? const TextStyle()).copyWith(
        decoration: existing == TextDecoration.underline
            ? TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough])
            : TextDecoration.lineThrough,
      );
    }
    if (entity.isCode) {
      style = (style ?? const TextStyle()).copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      );
    }
    if (entity.isPre) {
      style = (style ?? const TextStyle()).copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      );
    }
    if (entity.isSpoiler) {
      // فعلاً به‌صورت نیمه‌محو نشان می‌دهیم
      style = (style ?? const TextStyle()).copyWith(
        color: Colors.transparent,
        backgroundColor: theme.colorScheme.onSurface.withAlpha(180),
      );
    }

    if (style == null) return TextSpan(text: segment);
    return TextSpan(text: segment, style: style);
  }

  String? _resolveLink(MessageEntity e, String segment) {
    if (e.isTextLink && e.url != null) return e.url;
    if (e.isTextMention && e.userId != null) return 'tg://user?id=${e.userId}';
    if (e.isUrl) {
      final t = segment.trim();
      if (t.startsWith('http://') || t.startsWith('https://')) return t;
      return 'https://$t';
    }
    if (e.isEmail) return 'mailto:$segment';
    if (e.isPhone) return 'tel:${segment.replaceAll(' ', '')}';
    if (e.isMention) return 'tg://resolve?domain=${segment.substring(1)}';
    if (e.isHashtag) {
      final tag = segment.replaceFirst('#', '').replaceFirst('\$', '');
      return 'tg://search?query=$tag';
    }
    if (e.isBotCommand) {
      return 'https://t.me/${segment.substring(1)}';
    }
    return null;
  }

  Future<void> _open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[FormattedMessageText] open failed: $raw — $e');
    }
  }
}

// ═════════════════════════════════════════════
//  Blockquote box (RTL-aware)
// ═════════════════════════════════════════════

class _BlockquoteBox extends StatelessWidget {
  final Widget child;
  const _BlockquoteBox({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withAlpha(15),
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.primary.withAlpha(180),
            width: 3,
          ),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

class _TextBlock {
  final String text;
  final List<MessageEntity> entities;
  final bool isBlockquote;
  const _TextBlock({
    required this.text,
    required this.entities,
    this.isBlockquote = false,
  });
}

// ═════════════════════════════════════════════
//  Fallback — وقتی entity نداریم، مثل LinkifiedText
// ═════════════════════════════════════════════

class _FallbackLinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  const _FallbackLinkifiedText({
    required this.text,
    this.style,
    this.linkStyle,
  });

  static final RegExp _pattern = RegExp(
    r'(tg://[^\s]+)'
    r'|(https?://t\.me/[^\s]+)'
    r'|(https?://[^\s]+)'
    r'|(@[A-Za-z][A-Za-z0-9_]{4,31})',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveLink = linkStyle ??
        TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        );

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final raw = m.group(0)!;
      final tgUri = _toTg(raw);
      final rec = TapGestureRecognizer()
        ..onTap = () => _open(tgUri ?? raw);
      spans.add(TextSpan(text: raw, style: effectiveLink, recognizer: rec));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }

  String? _toTg(String raw) {
    if (raw.startsWith('@')) {
      return 'tg://resolve?domain=${raw.substring(1)}';
    }
    if (raw.toLowerCase().startsWith('tg://')) return raw;
    final lower = raw.toLowerCase();
    if (lower.contains('t.me/')) {
      try {
        final uri = Uri.parse(lower.startsWith('http') ? raw : 'https://$raw');
        final seg = uri.pathSegments;
        if (seg.isEmpty) return null;
        if (seg[0] == 'c' && seg.length >= 3) {
          return 'tg://privatepost?channel=${seg[1]}&post=${seg[2]}';
        }
        if (seg.length >= 2) {
          return 'tg://resolve?domain=${seg[0]}&post=${seg[1]}';
        }
        return 'tg://resolve?domain=${seg[0]}';
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _open(String raw) async {
    var normalized = raw;
    if (!raw.toLowerCase().startsWith('tg://') &&
        !raw.toLowerCase().startsWith('http') &&
        !raw.toLowerCase().startsWith('mailto:') &&
        !raw.toLowerCase().startsWith('tel:')) {
      normalized = 'https://$raw';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[FormattedMessageText] fallback open failed: $e');
    }
  }
}