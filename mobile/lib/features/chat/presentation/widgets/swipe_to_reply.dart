import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wrapper برای کشیدن پیام به سمت راست جهت پاسخ دادن.
/// در RTL و LTR، این الگو با تلگرام و واتساپ هم‌راستا است.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _threshold = 60.0;
  static const double _maxDrag = 90.0;

  double _dragOffset = 0.0;
  bool _hapticFired = false;
  bool _wasDragging = false;

  void _onDragStart(DragStartDetails _) {
    _hapticFired = false;
    _wasDragging = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_dragOffset + details.delta.dx).clamp(0.0, _maxDrag);
    if ((next - _dragOffset).abs() > 0.5) {
      _wasDragging = true;
    }
    setState(() => _dragOffset = next);

    if (_dragOffset >= _threshold && !_hapticFired) {
      _hapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    final shouldReply = _dragOffset >= _threshold;
    if (shouldReply) {
      widget.onReply();
    }
    setState(() {
      _dragOffset = 0;
      _hapticFired = false;
      _wasDragging = false;
    });
  }

  void _onDragCancel() {
    setState(() {
      _dragOffset = 0;
      _hapticFired = false;
      _wasDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dragOffset / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.enabled ? _onDragStart : null,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: widget.enabled ? _onDragCancel : null,
      child: Stack(
        children: [
          // آیکون پاسخ که در سمت چپ ظاهر می‌شود (پیام به راست می‌رود)
          if (_dragOffset > 0.5)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 12 + (_dragOffset * 0.15)),
                  child: Opacity(
                    opacity: progress,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(
                          (80 + progress * 120).toInt(),
                        ),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.reply_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // خود پیام
          AnimatedContainer(
            duration: _wasDragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}