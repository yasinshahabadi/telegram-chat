import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/auth_repository.dart';
import '../../domain/models/auth_user.dart';
import 'pending_approval_screen.dart';

/// صفحه ورود به برنامه از طریق ربات تلگرام
class LoginScreen extends StatefulWidget {
  final AuthRepository authRepository;
  final VoidCallback onAuthenticated;

  const LoginScreen({
    super.key,
    required this.authRepository,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Timer? _pollingTimer;
  bool _isWaitingForTelegram = false;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// باز کردن ربات تلگرام با دیپ‌لینک اختصاصی و آغاز پایش وضعیت
  Future<void> _handleTelegramLogin() async {
    final deepLinkUrl = widget.authRepository.startTelegramLogin();
    final uri = Uri.parse(deepLinkUrl);

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        setState(() {
          _isWaitingForTelegram = true;
        });
        _startVerificationPolling();
      } else {
        _showErrorSnackBar('امکان باز کردن تلگرام وجود ندارد. لطفاً از نصب بودن تلگرام مطمئن شوید.');
      }
    } catch (e) {
      _showErrorSnackBar('خطا در باز کردن لینک ورود: $e');
    }
  }

  /// پایش دوره‌ای وضعیت تایید کاربر هر ۳ ثانیه یک‌بار
  void _startVerificationPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final verified = await widget.authRepository.checkVerification();
      if (!mounted) return;

      if (verified) {
        timer.cancel();
        widget.onAuthenticated();
      } else if (widget.authRepository.status == AuthStatus.pendingApproval) {
        timer.cancel();
        _navigateToPendingApproval();
      }
    });
  }

  /// بررسی دستی وضعیت تایید با دکمه
  Future<void> _checkManually() async {
    final verified = await widget.authRepository.checkVerification();
    if (!mounted) return;

    if (verified) {
      _pollingTimer?.cancel();
      widget.onAuthenticated();
    } else if (widget.authRepository.status == AuthStatus.pendingApproval) {
      _pollingTimer?.cancel();
      _navigateToPendingApproval();
    } else if (widget.authRepository.errorMessage != null) {
      _showErrorSnackBar(widget.authRepository.errorMessage!);
    }
  }

  void _navigateToPendingApproval() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PendingApprovalScreen(
          authRepository: widget.authRepository,
          onApproved: widget.onAuthenticated,
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // آیکون بالای صفحه
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      size: 50,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // عنوان و توضیحات
                  Text(
                    'ورود به گفتگوی تلگرام',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'برای ورود امن و احراز هویت حساب، دکمه زیر را لمس کرده و در ربات تلگرام دکمه Start را بزنید.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // دکمه ورود با تلگرام
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: widget.authRepository.isLoading ? null : _handleTelegramLogin,
                      icon: const Icon(Icons.telegram, size: 28),
                      label: const Text(
                        'ورود از طریق تلگرام',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  // وضعیت انتظار و دکمه بررسی مجدد در صورت باز شدن تلگرام
                  if (_isWaitingForTelegram) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'در حال بررسی تایید ورود...',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: widget.authRepository.isLoading ? null : _checkManually,
                      icon: const Icon(Icons.refresh),
                      label: const Text('بررسی دستی تایید'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
