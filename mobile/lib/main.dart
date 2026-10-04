import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/database/app_database.dart';
import 'core/database/local_chat_dao.dart';
import 'core/network/network_monitor.dart';
import 'core/update/update_dialog.dart';
import 'core/update/update_service.dart';
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
import 'features/media/data/media_download_manager.dart';
import 'features/notifications/data/firebase_messaging_service.dart';
import 'features/notifications/data/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  MediaDownloadManager.instance.onDownloadCompleted =
      (attachmentId, messageId, localPath) {
    chatRepository.setLocalPathForAttachment(messageId, attachmentId, localPath);
  };

  final notifService = NotificationService.instance;
  await notifService.initialize();
  await notifService.requestPermission();

  await FirebaseMessagingService.instance.initialize();

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
    if (token == null || token.isEmpty) return;

    if (!socketClient.isConnected) {
      socketClient.connect(token);
    }

    final currentUser = authRepository.currentUser;
    final result = await syncEngine.syncMissedEvents(
      token,
      currentUserId: currentUser?.id,
      onSyncCompleted: () {
        chatRepository.loadLocalMessages();
        chatRepository.processPendingQueue();
      },
    );

    // ✅ اگر session نامعتبر شده، کاربر را logout کن.
    if (result.unauthorized) {
      await _handleUnauthorized(authRepository, socketClient);
      return;
    }

    if (result.newMessagesCount > 0 && chatRepository.isAppInBackground) {
      await NotificationService.instance.showMissedMessagesNotification(
        count: result.newMessagesCount,
        sender: result.lastMessageSender,
        text: result.lastMessageText,
      );
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

  _checkForUpdate();
}

/// ✅ خروج کاربر هنگام نامعتبر شدن session روی سرور.
Future<void> _handleUnauthorized(
  AuthRepository authRepository,
  ChatWebSocketClient socketClient,
) async {
  debugPrint('[Main] Session invalid — logging out');
  try {
    socketClient.disconnect();
  } catch (_) {}
  await authRepository.logout();
}

Future<void> _checkForUpdate() async {
  try {
    await Future.delayed(const Duration(seconds: 3));

    final updateInfo = await UpdateService.instance.checkForUpdate();
    if (updateInfo == null || !updateInfo.isUpdateAvailable) return;

    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updateInfo: updateInfo),
    );
  } catch (e) {
    debugPrint('[Update] Check error: $e');
  }
}

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

class _TelegramChatAppState extends State<TelegramChatApp>
    with WidgetsBindingObserver {
  StreamSubscription<RemoteMessage>? _notificationClickSubscription;
  bool _hasInitialized = false;

  Timer? _foregroundSyncDebounce;
  Timer? _catchUpTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notificationClickSubscription =
        notificationClickStream.listen(_onNotificationClicked);

    widget.chatRepository.onSocketReconnected = _debouncedSync;
    FirebaseMessagingService.instance.onForegroundMessage = _debouncedSync;
  }

  @override
  void dispose() {
    _notificationClickSubscription?.cancel();
    _foregroundSyncDebounce?.cancel();
    _catchUpTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _debouncedSync() {
    _foregroundSyncDebounce?.cancel();
    _foregroundSyncDebounce = Timer(const Duration(seconds: 2), () {
      _performSync();
    });
  }

  /// ✅ هستهٔ sync که در چند جا استفاده می‌شود.
  ///
  /// حالا اگر سرور 401 بدهد، کاربر را logout می‌کند.
  Future<void> _performSync() async {
    final token = widget.authStorage.getSessionToken();
    if (token == null || token.isEmpty) return;

    final currentUser = widget.authRepository.currentUser;
    final result = await widget.syncEngine.syncMissedEvents(
      token,
      currentUserId: currentUser?.id,
      onSyncCompleted: () {
        widget.chatRepository.loadLocalMessages();
        widget.chatRepository.processPendingQueue();
      },
    );

    if (result.unauthorized) {
      await _handleUnauthorized(widget.authRepository, widget.socketClient);
    }
  }

  void _startCatchUpTimer() {
    _catchUpTimer?.cancel();
    _catchUpTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      if (widget.chatRepository.isAppInBackground) return;
      if (!widget.authRepository.isAuthenticated) return;
      await _performSync();
    });
  }

  void _stopCatchUpTimer() {
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
  }

  Future<void> _onNotificationClicked(RemoteMessage message) async {
    debugPrint('[Main] Notification clicked, syncing messages...');
    final token = widget.authStorage.getSessionToken();
    if (token == null || token.isEmpty) return;

    if (!widget.socketClient.isConnected) {
      widget.socketClient.connect(token);
    }

    final currentUser = widget.authRepository.currentUser;
    final result = await widget.syncEngine.syncMissedEvents(
      token,
      currentUserId: currentUser?.id,
      onSyncCompleted: () {
        widget.chatRepository.loadLocalMessages();
        widget.chatRepository.processPendingQueue();
        _markAllUnreadAsRead();
      },
    );

    if (result.unauthorized) {
      await _handleUnauthorized(widget.authRepository, widget.socketClient);
    }
  }

  Future<void> _markAllUnreadAsRead() async {
    final currentUser = widget.authRepository.currentUser;
    if (currentUser == null) return;

    final unreadIds = widget.chatRepository.messages
        .where((m) => m.senderId != currentUser.id && m.readAt == null)
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      await widget.chatRepository.markMessagesAsRead(unreadIds);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isBackground = state != AppLifecycleState.resumed;
    widget.chatRepository.isAppInBackground = isBackground;
    debugPrint('[LIFECYCLE] App background state: $isBackground ($state)');

    if (widget.socketClient.isConnected) {
      widget.socketClient.sendPresence(online: !isBackground);
    }

    if (state == AppLifecycleState.resumed) {
      widget.notifService.cancelAllNotifications();
      _debouncedSync();
    }
  }

  void _ensureConnectedAndSynced() {
    if (_hasInitialized) return;
    _hasInitialized = true;

    final token = widget.authStorage.getSessionToken();
    if (token == null || token.isEmpty) return;

    if (!widget.socketClient.isConnected) {
      widget.socketClient.connect(token);
    }

    final currentUser = widget.authRepository.currentUser;

    widget.syncEngine
        .syncMissedEvents(
          token,
          currentUserId: currentUser?.id,
          onSyncCompleted: () {
            widget.chatRepository.loadLocalMessages();
            widget.chatRepository.processPendingQueue();
          },
        )
        .then((result) async {
      if (result.unauthorized) {
        await _handleUnauthorized(widget.authRepository, widget.socketClient);
        return;
      }

      if (result.newMessagesCount > 0 &&
          widget.chatRepository.isAppInBackground) {
        NotificationService.instance.showMissedMessagesNotification(
          count: result.newMessagesCount,
          sender: result.lastMessageSender,
          text: result.lastMessageText,
        );
      }
    }).catchError((e) {
      debugPrint('[Main] Sync error: $e');
    });

    widget.authStorage.getOrCreateDeviceIdentifier().then((deviceId) {
      FirebaseMessagingService.instance.registerTokenOnServer(
        sessionToken: token,
        deviceId: deviceId,
      );
    });

    _startCatchUpTimer();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guysgram',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,

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
          if (widget.authRepository.isLoading &&
              widget.authRepository.status == AuthStatus.initial) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (widget.authRepository.status == AuthStatus.unauthenticated) {
            return LoginScreen(
              authRepository: widget.authRepository,
              onAuthenticated: () {
                _hasInitialized = false;
                _ensureConnectedAndSynced();
              },
            );
          }

          if (widget.authRepository.status == AuthStatus.pendingApproval) {
            return PendingApprovalScreen(
              authRepository: widget.authRepository,
              onApproved: () {
                _hasInitialized = false;
                _ensureConnectedAndSynced();
              },
            );
          }

          if (widget.authRepository.isAuthenticated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _ensureConnectedAndSynced();
            });

            return ChatScreen(
              authRepository: widget.authRepository,
              chatRepository: widget.chatRepository,
              onLogout: () async {
                _hasInitialized = false;
                _stopCatchUpTimer();
                widget.socketClient.sendPresence(online: false);
                await Future.delayed(const Duration(milliseconds: 200));
                widget.socketClient.disconnect();
                await FirebaseMessagingService.instance.deleteToken();
                await widget.notifService.cancelAllNotifications();
                await widget.authRepository.logout();
              },
            );
          }

          return LoginScreen(
            authRepository: widget.authRepository,
            onAuthenticated: () {
              _hasInitialized = false;
              _ensureConnectedAndSynced();
            },
          );
        },
      ),
    );
  }
}