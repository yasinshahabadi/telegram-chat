import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:telegram_chat_mobile/core/network/network_monitor.dart';
import 'package:telegram_chat_mobile/features/auth/data/auth_repository.dart';
import 'package:telegram_chat_mobile/features/auth/domain/models/auth_user.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';
import 'package:telegram_chat_mobile/features/media/data/media_download_manager.dart';
import 'package:telegram_chat_mobile/features/media/data/media_remote_service.dart';
import 'package:telegram_chat_mobile/features/media/data/voice_record_service.dart';

/// هماهنگ‌کنندهٔ منطق ارسال فایل (انتخاب، ضبط صدا، آپلود، retry).
///
/// این کلاس stateless است و هیچ state داخلی ندارد. تمام state تعاملی
/// (reply target، scroll، نمایش خطا) از طریق callback به `ChatScreen` برمی‌گردد.
///
/// چرا از callback استفاده می‌کنیم؟
///   چون منطق آپلود به `BuildContext` و `setState` وابسته نیست، ولی
///   «واکنش به نتیجه» به این‌ها وابسته است. جدا کردن این دو، تست‌پذیری و
///   خوانایی را بالا می‌برد.
class ChatUploadCoordinator {
  final AuthRepository authRepository;
  final ChatRepository chatRepository;
  final VoiceRecordService voiceRecordService;
  final MediaRemoteService mediaRemoteService;

  /// reply فعلی را از `ChatScreen` می‌پرسد (چون ممکن است بین start و end
  /// آپلود تغییر کند).
  final ChatMessageModel? Function() getReplyTarget;

  /// پس از شروع آپلود optimistic، reply را پاک می‌کند.
  final void Function() onClearReplyTarget;

  /// نمایش خطا به کاربر.
  final void Function(String message) onError;

  /// پیمایش لیست به پایین (پس از ارسال).
  final void Function() onScrollToBottom;

  /// چک می‌کند که screen هنوز mount است.
  final bool Function() isMounted;

  ChatUploadCoordinator({
    required this.authRepository,
    required this.chatRepository,
    required this.voiceRecordService,
    required this.getReplyTarget,
    required this.onClearReplyTarget,
    required this.onError,
    required this.onScrollToBottom,
    required this.isMounted,
    MediaRemoteService? mediaRemoteService,
  }) : mediaRemoteService = mediaRemoteService ?? MediaRemoteService();

  // ═════════════════════════════════════════════
  //  Voice
  // ═════════════════════════════════════════════

  /// شروع ضبط صدا. اگر دسترسی داده نشد، پیام خطا می‌دهد.
  Future<void> startVoiceRecord() async {
    final started = await voiceRecordService.startRecording();
    if (!started && isMounted()) {
      onError('دسترسی به میکروفون داده نشد.');
    }
  }

  /// توقف ضبط + ارسال فایل صوتی با optimistic UI.
  Future<void> stopAndSendVoice() async {
    final path = await voiceRecordService.stopRecording();
    if (path == null) return;

    final user = authRepository.currentUser;
    final token = authRepository.sessionToken;
    if (user == null || token == null) {
      onError('جلسه منقضی شده است. لطفاً مجدداً وارد شوید.');
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    await _uploadFilesWithOptimisticUI(
      files: [file],
      mediaTypes: const ['voice'],
      originalNames: [file.uri.pathSegments.last],
      token: token,
      user: user,
      replyTarget: getReplyTarget(),
    );
  }

  // ═════════════════════════════════════════════
  //  Pick & send
  // ═════════════════════════════════════════════

  /// انتخاب چند فایل از گالری/فایل‌منیجر + آپلود.
  Future<void> pickAndSendFiles(FileType type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final validFiles = <File>[];
      final mediaTypes = <String>[];
      final originalNames = <String>[];

      for (final pf in result.files) {
        if (pf.path == null) continue;
        final file = File(pf.path!);
        if (!await file.exists()) continue;

        final name = pf.name;
        final ext = name.split('.').last.toLowerCase();
        String mediaType = 'document';
        if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif']
            .contains(ext)) {
          mediaType = 'photo';
        } else if (['mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v']
            .contains(ext)) {
          mediaType = 'video';
        } else if (['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'].contains(ext)) {
          mediaType = 'audio';
        }

        validFiles.add(file);
        mediaTypes.add(mediaType);
        originalNames.add(name);
      }

      if (validFiles.isEmpty) return;

      final user = authRepository.currentUser;
      final token = authRepository.sessionToken;
      if (user == null || token == null) {
        onError('جلسه منقضی شده است. لطفاً مجدداً وارد شوید.');
        return;
      }

      await _uploadFilesWithOptimisticUI(
        files: validFiles,
        mediaTypes: mediaTypes,
        originalNames: originalNames,
        token: token,
        user: user,
        replyTarget: getReplyTarget(),
      );
    } catch (e) {
      onError('خطا در انتخاب فایل: $e');
    }
  }

  // ═════════════════════════════════════════════
  //  Retry
  // ═════════════════════════════════════════════

  /// تلاش مجدد برای ارسال پیام ناموفق با فایل‌های ذخیره‌شده در storage داخلی.
  Future<void> retryUpload(ChatMessageModel message, String newText) async {
    final user = authRepository.currentUser;
    final token = authRepository.sessionToken;
    if (user == null || token == null) {
      onError('جلسه منقضی شده است. لطفاً مجدداً وارد شوید.');
      return;
    }

    if (!NetworkMonitor.instance.isOnline) {
      onError('اتصال اینترنت برقرار نیست.');
      return;
    }

    final files = <File>[];
    final originalNames = <String>[];
    final mediaTypes = <String>[];

    for (final att in message.attachments) {
      final path = att.localPath;
      if (path == null) continue;
      final f = File(path);
      if (!await f.exists()) continue;
      files.add(f);
      originalNames.add(att.fileName);
      mediaTypes.add(att.mediaType);
    }

    if (files.isEmpty) {
      onError('فایل اصلی یافت نشد. لطفاً دوباره ارسال کنید.');
      return;
    }

    chatRepository.prepareForRetry(message.id, newText: newText);

    try {
      final result = await mediaRemoteService.uploadFiles(
        files: files,
        mediaTypes: mediaTypes,
        originalNames: originalNames,
        sessionToken: token,
        caption: newText,
        clientMessageId: message.clientMessageId,
        replyTo: message.replyToMessageId != null
            ? {
                'id': message.replyToMessageId,
                'name': message.replyToName,
                'text': message.replyToText,
                'tgMsgId': null,
              }
            : null,
        onProgress: (p) {
          chatRepository.updateUploadProgress(message.id, p);
        },
      );

      if (!isMounted()) return;

      if (!result.isSuccess || result.messageId == null) {
        await chatRepository.failUpload(message.id, result.error ?? 'خطا');
        onError(result.error ?? 'خطا در آپلود فایل');
        return;
      }

      chatRepository.finalizeMultiUpload(
        tempId: message.id,
        clientMessageId: message.clientMessageId,
        realMessageId: result.messageId!,
        attachments: result.attachments,
      );

      onScrollToBottom();
    } catch (e) {
      if (!isMounted()) return;
      await chatRepository.failUpload(message.id, e.toString());
      onError('خطا در ارسال فایل: $e');
    }
  }

  // ═════════════════════════════════════════════
  //  Core upload pipeline
  // ═════════════════════════════════════════════

  Future<void> _uploadFilesWithOptimisticUI({
    required List<File> files,
    required List<String> mediaTypes,
    required List<String> originalNames,
    required String token,
    required AuthUser user,
    required ChatMessageModel? replyTarget,
  }) async {
    final optimistic = await chatRepository.addOptimisticMultiUpload(
      files: files,
      mediaTypes: mediaTypes,
      currentUser: user,
      replyTo: replyTarget,
    );
    final tempId = optimistic.id;
    final clientMessageId = optimistic.clientMessageId;

    if (!isMounted()) return;

    onClearReplyTarget();
    onScrollToBottom();

    if (!NetworkMonitor.instance.isOnline) {
      await chatRepository.failUpload(tempId, 'offline');
      onError('اتصال اینترنت برقرار نیست.');
      return;
    }

    try {
      final result = await mediaRemoteService.uploadFiles(
        files: files,
        mediaTypes: mediaTypes,
        originalNames: originalNames,
        sessionToken: token,
        clientMessageId: clientMessageId,
        replyTo: replyTarget != null
            ? {
                'id': replyTarget.id,
                'name': replyTarget.senderName,
                'text': replyTarget.text,
                'tgMsgId': replyTarget.telegramMessageId,
              }
            : null,
        onProgress: (p) {
          chatRepository.updateUploadProgress(tempId, p);
        },
      );

      if (!isMounted()) return;

      if (!result.isSuccess || result.messageId == null) {
        await chatRepository.failUpload(tempId, result.error ?? 'خطا');
        onError(result.error ?? 'خطا در آپلود فایل');
        return;
      }

      chatRepository.finalizeMultiUpload(
        tempId: tempId,
        clientMessageId: clientMessageId,
        realMessageId: result.messageId!,
        attachments: result.attachments,
      );

      for (int i = 0;
          i < result.attachments.length && i < files.length;
          i++) {
        try {
          final cached = await MediaDownloadManager.instance.cacheUploadedFile(
            attachmentId: result.attachments[i].id,
            sourcePath: files[i].path,
            originalFileName: originalNames[i],
          );
          if (cached != null) {
            chatRepository.setLocalPathForAttachment(
              result.messageId!,
              result.attachments[i].id,
              cached.path,
            );
          }
        } catch (e) {
          debugPrint('Cache uploaded file failed: $e');
        }
      }

      onScrollToBottom();
    } catch (e) {
      if (!isMounted()) return;
      await chatRepository.failUpload(tempId, e.toString());
      onError('خطا در ارسال فایل: $e');
    }
  }
}