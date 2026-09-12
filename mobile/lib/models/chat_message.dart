// lib/models/chat_message.dart
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  String text;
  final bool isFromTelegram;
  final int timestamp;
  final String? replyToName;
  final String? replyToText;
  final String? replyToId;
  final int? tgMsgId;
  int isRead;
  int? readAt;
  bool isEdited;
  final String? mediaType;
  final String? mediaFileId;
  final String? mediaFileName;
  final int? mediaFileSize;
  final String? mediaThumbId;
  final int? mediaDuration;
  Map<String, List<String>> reactions;

  // اطلاعات پست‌های فورواردشده و آلبوم‌ها
  final String? forwardFromName;
  final String? forwardChannelUsername;
  final int? forwardPostId;
  final String? forwardChatId;
  final String? mediaGroupId;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.isFromTelegram,
    required this.timestamp,
    this.replyToName,
    this.replyToText,
    this.replyToId,
    this.tgMsgId,
    this.isRead = 0,
    this.readAt,
    this.isEdited = false,
    this.mediaType,
    this.mediaFileId,
    this.mediaFileName,
    this.mediaFileSize,
    this.mediaThumbId,
    this.mediaDuration,
    required this.reactions,
    this.forwardFromName,
    this.forwardChannelUsername,
    this.forwardPostId,
    this.forwardChatId,
    this.mediaGroupId,
  });

  String get formattedTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('HH:mm').format(dt);
  }

  String get formattedReadTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(readAt ?? timestamp);
    return DateFormat('HH:mm').format(dt);
  }

  String get formattedFileSize {
    if (mediaFileSize == null || mediaFileSize == 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = mediaFileSize!.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get formattedDuration {
    if (mediaDuration == null || mediaDuration == 0) return '0:00';
    final m = mediaDuration! ~/ 60;
    final s = mediaDuration! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String? get mediaUrl {
    if (mediaFileId == null || mediaFileId!.isEmpty) return null;
    return '${AppConfig.baseUrl}/api/media?fileId=$mediaFileId';
  }

  String? get thumbUrl {
    if (mediaThumbId != null && mediaThumbId!.isNotEmpty) {
      return '${AppConfig.baseUrl}/api/media?fileId=$mediaThumbId';
    }
    return mediaUrl;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> parsedReactions = {};
    if (json['reactions'] != null) {
      dynamic rx = json['reactions'];
      if (rx is String) {
        try {
          rx = jsonDecode(rx);
        } catch (_) {}
      }
      if (rx is Map) {
        rx.forEach((key, val) {
          if (val is List) {
            parsedReactions[key.toString()] = val.map((e) => e.toString()).toList();
          }
        });
      }
    }

    return ChatMessage(
      id: json['id'] ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name'] ?? 'کاربر',
      text: json['text'] ?? '',
      isFromTelegram: (json['is_from_telegram'] == 1 || json['is_from_telegram'] == true),
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      replyToName: json['reply_to_name'],
      replyToText: json['reply_to_text'],
      replyToId: json['reply_to_id'],
      tgMsgId: json['tg_msg_id'],
      isRead: json['is_read'] ?? 0,
      readAt: json['read_at'],
      isEdited: json['is_edited'] == 1 || json['is_edited'] == true,
      mediaType: json['media_type'],
      mediaFileId: json['media_file_id'],
      mediaFileName: json['media_file_name'],
      mediaFileSize: json['media_file_size'],
      mediaThumbId: json['media_thumb_id'],
      mediaDuration: json['media_duration'],
      reactions: parsedReactions,
      forwardFromName: json['forward_from_name'],
      forwardChannelUsername: json['forward_channel_username'],
      forwardPostId: json['forward_post_id'],
      forwardChatId: json['forward_chat_id'],
      mediaGroupId: json['media_group_id'],
    );
  }
}