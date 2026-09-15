import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/database/app_database.dart';
import 'core/database/local_chat_dao.dart';
import 'features/auth/data/auth_local_storage.dart';
import 'features/auth/data/auth_remote_service.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/models/auth_user.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/pending_approval_screen.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/data/chat_websocket_client.dart';
import 'features/chat/presentation/screens/chat_screen.dart';
import 'features/notifications/data/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ۱. مقداردهی اولیه پایگاه داده محلی SQLite و تنظیمات
  final prefs = await SharedPreferences.getInstance();
  final localDao = LocalChatDao(appDatabase: AppDatabase.instance);

  final authStorage = AuthLocalStorage(prefs: prefs);
  final authService = AuthRemoteService();
  final authRepository = AuthRepository(
    localStorage: authStorage,
    remoteService: authService,
  );

  final socketClient = ChatWebSocketClient();
  final chatRepository = ChatRepository(
    localDao: localDao,
    socketClient: socketClient,
  );

  // ۲. راه‌اندازی سرویس اعلان‌های نیتیو اندروید و ثبت کانال‌ها
  final notifService = NotificationService.instance;
  await notifService.initialize();
  await notifService.requestPermission();

  // ۳. اتصال قابلیت پاسخ مستقیم از نوار اعلان (Android RemoteInput)
  notifService.onDirectReplyReceived = (replyText, payload) async {
    final currentUser = authRepository.currentUser;
    if (currentUser != null && replyText.trim().isNotEmpty) {
      await chatRepository.sendMessage(
        text: replyText.trim(),
        currentUser: currentUser,
      );
    }
  };

  // ۴. بررسی اولیه وضعیت نشست (پشتیبانی آفلاین در صورت قطعی اینترنت)
  await authRepository.initialize();

  runApp(TelegramChatApp(
    authRepository: authRepository,
    authStorage: authStorage,
    chatRepository: chatRepository,
    socketClient: socketClient,
    notifService: notifService,
  ));
}

/// ویجت ریشه اپلیکیشن با تم تلگرامی و پشتیبانی بومی از زبان فارسی
class TelegramChatApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AuthLocalStorage authStorage;
  final ChatRepository chatRepository;
  final ChatWebSocketClient socketClient;
  final NotificationService notifService;

  const TelegramChatApp({
    super.key,
    required this.authRepository,
    required this.authStorage,
    required this.chatRepository,
    required this.socketClient,
    required this.notifService,
  });

  void _ensureSocketConnected() {
    final token = authStorage.getSessionToken();
    if (token != null && token.isNotEmpty && !socketClient.isConnected) {
      socketClient.connect(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پیام‌رسان تلگرام',
      debugShowCheckedModeBanner: false,

      // پیکربندی بومی زبان فارسی و راست‌چین
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // تم متریال ۳ الهام‌گرفته از استایل استاندارد تلگرام
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0088CC),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0088CC),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
        ),
      ),
      themeMode: ThemeMode.system,

      // مسیریابی هوشمند و واکنشی بر اساس وضعیت نشست
      home: ListenableBuilder(
        listenable: authRepository,
        builder: (context, _) {
          // وضعیت بارگذاری اولیه
          if (authRepository.isLoading && authRepository.status == AuthStatus.initial) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // اگر کاربر وارد نشده باشد
          if (authRepository.status == AuthStatus.unauthenticated) {
            return LoginScreen(
              authRepository: authRepository,
              onAuthenticated: () {
                _ensureSocketConnected();
              },
            );
          }

          // اگر کاربر در انتظار تایید مدیر در تلگرام باشد
          if (authRepository.status == AuthStatus.pendingApproval) {
            return PendingApprovalScreen(
              authRepository: authRepository,
              onApproved: () {
                _ensureSocketConnected();
              },
            );
          }

          // اگر کاربر احراز هویت شده باشد (آنلاین یا آفلاین)
          if (authRepository.isAuthenticated) {
            _ensureSocketConnected();
            notifService.cancelAllNotifications();

            return ChatScreen(
              authRepository: authRepository,
              chatRepository: chatRepository,
              onLogout: () async {
                socketClient.disconnect();
                await notifService.cancelAllNotifications();
                await authRepository.logout();
              },
            );
          }

          return LoginScreen(
            authRepository: authRepository,
            onAuthenticated: () {
              _ensureSocketConnected();
            },
          );
        },
      ),
    );
  }
}
