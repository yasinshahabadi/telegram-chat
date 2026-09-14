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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ۱. مقداردهی اولیه سرویس‌های داده‌ای و پایگاه داده محلی SQLite
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

  // ۲. بررسی اولیه وضعیت نشست (پشتیبانی از بالا آمدن آفلاین در صورت قطعی اینترنت)
  await authRepository.initialize();

  runApp(TelegramChatApp(
    authRepository: authRepository,
    authStorage: authStorage,
    chatRepository: chatRepository,
    socketClient: socketClient,
  ));
}

/// ویجت ریشه اپلیکیشن با تم تلگرامی و پشتیبانی بومی از زبان فارسی
class TelegramChatApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AuthLocalStorage authStorage;
  final ChatRepository chatRepository;
  final ChatWebSocketClient socketClient;

  const TelegramChatApp({
    super.key,
    required this.authRepository,
    required this.authStorage,
    required this.chatRepository,
    required this.socketClient,
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

      // تم متریال ۳ الهام‌گرفته از رنگ‌آمیزی استاندارد تلگرام
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

      // مسیریابی خودکار بر اساس تغییرات وضعیت احراز هویت
      home: ListenableBuilder(
        listenable: authRepository,
        builder: (context, _) {
          // وضعیت لودینگ اولیه
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
            return ChatScreen(
              authRepository: authRepository,
              chatRepository: chatRepository,
              onLogout: () async {
                socketClient.disconnect();
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
