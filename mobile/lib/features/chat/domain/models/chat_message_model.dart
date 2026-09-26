import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

enum MessageStatus {
  pending,
  sending,
  synced,
  failed;

  static MessageStatus fromString(String? val) {
    switch (val) {
      case 'pending': return MessageStatus.pending;
      case 'sending': return MessageStatus.sending;
      case 'failed':  return MessageStatus.failed;
      case 'synced':
      default:        return MessageStatus.synced;
    }
  }

  String get name => toString().split('.').last;
}

class ChatMessageModel {
  final String id;
  final String? clientMessageId;
  final String senderId;
  final String senderName;
  final String text;
  final bool isFromTelegram;
  final int? telegramMessageId;
  final String? replyToMessageId;
  final String? replyToName;
  final String? replyToText;
  final String? replyToMediaType;
  final String? replyToAttachmentId;
  final String? replyToTelegramFileId;
  final String? replyToFileName;
  final int? replyToDuration;
  final bool isPinned;
  final bool isEdited;
  final MessageStatus status;
  final int? readAt;
  final int createdAt;
  final int updatedAt;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final List<MediaAttachmentModel> attachments;
  final double uploadProgress;
  final bool isUploading;

  const ChatMessageModel({
    required this.id,
    this.clientMessageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.isFromTelegram = false,
    this.telegramMessageId,
    this.replyToMessageId,
    this.replyToName,
    this.replyToText,
    this.replyToMediaType,
    this.replyToAttachmentId,
    this.replyToTelegramFileId,
    this.replyToFileName,
    this.replyToDuration,
    this.isPinned = false,
    this.isEdited = false,
    this.status = MessageStatus.synced,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
    this.reactions = const {},
    this.myReactions = const {},
    this.attachments = const [],
    this.uploadProgress = 1.0,
    this.isUploading = false,
  });

  MediaAttachmentModel? get attachment =>
      attachments.isEmpty ? null : attachments.first;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get replyHasMedia =>
      (replyToMediaType ?? '').isNotEmpty &&
      (replyToTelegramFileId ?? '').isNotEmpty;

  factory ChatMessageModel.fromDbMap(
    Map<String, dynamic> map, {
    Map<String, int> reactions = const {},
    Set<String> myReactions = const {},
    List<MediaAttachmentModel> attachments = const [],
  }) {
    return ChatMessageModel(
      id: map['id'] as String? ?? '',
      clientMessageId: map['client_message_id'] as String?,
      senderId: map['sender_id'] as String? ?? '',
      senderName: map['sender_name'] as String? ?? 'کاربر',
      text: map['text'] as String? ?? '',
      isFromTelegram: (map['is_from_telegram'] as int? ?? 0) == 1,
      telegramMessageId: map['telegram_message_id'] as int?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      replyToName: map['reply_to_name'] as String?,
      replyToText: map['reply_to_text'] as String?,
      replyToMediaType: map['reply_to_media_type'] as String?,
      replyToAttachmentId: map['reply_to_attachment_id'] as String?,
      replyToTelegramFileId: map['reply_to_telegram_file_id'] as String?,
      replyToFileName: map['reply_to_file_name'] as String?,
      replyToDuration: map['reply_to_duration'] as int?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isEdited: (map['is_edited'] as int? ?? 0) == 1,
      status: MessageStatus.fromString(map['status'] as String?),
      readAt: map['read_at'] as int?,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      reactions: reactions,
      myReactions: myReactions,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'client_message_id': clientMessageId,
      'sender_id': senderId,
      'sender_name': senderName,
      'text': text,
      'is_from_telegram': isFromTelegram ? 1 : 0,
      'telegram_message_id': telegramMessageId,
      'reply_to_message_id': replyToMessageId,
      'reply_to_name': replyToName,
      'reply_to_text': replyToText,
      'reply_to_media_type': replyToMediaType,
      'reply_to_attachment_id': replyToAttachmentId,
      'reply_to_telegram_file_id': replyToTelegramFileId,
      'reply_to_file_name': replyToFileName,
      'reply_to_duration': replyToDuration,
      'is_pinned': isPinned ? 1 : 0,
      'is_edited': isEdited ? 1 : 0,
      'status': status.name,
      'read_at': readAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ChatMessageModel.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final List<MediaAttachmentModel> atts = [];
    if (json['attachments'] is List) {
      for (final a in (json['attachments'] as List)) {
        if (a is Map<String, dynamic>) {
          atts.add(MediaAttachmentModel.fromJson(a));
        }
      }
    } else if (json['attachment'] is Map<String, dynamic>) {
      atts.add(MediaAttachmentModel.fromJson(json['attachment'] as Map<String, dynamic>));
    }

    final reactionsMap = <String, int>{};
    final myReactionsSet = <String>{};
    if (json['reactions'] is List) {
      for (final raw in (json['reactions'] as List)) {
        if (raw is! Map) continue;
        final emoji = raw['emoji'] as String?;
        if (emoji == null || emoji.isEmpty) continue;
        final count = (raw['count'] as num?)?.toInt() ?? 1;
        reactionsMap[emoji] = count;
        if (currentUserId != null && raw['userIds'] is List) {
          final ids = (raw['userIds'] as List).whereType<String>();
          if (ids.contains(currentUserId)) {
            myReactionsSet.add(emoji);
          }
        }
      }
    }

    return ChatMessageModel(
      id: json['id'] as String? ?? '',
      clientMessageId: json['clientMessageId'] as String? ?? json['client_message_id'] as String?,
      senderId: json['senderId'] as String? ?? json['sender_id'] as String? ?? '',
      senderName: json['senderName'] as String? ?? json['sender_name'] as String? ?? 'کاربر',
      text: json['text'] as String? ?? '',
      isFromTelegram: json['isFromTelegram'] == true || json['is_from_telegram'] == 1,
      telegramMessageId: json['telegramMessageId'] as int? ?? json['tg_msg_id'] as int?,
      replyToMessageId: json['replyToId'] as String? ?? json['reply_to_id'] as String?,
      replyToName: json['replyToName'] as String? ?? json['reply_to_name'] as String?,
      replyToText: json['replyToText'] as String? ?? json['reply_to_text'] as String?,
      replyToMediaType: json['replyToMediaType'] as String? ?? json['reply_to_media_type'] as String?,
      replyToAttachmentId: json['replyToAttachmentId'] as String? ?? json['reply_to_attachment_id'] as String?,
      replyToTelegramFileId: json['replyToTelegramFileId'] as String? ?? json['reply_to_telegram_file_id'] as String?,
      replyToFileName: json['replyToFileName'] as String? ?? json['reply_to_file_name'] as String?,
      replyToDuration: json['replyToDuration'] as int? ?? json['reply_to_duration'] as int?,
      isPinned: json['isPinned'] == true || json['is_pinned'] == 1,
      isEdited: json['isEdited'] == true || json['is_edited'] == 1,
      status: MessageStatus.synced,
      readAt: json['readAt'] as int? ?? json['read_at'] as int?,
      createdAt: json['createdAt'] as int? ?? json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      reactions: reactionsMap,
      myReactions: myReactionsSet,
      attachments: atts,
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? clientMessageId,
    String? senderId,
    String? senderName,
    String? text,
    bool? isFromTelegram,
    int? telegramMessageId,
    String? replyToMessageId,
    String? replyToName,
    String? replyToText,
    String? replyToMediaType,
    String? replyToAttachmentId,
    String? replyToTelegramFileId,
    String? replyToFileName,
    int? replyToDuration,
    bool? isPinned,
    bool? isEdited,
    MessageStatus? status,
    int? readAt,
    int? createdAt,
    int? updatedAt,
    Map<String, int>? reactions,
    Set<String>? myReactions,
    List<MediaAttachmentModel>? attachments,
    double? uploadProgress,
    bool? isUploading,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      isFromTelegram: isFromTelegram ?? this.isFromTelegram,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToName: replyToName ?? this.replyToName,
      replyToText: replyToText ?? this.replyToText,
      replyToMediaType: replyToMediaType ?? this.replyToMediaType,
      replyToAttachmentId: replyToAttachmentId ?? this.replyToAttachmentId,
      replyToTelegramFileId: replyToTelegramFileId ?? this.replyToTelegramFileId,
      replyToFileName: replyToFileName ?? this.replyToFileName,
      replyToDuration: replyToDuration ?? this.replyToDuration,
      isPinned: isPinned ?? this.isPinned,
      isEdited: isEdited ?? this.isEdited,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      attachments: attachments ?? this.attachments,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isUploading: isUploading ?? this.isUploading,
    );
  }

  String get formattedTime {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool get isPending => status == MessageStatus.pending;
  bool get isSending => status == MessageStatus.sending;
  bool get isSynced  => status == MessageStatus.synced;
  bool get isFailed  => status == MessageStatus.failed;
  bool get isRead    => readAt != null;
}