import 'package:flutter/material.dart';

/// دیالوگ تلاش دوباره برای ارسال پیام ناموفق + ویرایش متن همراه.
///
/// در صورت تایید، متن جدید (که می‌تواند خالی باشد) را برمی‌گرداند.
/// در صورت انصراف، `null` برمی‌گرداند.
///
/// ⚠️ نکته: `TextEditingController` عمداً dispose نمی‌شود.
/// دلیل: دقیقاً مثل `EditMessageDialog` — انیمیشن خروج دیالوگ پس از pop
/// همچنان در جریان است و dispose زودهنگام باعث crash می‌شود.
class RetryUploadDialog {
  static Future<String?> show(
    BuildContext context, {
    required String initialText,
  }) async {
    final controller = TextEditingController(text: initialText);

    return await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تلاش دوباره برای ارسال'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'پیام قبلی ارسال نشد. می‌توانید متن همراه فایل را ویرایش کنید و دوباره بفرستید.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'متن همراه (اختیاری)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ارسال دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}