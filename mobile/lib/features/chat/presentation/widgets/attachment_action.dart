import 'package:flutter/material.dart';

/// یک اکشن در نوار پیوست.
///
/// افزودن گزینهٔ جدید (مثلاً موقعیت یا مخاطب) فقط با اضافه‌کردن یک
/// [AttachmentAction] به لیست انجام می‌شود؛ نوار به‌صورت خودکار اسکرول
/// افقی می‌گیرد و آیتم‌ها را کنار هم می‌چیند.
class AttachmentAction {
  final String id;
  final String label;
  final IconData icon;
  final Color? accentColor;
  final Future<void> Function() onSelected;

  const AttachmentAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.accentColor,
  });
}
