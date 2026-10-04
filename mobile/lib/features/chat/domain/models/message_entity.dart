import 'dart:convert';

/// مدل یک entity تلگرام (bold, italic, link, blockquote, ...).
///
/// ساختار مطابق Bot API 7.x:
///   { "type": "bold", "offset": 0, "length": 5 }
///   { "type": "text_link", "offset": 10, "length": 8, "url": "..." }
///   { "type": "blockquote", "offset": 20, "length": 40 }
///
/// offset و length بر حسب UTF-16 code units هستند (همان چیزی که
/// Dart String استفاده می‌کند — پس substring مستقیم کار می‌کند).
class MessageEntity {
  final String type;
  final int offset;
  final int length;

  /// برای `text_link`
  final String? url;

  /// برای `text_mention` — شناسهٔ کاربر تلگرام
  final String? userId;

  /// برای `pre` — زبان برنامه‌نویسی
  final String? language;

  const MessageEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url,
    this.userId,
    this.language,
  });

  int get end => offset + length;

  bool get isBold => type == 'bold';
  bool get isItalic => type == 'italic';
  bool get isUnderline => type == 'underline';
  bool get isStrikethrough => type == 'strikethrough';
  bool get isSpoiler => type == 'spoiler';
  bool get isCode => type == 'code';
  bool get isPre => type == 'pre';
  bool get isTextLink => type == 'text_link';
  bool get isTextMention => type == 'text_mention';
  bool get isUrl => type == 'url';
  bool get isEmail => type == 'email';
  bool get isPhone => type == 'phone_number';
  bool get isMention => type == 'mention';
  bool get isHashtag => type == 'hashtag' || type == 'cashtag';
  bool get isBotCommand => type == 'bot_command';
  bool get isBlockquote =>
      type == 'blockquote' || type == 'expandable_blockquote';

  bool get isLink =>
      isTextLink || isTextMention || isUrl || isEmail || isPhone ||
      isMention || isHashtag || isBotCommand;

  /// لینکی که این entity باید باز کند (یا null اگر لینک نیست).
  String? get resolvedUrl {
    if (url != null && url!.isNotEmpty) return url;
    if (isTextMention && userId != null) return 'tg://user?id=$userId';
    if (isUrl) return null; // خود متن URL است — در render حل می‌شود
    return null;
  }

  factory MessageEntity.fromJson(Map<String, dynamic> json) {
    return MessageEntity(
      type: json['type'] as String? ?? '',
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      length: (json['length'] as num?)?.toInt() ?? 0,
      url: json['url'] as String?,
      userId: json['user'] != null
          ? (json['user']['id']?.toString())
          : null,
      language: json['language'] as String?,
    );
  }

  /// برای shift دادن offset پس از برش متن.
  MessageEntity shifted(int delta) => MessageEntity(
        type: type,
        offset: offset + delta,
        length: length,
        url: url,
        userId: userId,
        language: language,
      );

  /// پارس لیست entityها از یک رشتهٔ JSON یا از یک List.
  static List<MessageEntity> parseList(dynamic raw) {
    if (raw == null) return const [];
    List<dynamic> list;
    if (raw is String) {
      if (raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const [];
        list = decoded;
      } catch (_) {
        return const [];
      }
    } else if (raw is List) {
      list = raw;
    } else {
      return const [];
    }

    final result = <MessageEntity>[];
    for (final item in list) {
      if (item is Map) {
        try {
          result.add(MessageEntity.fromJson(item.cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    return result;
  }
}