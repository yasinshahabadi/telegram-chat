import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:telegram_chat_mobile/core/database/local_chat_dao.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/data/media_local_storage.dart';
import 'package:telegram_chat_mobile/features/media/domain/models/media_attachment_model.dart';

/// اطلاعات پیش‌نمایش reply برای استفاده در payload socket و DB.
class ReplyPreviewInfo {
  final String messageId;
  final String name;
  final String text;
  final String? mediaType;
  final String? attachmentId;
  final String? telegramFileId;
  final String? fileName;
  final int? duration;

  const ReplyPreviewInfo({
    required this.messageId,
    required this.name,
    required this.text,
    this.mediaType,
    this.attachmentId,
    this.telegramFileId,
    this.fileName,
    this.duration,
  });

  /// استخراج از یک `ChatMessageModel` که هدف reply است.
  static ReplyPreviewInfo? from(ChatMessageModel? replyTo) {
    if (replyTo == null) return null;
    final att =
        replyTo.attachments.isNotEmpty ? replyTo.attachments.first : null;
    return ReplyPreviewInfo(
      messageId: replyTo.id,
      name: replyTo.senderName,
      text: replyTo.text,
      mediaType: att?.mediaType,
      attachmentId: att?.id,
      telegramFileId: att?.telegramFileId,
      fileName: att?.fileName,
      duration: att?.duration,
    );
  }

  /// payload برای socket message.
  Map<String, dynamic> toSocketPayload({int? tgMsgId}) {
    return {
      'id': messageId,
      'name': name,
      'text': text,
      'tgMsgId': tgMsgId,
    };
  }
}

/// چرخهٔ ساخت و ویرایش پیام‌ها با optimistic UI.
///
/// مسئولیت‌ها:
///   - ساخت پیام متنی optimistic + ذخیره در DB
///   - ساخت پیام چندفایلی optimistic (کپی فایل به storage داخلی) + DB
///   - به‌روزرسانی progress آپلود
///   - finalize آپلود پس از موفقیت
///   - علامت‌گذاری ناموفق
///   - آماده‌سازی برای retry
///   - به‌روزرسانی localPath پس از دانلود/کش
///
/// چرا stateless با callback؟ چون state داخلی `_messages` در ChatRepository
/// مالکیت دارد و این کلاس فقط manipulator است.
class UploadLifecycle {
  final LocalChatDao localDao;
  final MediaLocalStorage mediaStorage;
  final List<ChatMessageModel> Function() getMessages;
  final void Function() notify;

  UploadLifecycle({
    required this.localDao,
    MediaLocalStorage? mediaStorage,
    required this.getMessages,
    required this.notify,
  }) : mediaStorage = mediaStorage ?? MediaLocalStorage();

  // ═════════════════════════════════════════════
  //  Text message
  // ═════════════════════════════════════════════

  /// ساخت پیام متنی optimistic + ذخیره در DB + افزودن به `_messages`.
  Future<ChatMessageModel> createOptimisticText({
    required String text,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = const Uuid().v4();
    final clientMessageId = const Uuid().v4();
    final rp = ReplyPreviewInfo.from(replyTo);

    final newMessage = ChatMessageModel(
      id: messageId,
      clientMessageId: clientMessageId,
      senderId: currentUser.id,
      senderName: currentUser.fullName,
      text: text,
      isFromTelegram: false,
      replyToMessageId: rp?.messageId,
      replyToName: rp?.name,
      replyToText: rp?.text,
      replyToMediaType: rp?.mediaType,
      replyToAttachmentId: rp?.attachmentId,
      replyToTelegramFileId: rp?.telegramFileId,
      replyToFileName: rp?.fileName,
      replyToDuration: rp?.duration,
      status: MessageStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    getMessages().insert(0, newMessage);
    notify();

    try {
      await localDao.saveMessage(newMessage.toDbMap());
    } catch (e) {
      debugPrint('[UploadLifecycle] saveMessage (text) failed: $e');
    }

    return newMessage;
  }

  // ═════════════════════════════════════════════
  //  Multi-file upload
  // ═════════════════════════════════════════════

  /// ساخت پیام چندفایلی optimistic + کپی فایل‌ها به storage داخلی + DB.
  ///
  /// مزیت کپی قبل از آپلود:
  ///   - فایل اصلی (از file_picker cache) توسط سیستم پاک نمی‌شود.
  ///   - پس از قطعی اینترنت، retry با همان فایل ممکن است.
  Future<ChatMessageModel> addOptimisticMultiUpload({
    required List<File> files,
    required List<String> mediaTypes,
    required AuthUser currentUser,
    ChatMessageModel? replyTo,
  }) async {
    final tempId = 'temp_upload_${const Uuid().v4()}';
    final clientMessageId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rp = ReplyPreviewInfo.from(replyTo);

    final optimisticAtts = <MediaAttachmentModel>[];
    for (int i = 0; i < files.length; i++) {
      final original = files[i];
      final attId = 'att_${tempId}_$i';
      final originalName = p.basename(original.path);

      File durable = original;
      try {
        final copied = await mediaStorage.saveFileFromPathForAttachment(
          original.path,
          attId,
          originalName,
        );
        if (copied != null) durable = copied;
      } catch (e) {
        debugPrint('[UploadLifecycle] Copy to storage failed: $e');
      }

      optimisticAtts.add(MediaAttachmentModel(
        id: attId,
        messageId: tempId,
        mediaType: mediaTypes[i],
        localPath: durable.path,
        fileName: originalName,
        isDownloaded: true,
        createdAt: now,
      ));
    }

    final optimistic = ChatMessageModel(
      id: tempId,
      clientMessageId: clientMessageId,
      senderId: currentUser.id,
      senderName: currentUser.fullName,
      text: '',
      isFromTelegram: false,
      replyToMessageId: rp?.messageId,
      replyToName: rp?.name,
      replyToText: rp?.text,
      replyToMediaType: rp?.mediaType,
      replyToAttachmentId: rp?.attachmentId,
      replyToTelegramFileId: rp?.telegramFileId,
      replyToFileName: rp?.fileName,
      replyToDuration: rp?.duration,
      status: MessageStatus.sending,
      createdAt: now,
      updatedAt: now,
      isUploading: true,
      uploadProgress: 0.0,
      attachments: optimisticAtts,
    );

    try {
      await localDao.saveMessage(optimistic.toDbMap());
      for (final a in optimisticAtts) {
        try {
          await localDao.saveAttachment(a.toDbMap());
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[UploadLifecycle] Failed to persist optimistic upload: $e');
    }

    getMessages().insert(0, optimistic);
    notify();
    return optimistic;
  }

  // ═════════════════════════════════════════════
  //  Progress / finalize / fail
  // ═════════════════════════════════════════════

  void updateUploadProgress(String tempId, double progress) {
    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(
      uploadProgress: progress.clamp(0.0, 1.0),
      isUploading: true,
      status: MessageStatus.sending,
    );
    notify();
  }

  /// نهایی‌سازی پس از آپلود موفق.
  ///
  /// پیام در حافظه id سرور را می‌گیرد، سپس در DB ذخیره می‌شود (rename branch).
  /// پیوست‌ها با id سرور به DB اضافه می‌شوند و local_path از نسخهٔ optimistic
  /// منتقل می‌شود.
  void finalizeMultiUpload({
    required String tempId,
    String? clientMessageId,
    required String realMessageId,
    required List<MediaAttachmentModel> attachments,
  }) {
    final messages = getMessages();
    int idx = messages.indexWhere((m) => m.id == tempId);
    if (idx == -1 && clientMessageId != null) {
      idx = messages.indexWhere((m) => m.clientMessageId == clientMessageId);
    }
    if (idx == -1) return;

    final old = messages[idx];
    final now = DateTime.now().millisecondsSinceEpoch;
    final mergedAtts = _mergeAttachmentsForUpload(old.attachments, attachments);

    messages[idx] = old.copyWith(
      id: realMessageId,
      status: MessageStatus.synced,
      isUploading: false,
      uploadProgress: 1.0,
      updatedAt: now,
      attachments: mergedAtts,
    );
    notify();

    // ✅ ابتدا پیام ذخیره می‌شود (rename branch قدیمی را حذف و جدید را insert
    //    می‌کند)، سپس پیوست‌ها با id جدید insert می‌شوند.
    localDao.saveMessage(messages[idx].toDbMap()).then((_) {
      for (final a in mergedAtts) {
        localDao.saveAttachment(a.toDbMap()).catchError((_) {});
      }
    }).catchError((_) {});
  }

  /// تغییر وضعیت به «ناموفق» + ذخیره در DB.
  Future<void> failUpload(String tempId, String error) async {
    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      messages[idx] = messages[idx].copyWith(
        status: MessageStatus.failed,
        isUploading: false,
      );
      notify();
    }
    try {
      await localDao.updateMessageStatus(tempId, 'failed');
    } catch (_) {}
  }

  /// آماده‌سازی پیام برای تلاش دوباره: وضعیت sending + متن اختیاری جدید.
  void prepareForRetry(String messageId, {String? newText}) {
    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final old = messages[idx];
    messages[idx] = old.copyWith(
      status: MessageStatus.sending,
      isUploading: true,
      uploadProgress: 0.0,
      text: newText ?? old.text,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    notify();
    localDao.saveMessage(messages[idx].toDbMap()).catchError((_) {});
  }

  // ═════════════════════════════════════════════
  //  Attachment path
  // ═════════════════════════════════════════════

  void setLocalPathForAttachment(
    String messageId,
    String attachmentId,
    String localPath,
  ) {
    localDao
        .updateAttachmentLocalPath(attachmentId, localPath)
        .catchError((_) {});

    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final msg = messages[idx];
    final atts = List<MediaAttachmentModel>.from(msg.attachments);
    final attIdx = atts.indexWhere((a) => a.id == attachmentId);
    if (attIdx == -1) return;

    atts[attIdx] = atts[attIdx].copyWith(
      localPath: localPath,
      isDownloaded: true,
    );
    messages[idx] = msg.copyWith(attachments: atts);
    notify();
  }

  // ═════════════════════════════════════════════
  //  Status helpers
  // ═════════════════════════════════════════════

  /// به‌روزرسانی وضعیت پیام فقط در حافظه (بدون DB).
  void updateStatusInMemory(String messageId, MessageStatus newStatus) {
    final messages = getMessages();
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(status: newStatus);
    notify();
  }

  // ═════════════════════════════════════════════
  //  Helpers
  // ═════════════════════════════════════════════

  List<MediaAttachmentModel> _mergeAttachmentsForUpload(
    List<MediaAttachmentModel> existing,
    List<MediaAttachmentModel> incoming,
  ) {
    if (incoming.isEmpty) return existing;

    final result = <MediaAttachmentModel>[];
    for (int i = 0; i < incoming.length; i++) {
      final inc = incoming[i];
      if (i < existing.length) {
        final ex = existing[i];
        result.add(inc.copyWith(
          localPath: inc.localPath ?? ex.localPath,
          isDownloaded: inc.isDownloaded || ex.isDownloaded,
        ));
      } else {
        result.add(inc);
      }
    }
    return result;
  }
}