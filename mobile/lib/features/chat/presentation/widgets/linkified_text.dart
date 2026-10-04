import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// ویجت متن با تشخیص خودکار لینک‌ها و منشن‌ها.
///
/// الگوهای شناسایی‌شده:
///   - `@username`              → tg://resolve?domain=username
///   - `t.me/username`          → tg://resolve?domain=username
///   - `t.me/username/123`      → tg://resolve?domain=username&post=123
///   - `t.me/c/12345/678`       → tg://privatepost?channel=12345&post=678
///   - `https://t.me/...`       → تبدیل به tg:// (باز شدن مستقیم تلگرام)
///   - `tg://...`               → بدون تغییر
///   - `https://...`            → بدون تغییر (مرورگر)
///   - `http://...`             → بدون تغییر (مرورگر)
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
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

    final effectiveLinkStyle = linkStyle ??
        TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        );

    final spans = _parse(text, effectiveLinkStyle);

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: style,
        children: spans,
      ),
    );
  }

  List<InlineSpan> _parse(String input, TextStyle linkStyle) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _pattern.allMatches(input)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: input.substring(lastEnd, match.start)));
      }

      final matched = match.group(0)!;
      final tgUri = _toTelegramUri(matched);

      final recognizer = TapGestureRecognizer()
        ..onTap = () => _open(tgUri ?? matched);

      spans.add(TextSpan(
        text: matched,
        style: linkStyle,
        recognizer: recognizer,
      ));

      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd)));
    }

    return spans;
  }

  String? _toTelegramUri(String raw) {
    if (raw.startsWith('@')) {
      final username = raw.substring(1);
      return 'tg://resolve?domain=$username';
    }

    if (raw.toLowerCase().startsWith('tg://')) {
      return raw;
    }

    final lower = raw.toLowerCase();
    if (lower.contains('t.me/')) {
      try {
        final uri = Uri.parse(lower.startsWith('http') ? raw : 'https://$raw');
        final segments = uri.pathSegments;
        if (segments.isEmpty) return null;

        if (segments[0] == 'c' && segments.length >= 3) {
          final channelId = segments[1];
          final messageId = segments[2];
          return 'tg://privatepost?channel=$channelId&post=$messageId';
        }

        final username = segments[0];
        if (segments.length >= 2) {
          final messageId = segments[1];
          return 'tg://resolve?domain=$username&post=$messageId';
        }
        return 'tg://resolve?domain=$username';
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  Future<void> _open(String raw) async {
    String normalized = raw;
    if (!raw.toLowerCase().startsWith('tg://') &&
        !raw.toLowerCase().startsWith('http')) {
      normalized = 'https://$raw';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[LinkifiedText] Cannot launch: $normalized');
      }
    } catch (e) {
      debugPrint('[LinkifiedText] Failed to open $normalized: $e');
    }
  }
}