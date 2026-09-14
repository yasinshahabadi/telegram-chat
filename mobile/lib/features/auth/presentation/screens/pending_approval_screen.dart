import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';

/// صفحه نمایش وضعیت در انتظار تایید مدیر در تلگرام
class PendingApprovalScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final VoidCallback onApproved;

  const PendingApprovalScreen({
    super.key,
    required this.authRepository,
    required this.onApproved,
  });

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final verified = await widget.authRepository.checkVerification();
      if (!mounted) return;

      if (verified) {
        _pollingTimer?.cancel();
        Navigator.of(context).pop(); // بازگشت از صفحه تایید
        widget.onApproved();
      }
    });
  }

  Future<void> _checkNow() async {
    final verified = await widget.authRepository.checkVerification();
    if (!mounted) return;

    if (verified) {
      _pollingTimer?.cancel();
      Navigator.of(context).pop();
      widget.onApproved();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.authRepository.errorMessage ?? 'هنوز توسط مدیر تایید نشده‌اید.',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    size: 48,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'در انتظار تایید مدیر',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'درخواست ورود شما برای مدیر سوپرگروه در تلگرام ارسال شده است. به محض تایید دسترسی، اپلیکیشن به صورت خودکار فعال خواهد شد.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: widget.authRepository.isLoading ? null : _checkNow,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('بررسی مجدد وضعیت'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    widget.authRepository.cancelPendingLogin();
                    Navigator.of(context).pop();
                  },
                  child: const Text('انصراف و بازگشت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
