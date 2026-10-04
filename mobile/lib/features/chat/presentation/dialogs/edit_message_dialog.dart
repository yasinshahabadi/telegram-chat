import 'package:flutter/material.dart';

/// دیالوگ ویرایش متن یک پیام.
///
/// در صورت تایید و معتبر بودن متن جدید (غیرخالی و متفاوت)، متن ویرایش‌شده را
/// برمی‌گرداند. در صورت انصراف، خالی بودن، یا عدم تغییر، `null` برمی‌گرداند.
///
/// ⚠️ نکته: `TextEditingController` عمداً dispose نمی‌شود.
/// دلیل: پس از `Navigator.pop`، انیمیشن خروج دیالوگ همچنان در جریان است و
/// `TextField` داخل دیالوگ تا پایان انیمیشن زنده است. dispose زودهنگام باعث
/// خطای `_dependents.isEmpty` می‌شود. controller پس از unmount کامل دیالوگ
/// توسط GC جمع‌آوری خواهد شد (بدون leak).
class EditMessageDialog {
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
          title: const Text('ویرایش پیام'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'متن جدید پیام...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () {
                final newText = controller.text.trim();
                if (newText.isNotEmpty && newText != initialText) {
                  Navigator.pop(ctx, newText);
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }
}