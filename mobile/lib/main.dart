import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pushy_flutter/pushy_flutter.dart';
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
import 'features/notifications/data/pushy_service.dart';

@pragma('vm:entry-point')
void backgroundPushyNotificationListener(Map<String, dynamic> data) async {
  debugPrint('[PUSHY] -> Background payload: $data');

  try {
    WidgetsFlutterBinding.ensureInitialized();
    final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    await localNotif.initialize(const InitializationSettings(android: androidSettings));

    const androidDetails = AndroidNotificationDetails(
      'telegram_chat_messages',
      'پیام‌های چت',
      channelDescription: 'اعلان پیام‌های دریافتی از سوپرگروه تلگرام',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final String title = data['title']?.toString() ?? data['senderName']?.toString() ?? 'Guysgram';
    final String message = data['message']?.toString() ?? data['text']?.toString() ?? 'پیام جدید دریافت شد';

    await localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      message,
      const NotificationDetails(android: androidDetails),
      payload: data['messageId']?.toString(),
    );
  } catch (_) {}

  try {
    Pushy.clearBadge();
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final notifService = NotificationService.instance;
  await notifService.initialize();
  await notifService.requestPermission();

  try {
    Pushy.listen();
    Pushy.setNotificationListener(backgroundPushyNotificationListener);
  } catch (_) {}

  notifService.onDirectReplyReceived = (replyText, payload) async {
    final currentUser = authRepository.currentUser;
    if (currentUser != null && replyText.trim().isNotEmpty) {
      await chatRepository.sendMessage(
        text: replyText.trim(),
        currentUser: currentUser,
      );
    }
  };

  final syncEngine = SyncEngine(localDao: localDao);
  final networkMonitor = NetworkMonitor.instance;
  await networkMonitor.initialize();

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

/// اپلیکیشن مجهز به ناظر پایش چرخه حیات (WidgetsBindingObserver)
class TelegramChatApp extends StatefulWidget {
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

  @override
  State<TelegramChatApp> createState() => _TelegramChatAppState();
}

class _TelegramChatAppState extends State<TelegramChatApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // اگر کاربر دکمه هوم را زد یا صفحه قفل شد، وضعیت پس‌زمینه را فعال کن
    final isBackground = state != AppLifecycleState.resumed;
    widget.chatRepository.isAppInBackground = isBackground;
    debugPrint('[LIFECYCLE] App background state: $isBackground ($state)');
  }

  void _ensureConnectedAndSynced() {
    final token = widget.authStorage.getSessionToken();
    if (token != null && token.isNotEmpty) {
      if (!widget.socketClient.isConnected) {
        widget.socketClient.connect(token);
      }
      widget.syncEngine.syncMissedEvents(token, onSyncCompleted: () {
        widget.chatRepository.loadLocalMessages();
        widget.chatRepository.processPendingQueue();
      });

      widget.authStorage.getOrCreateDeviceIdentifier().then((deviceId) {
        PushyService.instance.registerDeviceToken(
          sessionToken: token,
          deviceId: deviceId,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guysgram',
      debugShowCheckedModeBanner: false,

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

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0088CC),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0088CC),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,

      home: ListenableBuilder(
        listenable: widget.authRepository,
        builder: (context, _) {
          if (widget.authRepository.isLoading && widget.authRepository.status == AuthStatus.initial) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (widget.authRepository.status == AuthStatus.unauthenticated) {
            return LoginScreen(
              authRepository: widget.authRepository,
              onAuthenticated: _ensureConnectedAndSynced,
            );
          }

          if (widget.authRepository.status == AuthStatus.pendingApproval) {
            return PendingApprovalScreen(
              authRepository: widget.authRepository,
              onApproved: _ensureConnectedAndSynced,
            );
          }

          if (widget.authRepository.isAuthenticated) {
            _ensureConnectedAndSynced();

            return ChatScreen(
              authRepository: widget.authRepository,
              chatRepository: widget.chatRepository,
              onLogout: () async {
                widget.socketClient.disconnect();
                await widget.notifService.cancelAllNotifications();
                await widget.authRepository.logout();
              },
            );
          }

          return LoginScreen(
            authRepository: widget.authRepository,
            onAuthenticated: _ensureConnectedAndSynced,
          );
        },
      ),
    );
  }
}
