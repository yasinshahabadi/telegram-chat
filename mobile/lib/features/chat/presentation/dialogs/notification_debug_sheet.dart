import 'package:flutter/material.dart';
import 'package:telegram_chat_mobile/features/notifications/data/firebase_messaging_service.dart';
import 'package:telegram_chat_mobile/features/notifications/data/notification_service.dart';

/// Bottom Sheet دیباگ و تست اعلان‌ها.
///
/// در نسخه production نمایش داده می‌شود (تصمیم این جلسه: دست نزن).
class NotificationDebugSheet {
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🛠️ پنل دیباگ و تست اعلان‌ها',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(
                    Icons.notifications_active,
                    color: Colors.green,
                  ),
                  title: const Text('تست ۱: اعلان مستقیم محلی'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await NotificationService.instance.showChatNotification(
                      id: 101,
                      senderName: 'تست ۱: محلی',
                      messageText: 'موتور اعلان داخلی کار می‌کند! ✅',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.vpn_key_rounded,
                    color: Colors.amber,
                  ),
                  title: const Text('تست ۳: دریافت توکن FCM'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final token =
                        await FirebaseMessagingService.instance.getToken();
                    if (context.mounted && token != null) {
                      showDialog(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('توکن FCM دستگاه'),
                          content: SelectableText(token),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: const Text('بستن'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}