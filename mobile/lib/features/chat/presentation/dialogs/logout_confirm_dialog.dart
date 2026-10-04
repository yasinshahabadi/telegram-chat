import 'package:flutter/material.dart';

/// دیالوگ تایید خروج از حساب.
///
/// اگر کاربر تایید کند `true` برمی‌گرداند، در غیر این صورت `false`.
class LogoutConfirmDialog {
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خروج از حساب'),
          content: const Text('آیا از خروج اطمینان دارید؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('خیر'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج'),
            ),
          ],
        ),
      ),
    );

    return result == true;
  }
}