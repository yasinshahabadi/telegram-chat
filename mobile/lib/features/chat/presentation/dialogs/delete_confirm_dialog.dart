import 'package:flutter/material.dart';

/// دیالوگ تایید حذف پیام.
///
/// اگر کاربر تایید کند `true` برمی‌گرداند، در غیر این صورت `false`.
class DeleteMessageDialog {
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف پیام'),
          content: const Text(
            'آیا از حذف این پیام اطمینان دارید؟ این عمل روی گروه تلگرام نیز اعمال می‌شود.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    return result == true;
  }
}