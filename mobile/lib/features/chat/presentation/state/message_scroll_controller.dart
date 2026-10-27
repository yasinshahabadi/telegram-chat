import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';

/// نتیجهٔ تلاش برای پرش به یک پیام.
enum MessageScrollResult {
  /// پیام پیدا شد و ابتدای آن در بالای viewport قرار گرفت.
  reached,

  /// پیام در لیست فعلی (حافظه) وجود ندارد.
  notInList,

  /// لیست/کنترلر اسکرول هنوز آماده نیست.
  notReady,

  /// درخواست دیگری جای این درخواست را گرفت (مثلاً کاربر روی reply دیگری زد).
  cancelled,
}

/// پرش دقیق به یک پیام در لیست چت (برای «پاسخ به پیام»).
///
/// چرا این کلاس لازم است؟
/// لیست پیام‌ها `ListView.builder` با ارتفاع متغیر است و فقط آیتم‌های نزدیک
/// viewport ساخته می‌شوند. بنابراین نه می‌توان با یک تخمین ثابت (مثل ۹۰ پیکسل
/// برای هر پیام) دقیق اسکرول کرد، نه می‌توان در لحظهٔ کلیک به `GlobalKey`
/// پیام مقصد دسترسی داشت.
///
/// راهکار:
///   1. هر پیام یک `GlobalKey` پایدار دارد (تا وقتی ساخته شود).
///   2. ارتفاع آیتم‌های ساخته‌شده اندازه‌گیری و کش می‌شود.
///   3. با یک اسکرول تقریبی به نزدیکی مقصد می‌رویم، سپس در چند فریم متوالی
///      با اندازه‌گیری واقعی و `getOffsetToReveal` موقعیت را تصحیح می‌کنیم.
///   4. وقتی آیتم مقصد ساخته شد، `Scrollable.ensureVisible` با
///      `alignment: 1.0` ابتدای پیام را در بالای صفحه قرار می‌دهد.
///
/// در لیست reverse (پیام جدید پایین)، `alignment: 1.0` یعنی لبهٔ بالایی آیتم
/// روی لبهٔ بالایی viewport؛ همان چیزی که تلگرام هم انجام می‌دهد.
class MessageScrollController {
  /// ارتفاع تقریبی یک پیام وقتی هنوز هیچ آیتمی اندازه‌گیری نشده است.
  static const double _fallbackItemHeight = 88.0;

  /// حداقل/حداکثر ارتفاع معقول برای تخمین.
  static const double _minEstimatedHeight = 44.0;
  static const double _maxEstimatedHeight = 480.0;

  /// حداکثر تعداد فریم تصحیح بعد از پرش تقریبی.
  static const int _maxRefineAttempts = 10;

  /// نشانگر روزآمدِ فعلی؛ با هر درخواست جدید زیاد می‌شود تا درخواست‌های
  /// قدیمی خودبه‌خود لغو شوند.
  int _requestToken = 0;

  /// GlobalKey پایدار برای هر پیام (به‌ازای id).
  final Map<String, GlobalKey> _anchors = <String, GlobalKey>{};

  /// ارتفاع اندازه‌گیری‌شدهٔ هر پیام.
  final Map<String, double> _measuredHeights = <String, double>{};

  /// کلید پایدار پیام. اگر وجود نداشته باشد ساخته می‌شود.
  GlobalKey anchorFor(String messageId) {
    return _anchors.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'chat-message-$messageId'),
    );
  }

  /// حذف کلیدها/ارتفاع‌های پیام‌هایی که دیگر در لیست نیستند (جلوگیری از رشد
  /// بی‌پایان حافظه در نشست‌های طولانی).
  void pruneTo(Iterable<String> liveMessageIds) {
    final live = liveMessageIds.toSet();
    _anchors.removeWhere((id, _) => !live.contains(id));
    _measuredHeights.removeWhere((id, _) => !live.contains(id));
  }

  /// لغو پرش در جریان (مثلاً هنگام بستن صفحه).
  void cancel() {
    _requestToken++;
  }

  /// پرش به پیام [messageId] و قرار دادن ابتدای آن در بالای صفحه.
  Future<MessageScrollResult> scrollToMessage({
    required String messageId,
    required List<ChatMessageModel> Function() readMessages,
    required ScrollController? scrollController,
    Duration animationDuration = const Duration(milliseconds: 280),
  }) async {
    final controller = scrollController;
    if (controller == null || !controller.hasClients) {
      return MessageScrollResult.notReady;
    }

    if (!_contains(readMessages(), messageId)) {
      return MessageScrollResult.notInList;
    }

    final token = ++_requestToken;

    // مسیر سریع: آیتم همین حالا ساخته شده است (مثلاً پیام روی صفحه است).
    if (await _reveal(messageId, animationDuration)) {
      return _isCurrent(token)
          ? MessageScrollResult.reached
          : MessageScrollResult.cancelled;
    }

    // مسیر اصلی: یک پرش تقریبی، سپس تصحیح تدریجی با اندازه‌های واقعی.
    _captureHeights(readMessages());

    final firstGuess = _estimateOffset(
      readMessages(),
      controller,
      _indexOf(readMessages(), messageId),
    );

    // اگر مقصد چند صفحه دورتر است، پرش فوری انجام می‌دهیم؛ انیمیشن طولانی
    // باعث ساخته‌شدن صدها آیتم میانی (و کندی/فشار روی رندر متن) می‌شود.
    final farDistance = (firstGuess - controller.offset).abs() >
        controller.position.viewportDimension * 2;
    if (farDistance) {
      controller.jumpTo(_clampOffset(controller, firstGuess));
    } else {
      await _animateTo(controller, firstGuess, animationDuration);
    }
    if (!_isCurrent(token)) return MessageScrollResult.cancelled;

    for (int attempt = 0; attempt < _maxRefineAttempts; attempt++) {
      await _nextFrame();
      if (!_isCurrent(token)) return MessageScrollResult.cancelled;
      if (!controller.hasClients) return MessageScrollResult.notReady;

      final messages = readMessages();
      final index = _indexOf(messages, messageId);
      if (index < 0) return MessageScrollResult.notInList;

      if (await _reveal(messageId, const Duration(milliseconds: 140))) {
        return _isCurrent(token)
            ? MessageScrollResult.reached
            : MessageScrollResult.cancelled;
      }

      _captureHeights(messages);
      final nextGuess = _estimateOffset(messages, controller, index);
      final distance = (nextGuess - controller.offset).abs();
      if (distance < 0.5) {
        // تخمین دیگر تغییر نمی‌کند؛ برای جلوگیری از حلقهٔ بی‌پایان خارج می‌شویم.
        break;
      }

      if (distance > controller.position.viewportDimension * 2) {
        controller.jumpTo(_clampOffset(controller, nextGuess));
      } else {
        await _animateTo(
          controller,
          nextGuess,
          const Duration(milliseconds: 140),
        );
      }
      if (!_isCurrent(token)) return MessageScrollResult.cancelled;
    }

    // آخرین تلاش: ممکن است آیتم در همین فریم ساخته شده باشد.
    await _nextFrame();
    if (!_isCurrent(token)) return MessageScrollResult.cancelled;
    if (await _reveal(messageId, const Duration(milliseconds: 140))) {
      return MessageScrollResult.reached;
    }

    return MessageScrollResult.notReady;
  }

  // ═════════════════════════════════════════════
  //  Internals
  // ═════════════════════════════════════════════

  bool _isCurrent(int token) => token == _requestToken;

  bool _contains(List<ChatMessageModel> messages, String id) {
    for (final message in messages) {
      if (message.id == id) return true;
    }
    return false;
  }

  int _indexOf(List<ChatMessageModel> messages, String id) {
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].id == id) return i;
    }
    return -1;
  }

  /// اگر آدرس پیام وجود داشته و `alignment: 1.0` معتبر باشد، ابتدای پیام را
  /// بالای صفحه می‌آورد. `alignment: 1.0` برای لیست reverse دقیقاً یعنی همین.
  Future<bool> _reveal(String messageId, Duration duration) async {
    final context = _anchors[messageId]?.currentContext;
    if (context == null || !context.mounted) return false;

    try {
      await Scrollable.ensureVisible(
        context,
        alignment: 1.0,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ارتفاع آیتم‌های ساخته‌شده را از RenderBox واقعی می‌خواند.
  void _captureHeights(List<ChatMessageModel> messages) {
    for (final message in messages) {
      final context = _anchors[message.id]?.currentContext;
      if (context == null || !context.mounted) continue;

      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.size.height > 0) {
        _measuredHeights[message.id] = renderObject.size.height;
      }
    }
  }

  /// offset دقیقی که ابتدای این پیام را بالای viewport می‌گذارد؛ فقط برای
  /// آیتم‌های ساخته‌شده.
  double? _revealOffsetOf(String messageId) {
    final context = _anchors[messageId]?.currentContext;
    if (context == null || !context.mounted) return null;

    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return null;

    try {
      final viewport = RenderAbstractViewport.of(renderObject);
      final revealed = viewport.getOffsetToReveal(renderObject, 1.0);
      if (revealed.offset.isFinite) return revealed.offset;
    } catch (_) {}
    return null;
  }

  /// تخمین offset برای «ابتدای پیام [targetIndex] در بالای صفحه».
  ///
  /// بهترین لنگر، نزدیک‌ترین پیام ساخته‌شده به مقصد است؛ سپس فاصله با ارتفاع
  /// واقعی (برای آیتم‌های ساخته‌شده) و ارتفاع میانگین (برای بقیه) طی می‌شود.
  /// این کار خطای تخمین را به‌شدت کم می‌کند، چون ارتفاع پیام‌ها در این چت
  /// می‌تواند از چند ده تا چند صد پیکسل متفاوت باشد.
  double _estimateOffset(
    List<ChatMessageModel> messages,
    ScrollController controller,
    int targetIndex,
  ) {
    final position = controller.position;
    if (targetIndex < 0) return position.pixels;

    final fallback = _averageMeasuredHeight();

    int? anchorIndex;
    double? anchorOffset;

    for (int distance = 0; distance <= messages.length; distance++) {
      final candidates = <int>[
        if (targetIndex - distance >= 0) targetIndex - distance,
        if (distance > 0 && targetIndex + distance < messages.length)
          targetIndex + distance,
      ];
      for (final index in candidates) {
        final revealed = _revealOffsetOf(messages[index].id);
        if (revealed != null) {
          anchorIndex = index;
          anchorOffset = revealed;
          break;
        }
      }
      if (anchorIndex != null) break;
    }

    if (anchorIndex == null || anchorOffset == null) {
      // هیچ پیامی ساخته نشده؛ از انتهای لیست (جدیدترین) جمع می‌زنیم.
      double total = 0;
      for (int i = 0; i <= targetIndex; i++) {
        total += _measuredHeights[messages[i].id] ?? fallback;
      }
      // در لیست reverse، offset صفر یعنی پایین‌ترین نقطه؛ ابتدای پیام i وقتی
      // بالای صفحه است که مجموع ارتفاع پیام‌های ۰ تا i منهای ارتفاع viewport.
      return _clampOffset(controller, total - position.viewportDimension);
    }

    double offset = anchorOffset;
    if (targetIndex > anchorIndex) {
      for (int i = anchorIndex + 1; i <= targetIndex; i++) {
        offset += _measuredHeights[messages[i].id] ?? fallback;
      }
    } else if (targetIndex < anchorIndex) {
      for (int i = targetIndex + 1; i <= anchorIndex; i++) {
        offset -= _measuredHeights[messages[i].id] ?? fallback;
      }
    }

    return _clampOffset(controller, offset);
  }

  double _averageMeasuredHeight() {
    if (_measuredHeights.isEmpty) return _fallbackItemHeight;

    double sum = 0;
    for (final height in _measuredHeights.values) {
      sum += height;
    }
    final average = sum / _measuredHeights.length;
    return average.clamp(_minEstimatedHeight, _maxEstimatedHeight).toDouble();
  }

  double _clampOffset(ScrollController controller, double offset) {
    final position = controller.position;
    return offset.clamp(0.0, position.maxScrollExtent).toDouble();
  }

  Future<void> _animateTo(
    ScrollController controller,
    double target,
    Duration duration,
  ) async {
    if (!controller.hasClients) return;
    final clamped = _clampOffset(controller, target);
    if ((clamped - controller.offset).abs() < 0.5) return;

    try {
      await controller.animateTo(
        clamped,
        duration: duration,
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {
      // موقعیت ممکن است در میانهٔ انیمیشن حذف شده باشد؛ نادیده می‌گیریم.
    }
  }

  Future<void> _nextFrame() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}
  }
}
