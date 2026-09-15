import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/database/app_database.dart';
import 'core/database/local_chat_dao.dart';
import 'core/network/network_monitor.dart';
import 'features/auth/data/auth_local_storage.dart';
import 'features/auth/data/auth_remote_service.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/domain/models/auth_user.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/pending_approval_screen.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/data/chat_websocket_client.dart';
import 'features/chat/data/sync_engine.dart';
import 'features/chat/presentation/screens/chat_screen.dart';
import 'features/notifications/data/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ۱. مقداردهی اولیه پایگاه داده محلی SQLite و حافظه محلی
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

  // ۲. راه‌اندازی موتور همگام‌سازی دلتا و پایشگر شبکه
  final syncEngine = SyncEngine(localDao: localDao);
  final networkMonitor = NetworkMonitor.instance;
  await networkMonitor.initialize();

  // اتصال رویداد بازیابی شبکه: به محض وصل شدن اینترنت، سوکت متصل شده و دلتا سینک اجرا می‌شود
  networkMonitor.onNetworkRestored = () async {
    final token = authStorage.getSessionToken();
    if (token != null && token.isNotEmpty) {
      if (!socketClient.isConnected) {
        socketClient.connect(token);
      }
      await syncEngine.syncMissedEvents(token, onSyncCompleted: () {
        chatRepository.loadLocalMessages();
        chatRepository.processPendingQueue();
      });
    }
  };

  // ۳. راه‌اندازی سرویس اعلان‌های نیتیو اندروید
  final notifService = NotificationService.instance;
  await notifService.initialize();
  await notifService.requestPermission();

  // اتصال پاسخ مستقیم از نوار نوتیفیکیشن
  notifService.onDirectReplyReceived = (replyText, payload) async {
    final currentUser = authRepository.currentUser;
    if (currentUser != null && replyText.trim().isNotEmpty) {
      await chatRepository.sendMessage(
        text: replyText.trim(),
        currentUser: currentUser,
      );
    }
  };

  // ۴. بررسی اولیه نشست کاربر (لود آفلاین در صورت نبود اینترنت)
  await authRepository.initialize();

  runApp(TelegramChatApp(
    authRepository: authRepository,
    authStorage: authStorage,
    chatRepository: chatRepository,
    socketClient: socketClient,
    notifService: notifService,
    syncEngine: syncEngine,
  ));
}

/// ویجت ریشه اپلیکیشن با تم تلگرامی و پشتیبانی بومی از زبان فارسی
class TelegramChatApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AuthLocalStorage authStorage;
  final ChatRepository chatRepository;
  final ChatWebSocketClient socketClient;
  final NotificationService notifService;
  final SyncEngine syncEngine;

  const TelegramChatApp({
    super.key,
    required this.authRepository,
    required this.authStorage,
    required this.chatRepository,
    required this.socketClient,
    required this.notifService,
    required this.syncEngine,
  });

  void _ensureConnectedAndSynced() {
    final token = authStorage.getSessionToken();
    if (token != null && token.isNotEmpty) {
      if (!socketClient.isConnected) {
        socketClient.connect(token);
      }
      // اجرای همگام‌سازی پس‌زمینه برای رویدادهای از دست رفته
      syncEngine.syncMissedEvents(token, onSyncCompleted: () {
        chatRepository.loadLocalMessages();
        chatRepository.processPendingQueue();
      });
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

      // تم متریال ۳ تلگرامی
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

      // مسیریابی هوشمند بر اساس وضعیت احراز هویت
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
                _ensureConnectedAndSynced();
              },
            );
          }

          // اگر در انتظار تایید مدیر باشد
          if (authRepository.status == AuthStatus.pendingApproval) {
            return PendingApprovalScreen(
              authRepository: authRepository,
              onApproved: () {
                _ensureConnectedAndSynced();
              },
            );
          }

          // اگر کاربر تایید و وارد شده باشد (آنلاین یا آفلاین)
          if (authRepository.isAuthenticated) {
            _ensureConnectedAndSynced();
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
              _ensureConnectedAndSynced();
            },
          );
        },
      ),
    );
  }
}
