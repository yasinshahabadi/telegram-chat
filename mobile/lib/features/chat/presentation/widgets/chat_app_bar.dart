import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/chat/data/chat_repository.dart';
import 'package:telegram_chat_mobile/features/chat/presentation/widgets/chat_status_subtitle.dart';

/// سازندهٔ AppBar صفحهٔ چت با عنوان، زیرعنوان وضعیت و سه اکشن.
///
/// از الگوی static factory استفاده می‌کند (نه Widget) چون `Scaffold.appBar`
/// نیازمند `PreferredSizeWidget` است و `AppBar` خودش این را پیاده می‌کند.
/// این سبک همچنین با الگوی موجود در `dialogs/` هماهنگ است.
class ChatAppBar {
  static AppBar build({
    required ChatRepository chatRepository,
    required VoidCallback onOpenStorage,
    required VoidCallback onOpenDebug,
    required VoidCallback onLogout,
  }) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سوپرگروه تلگرام',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          ChatStatusSubtitle(chatRepository: chatRepository),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.storage_rounded),
          tooltip: 'مدیریت حافظه',
          onPressed: onOpenStorage,
        ),
        IconButton(
          icon: const Icon(Icons.build_circle_rounded, color: Colors.amber),
          tooltip: 'پنل تست اعلان‌ها',
          onPressed: onOpenDebug,
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'خروج از حساب',
          onPressed: onLogout,
        ),
      ],
    );
  }
}