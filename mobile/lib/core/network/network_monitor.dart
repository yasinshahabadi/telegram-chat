import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// وضعیت دسترسی به شبکه در دستگاه
enum NetworkState {
  online,
  offline,
}

/// سرویس پایش هوشمند وضعیت اتصال اینترنت (وای‌فای، داده همراه و فیلترشکن)
class NetworkMonitor {
  static final NetworkMonitor instance = NetworkMonitor._internal();
  final Connectivity _connectivity = Connectivity();

  NetworkState _currentState = NetworkState.online;
  final _stateController = StreamController<NetworkState>.broadcast();
  StreamSubscription? _subscription;

  VoidCallback? onNetworkRestored;

  NetworkMonitor._internal();

  NetworkState get currentState => _currentState;
  bool get isOnline => _currentState == NetworkState.online;
  Stream<NetworkState> get stateStream => _stateController.stream;

  /// مقداردهی اولیه و آغاز گوش دادن به تغییرات وضعیت شبکه
  Future<void> initialize() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateState(results);
    } catch (_) {}

    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateState(results);
    });
  }

  void _updateState(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);

    final newState = hasConnection ? NetworkState.online : NetworkState.offline;

    // اگر قبلاً آفلاین بوده و اکنون آنلاین شده، رویداد بازیابی شبکه را فعال کن
    if (_currentState == NetworkState.offline && newState == NetworkState.online) {
      onNetworkRestored?.call();
    }

    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _stateController.close();
  }
}
