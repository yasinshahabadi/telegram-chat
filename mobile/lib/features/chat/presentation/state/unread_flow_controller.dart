import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:telegram_chat_mobile/features/chat/domain/models/chat_message_model.dart';

/// فاز نمایش Divider نخوانده‌ها.
enum DividerPhase { idle, visible, fading, done }

/// کنترلر کامل «چرخهٔ خواندن/نخواندن» چت.
///
/// چرا یک فایل و نه دو؟ چون این دو مسئولیت state مشترک دارند:
///   - `_lastReadAt` (snapshot می‌خواند، mark می‌نویسد)
///   - `_inInitialLoad` (divider می‌سازد، mark از آن استفاده می‌کند)
///   - `_isMarkingRead` (mark تولید می‌کند، divider از آن مطلع می‌شود)
/// جدا کردن آن‌ها به دو فایل، یا state مشترک می‌ساخت یا callback دوطرفه.
///
/// این کنترلر:
///   - مالک `ScrollController` است (چون در reveal ها recreate می‌شود).
///   - مالک تمام state مربوط به divider و mark-read است.
///   - تمام تصمیمات را خودش می‌گیرد.
///   - فقط از طریق callback با host ارتباط دارد.
class UnreadFlowController {
  // ── Prefs key ──
  static const String _prefsKeyLastReadAt = 'chat_last_read_at';

  // ── Timing ──
  static const Duration _settleDelay = Duration(milliseconds: 400);
  static const Duration _settleExtension = Duration(milliseconds: 1200);
  static const Duration _hardCap = Duration(seconds: 4);
  static const Duration _dividerRevealDelay = Duration(milliseconds: 150);
  static const Duration _dividerFadeDelay = Duration(seconds: 5);
  static const Duration _dividerFadeAnim = Duration(milliseconds: 900);
  static const Duration _markReadDebounceDelay = Duration(milliseconds: 800);

  // ── Thresholds ──
  static const double _nearBottomThreshold = 120.0;
  static const double _messageEstimate = 90.0;

  // ── Callbacks to host ──
  final List<ChatMessageModel> Function() getMessages;
  final String? Function() getCurrentUserId;
  final void Function() onStateChanged;
  final void Function() onScrollToBottomRequest;

  // ── Lifecycle ──
  bool _isAlive = true;

  // ── Scroll ──
  ScrollController? _scrollController;

  // ── Unread state ──
  int? _lastReadAt;
  String? _snapshotFirstUnreadId;
  int _snapshotUnreadCount = 0;
  final GlobalKey firstUnreadKey = GlobalKey();
  DividerPhase _dividerPhase = DividerPhase.idle;
  Timer? _dividerFadeTimer;
  bool _autoScrollInProgress = false;

  // ── Initial-load window ──
  bool _inInitialLoad = true;
  DateTime? _initialLoadStart;
  Timer? _initialLoadSettleTimer;

  // ── Mark-read state ──
  Timer? _markReadDebounce;
  final Set<String> _pendingMarkReadIds = {};
  bool _isMarkingRead = false;

  // ── App visibility ──
  bool _isAppVisible = true;

  // ── New-message tracking ──
  String? _lastKnownNewestId;
  bool _hasHighlightedMessage = false;

  /// callback که host باید پس از ساخت set کند.
  /// این متد به `ChatRepository.markMessagesAsRead` وصل می‌شود.
  Future<void> Function(List<String> ids)? onMarkReadRequest;

  UnreadFlowController({
    required this.getMessages,
    required this.getCurrentUserId,
    required this.onStateChanged,
    required this.onScrollToBottomRequest,
  });

  // ═════════════════════════════════════════════
  //  Public getters
  // ═════════════════════════════════════════════

  ScrollController? get scrollController => _scrollController;
  DividerPhase get dividerPhase => _dividerPhase;
  String? get snapshotFirstUnreadId => _snapshotFirstUnreadId;
  int get snapshotUnreadCount => _snapshotUnreadCount;
  bool get chatReady => _scrollController != null;

  bool get _isNearBottom {
    final c = _scrollController;
    if (c == null || !c.hasClients) return true;
    return c.offset < _nearBottomThreshold;
  }

  // ═════════════════════════════════════════════
  //  Lifecycle
  // ═════════════════════════════════════════════

  Future<void> initialize() async {
    await _loadLastReadAt();
    final messages = getMessages();
    if (messages.isNotEmpty) {
      _lastKnownNewestId = messages.first.id;
    }
    _beginInitialLoad();
  }

  void dispose() {
    _isAlive = false;
    _initialLoadSettleTimer?.cancel();
    _initialLoadSettleTimer = null;
    _markReadDebounce?.cancel();
    _markReadDebounce = null;
    _dividerFadeTimer?.cancel();
    _dividerFadeTimer = null;
    _scrollController?.removeListener(_onScrollChanged);
    _scrollController?.dispose();
    _scrollController = null;
  }

  /// اطلاع از حضور یا عدم حضور پیام highlight شده.
  /// برای جلوگیری از auto-scroll هنگام highlight.
  void setHighlightPresent(bool present) {
    _hasHighlightedMessage = present;
  }

  /// ChatScreen از listener روی ChatRepository صدا می‌زند.
  void onChatUpdate() {
    if (!_isAppVisible) return;

    final userId = getCurrentUserId();
    if (userId == null) return;

    final messages = getMessages();
    final newestId = messages.isNotEmpty ? messages.first.id : null;
    final previousNewestId = _lastKnownNewestId;
    _lastKnownNewestId = newestId;

    final hasNewMessage = previousNewestId != null &&
        newestId != null &&
        newestId != previousNewestId;

    final newestIsFromOther = hasNewMessage &&
        messages.isNotEmpty &&
        messages.first.senderId != userId;

    if (_inInitialLoad) {
      if (newestIsFromOther) {
        _extendSettleTimer();
      }
      return;
    }

    if (hasNewMessage &&
        _isNearBottom &&
        !_autoScrollInProgress &&
        !_hasHighlightedMessage) {
      onScrollToBottomRequest();
    }

    _maybeScheduleReadForVisibleMessages();
  }

  /// ChatScreen از didChangeAppLifecycleState صدا می‌زند.
  void onAppVisibilityChanged(bool isVisible) {
    if (_isAppVisible == isVisible) return;
    _isAppVisible = isVisible;

    if (isVisible) {
      _markReadDebounce?.cancel();
      _resetDividerState();
      _beginInitialLoad();
    } else {
      _markReadDebounce?.cancel();
    }
  }

  // ═════════════════════════════════════════════
  //  Scroll actions (public)
  // ═════════════════════════════════════════════

  void scrollToBottom() {
    final c = _scrollController;
    if (c != null && c.hasClients) {
      c.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// برای سناریوی tap روی reply — Scrollable.ensureVisible با key پیام.
  Future<void> ensureVisibleOnKey(
    GlobalKey key, {
    double alignment = 0.5,
    Duration duration = const Duration(milliseconds: 350),
  }) async {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return;

    _autoScrollInProgress = true;
    try {
      await Scrollable.ensureVisible(
        ctx,
        duration: duration,
        curve: Curves.easeInOut,
        alignment: alignment,
      );
    } catch (_) {
    } finally {
      _autoScrollInProgress = false;
    }
  }

  /// برای سناریوی tap روی reply — fallback با محاسبهٔ تخمینی offset.
  Future<void> animateToApproximateIndex(int index) async {
    final c = _scrollController;
    if (c == null || !c.hasClients) return;

    final approx = (index * _messageEstimate).clamp(
      0.0,
      c.position.maxScrollExtent,
    );
    await c.animateTo(
      approx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ═════════════════════════════════════════════
  //  Unread flow — initial load
  // ═════════════════════════════════════════════

  void _beginInitialLoad() {
    _inInitialLoad = true;
    _initialLoadStart = DateTime.now();
    _resetSettleTimer(_settleDelay);
  }

  void _resetSettleTimer(Duration delay) {
    _initialLoadSettleTimer?.cancel();
    _initialLoadSettleTimer = Timer(delay, _onInitialLoadSettled);
  }

  void _extendSettleTimer() {
    final start = _initialLoadStart;
    if (start == null) return;
    if (DateTime.now().difference(start) >= _hardCap) return;
    _resetSettleTimer(_settleExtension);
  }

  void _onInitialLoadSettled() {
    if (!_isAlive) return;

    _initialLoadSettleTimer?.cancel();
    _initialLoadSettleTimer = null;
    _inInitialLoad = false;
    _initialLoadStart = null;

    _takeUnreadSnapshot();

    if (_snapshotFirstUnreadId != null) {
      Future.delayed(_dividerRevealDelay, () {
        if (!_isAlive) return;
        if (_scrollController == null) {
          _revealDividerOnFirstOpen();
        } else {
          _revealDividerOnResume();
        }
      });
    } else {
      if (_scrollController == null) {
        _revealChatWithoutDivider();
      } else {
        _maybeScheduleReadForVisibleMessages();
      }
    }
  }

  // ═════════════════════════════════════════════
  //  Unread flow — snapshot
  // ═════════════════════════════════════════════

  void _takeUnreadSnapshot() {
    _snapshotFirstUnreadId = null;
    _snapshotUnreadCount = 0;

    final userId = getCurrentUserId();
    if (userId == null) return;

    final messages = getMessages();
    if (messages.isEmpty) return;

    final lastReadAt = _lastReadAt;

    for (int i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.senderId == userId) continue;
      if (lastReadAt == null || m.createdAt > lastReadAt) {
        _snapshotFirstUnreadId = m.id;
        break;
      }
    }

    if (_snapshotFirstUnreadId != null) {
      for (final m in messages) {
        if (m.senderId == userId) continue;
        if (lastReadAt == null || m.createdAt > lastReadAt) {
          _snapshotUnreadCount++;
        }
      }
    }
  }

  // ═════════════════════════════════════════════
  //  Unread flow — reveal
  // ═════════════════════════════════════════════

  void _revealChatWithoutDivider() {
    _scrollController?.removeListener(_onScrollChanged);
    _scrollController?.dispose();
    final c = ScrollController();
    c.addListener(_onScrollChanged);
    _scrollController = c;

    _dividerPhase = DividerPhase.idle;
    onStateChanged();

    _maybeScheduleReadForVisibleMessages();
  }

  void _revealDividerOnFirstOpen() {
    final messages = getMessages();
    double initialOffset = 0.0;

    if (_snapshotFirstUnreadId != null) {
      final idx = messages.indexWhere((m) => m.id == _snapshotFirstUnreadId);
      if (idx > 0) {
        initialOffset = idx * _messageEstimate;
      }
    }

    _scrollController?.removeListener(_onScrollChanged);
    _scrollController?.dispose();
    final c = ScrollController(initialScrollOffset: initialOffset);
    c.addListener(_onScrollChanged);
    _scrollController = c;

    _dividerPhase = DividerPhase.visible;
    onStateChanged();

    _startDividerFadeTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isAlive) return;
      _refineScrollToSnapshot();
      _markAllUnreadAsReadAndUpdateTimestamp();
    });
  }

  void _revealDividerOnResume() {
    _dividerPhase = DividerPhase.visible;
    onStateChanged();

    _startDividerFadeTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isAlive) return;
      await _refineScrollToSnapshot();
      if (_isAlive) _markAllUnreadAsReadAndUpdateTimestamp();
    });
  }

  Future<void> _refineScrollToSnapshot() async {
    if (_snapshotFirstUnreadId == null) return;
    final ctx = firstUnreadKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    _autoScrollInProgress = true;
    try {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: 0.75,
      );
    } catch (_) {
    } finally {
      _autoScrollInProgress = false;
    }
  }

  void _startDividerFadeTimer() {
    _dividerFadeTimer?.cancel();
    _dividerFadeTimer = Timer(_dividerFadeDelay, () {
      if (!_isAlive) return;

      _dividerPhase = DividerPhase.fading;
      onStateChanged();

      Timer(_dividerFadeAnim, () {
        if (!_isAlive) return;
        _dividerPhase = DividerPhase.done;
        _snapshotFirstUnreadId = null;
        _snapshotUnreadCount = 0;
        onStateChanged();
      });
    });
  }

  void _resetDividerState() {
    _dividerPhase = DividerPhase.idle;
    _snapshotFirstUnreadId = null;
    _snapshotUnreadCount = 0;
    _dividerFadeTimer?.cancel();
    _dividerFadeTimer = null;
    _inInitialLoad = true;
  }

  // ═════════════════════════════════════════════
  //  Mark-read
  // ═════════════════════════════════════════════

  void _onScrollChanged() {
    if (!_isAppVisible) return;
    if (_autoScrollInProgress) return;
    if (_inInitialLoad) return;
    if (!_isNearBottom) return;
    _maybeScheduleReadForVisibleMessages();
  }

  void _maybeScheduleReadForVisibleMessages() {
    if (!_isAppVisible) return;
    if (_autoScrollInProgress) return;
    if (_inInitialLoad) return;
    if (!_isNearBottom) return;

    final userId = getCurrentUserId();
    if (userId == null) return;

    final messages = getMessages();
    final unreadIds = messages
        .where((m) => m.senderId != userId && m.readAt == null)
        .map((m) => m.id)
        .toSet();

    if (unreadIds.isEmpty) return;

    _pendingMarkReadIds.addAll(unreadIds);

    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(_markReadDebounceDelay, () {
      _flushMarkRead();
    });
  }

  Future<void> _flushMarkRead() async {
    if (!_isAlive) return;
    if (!_isAppVisible) return;
    if (_isMarkingRead) return;
    if (_inInitialLoad) return;
    if (_pendingMarkReadIds.isEmpty) return;

    final idsToMark = _pendingMarkReadIds.toList();
    _pendingMarkReadIds.clear();

    _isMarkingRead = true;
    try {
      await onMarkReadRequest?.call(idsToMark);

      final messages = getMessages();
      int newestMarked = 0;
      for (final m in messages) {
        if (idsToMark.contains(m.id) && m.createdAt > newestMarked) {
          newestMarked = m.createdAt;
        }
      }
      if (newestMarked > 0) {
        await _saveLastReadAt(newestMarked);
      }
    } finally {
      _isMarkingRead = false;
    }
  }

  Future<void> _markAllUnreadAsReadAndUpdateTimestamp() async {
    if (!_isAppVisible) return;

    final userId = getCurrentUserId();
    if (userId == null) return;

    final messages = getMessages();
    final unreadIds = messages
        .where((m) => m.senderId != userId && m.readAt == null)
        .map((m) => m.id)
        .toList();

    if (unreadIds.isEmpty) return;

    _isMarkingRead = true;
    try {
      await onMarkReadRequest?.call(unreadIds);
      if (messages.isNotEmpty) {
        await _saveLastReadAt(messages.first.createdAt);
      }
    } finally {
      _isMarkingRead = false;
    }
  }

  // ═════════════════════════════════════════════
  //  Persistence
  // ═════════════════════════════════════════════

  Future<void> _loadLastReadAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastReadAt = prefs.getInt(_prefsKeyLastReadAt);
    } catch (_) {}
  }

  Future<void> _saveLastReadAt(int timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyLastReadAt, timestamp);
      _lastReadAt = timestamp;
    } catch (_) {}
  }
}