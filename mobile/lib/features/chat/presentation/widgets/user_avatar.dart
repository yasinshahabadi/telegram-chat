import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/config.dart';

/// آواتار کاربر - با تصویر از سرور، یا حرف اول نام (fallback)
class UserAvatar extends StatelessWidget {
  final String userId;
  final String fullName;
  final double size;
  final bool showOnlineBadge;
  final bool isOnline;

  const UserAvatar({
    super.key,
    required this.userId,
    required this.fullName,
    this.size = 40,
    this.showOnlineBadge = false,
    this.isOnline = false,
  });

  /// تولید رنگ ثابت بر اساس نام کاربر (مثل تلگرام)
  Color _colorFromName(String name) {
    if (name.isEmpty) return const Color(0xFF0088CC);
    final hash = name.codeUnits.fold<int>(0, (prev, c) => prev + c);
    const colors = [
      Color(0xFFE17076),
      Color(0xFF7BC862),
      Color(0xFFE5CA77),
      Color(0xFF65AADD),
      Color(0xFFA695E7),
      Color(0xFFEE7AAE),
      Color(0xFF6EC9CB),
      Color(0xFFFAA774),
    ];
    return colors[hash % colors.length];
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = '${AppConfig.baseUrl}/api/users/avatar?userId=$userId';
    final theme = Theme.of(context);

    Widget avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          fit: BoxFit.cover,
          memCacheWidth: (size * 3).toInt(),
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => _buildInitialsAvatar(theme),
          errorWidget: (_, __, ___) => _buildInitialsAvatar(theme),
        ),
      ),
    );

    if (showOnlineBadge) {
      avatar = Stack(
        children: [
          avatar,
          if (isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return avatar;
  }

  Widget _buildInitialsAvatar(ThemeData theme) {
    final bg = _colorFromName(fullName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(fullName),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}