import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

enum ConnectivityStatus {
  online,
  slow,
  offline,
}

class ConnectivityService with WidgetsBindingObserver {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  static const String _primaryPingUrl =
      'https://clients3.google.com/generate_204';
  static const String _secondaryPingUrl =
      'https://itunes.apple.com/search?term=ping&limit=1';
  static const Duration _checkInterval = Duration(seconds: 25);
  static const Duration _pingTimeout = Duration(seconds: 7);

  Timer? _timer;
  bool _isObserverRegistered = false;
  bool _isInForeground = true;
  int _consecutiveFailures = 0;
  ConnectivityStatus _currentStatus = ConnectivityStatus.online;
  int _lastLatencyMs = 0;
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  ConnectivityStatus get status => _currentStatus;
  bool get isOnline => _currentStatus != ConnectivityStatus.offline;
  bool get isSlow => _currentStatus == ConnectivityStatus.slow;
  int get latencyMs => _lastLatencyMs;
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  void startMonitoring() {
    if (_timer != null) return;
    try {
      if (!_isObserverRegistered) {
        WidgetsBinding.instance.addObserver(this);
        _isObserverRegistered = true;
      }
    } catch (_) {}

    checkConnectivity();
    _timer = Timer.periodic(_checkInterval, (_) {
      // Do not run passive pings when screen is off / app is in background
      // to prevent Android Doze socket throttling from triggering false offline states.
      if (_isInForeground) {
        checkConnectivity();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasInForeground = _isInForeground;
    _isInForeground = state == AppLifecycleState.resumed;
    if (!wasInForeground && _isInForeground) {
      // Reset failure counter on wake and verify silently
      _consecutiveFailures = 0;
      if (_currentStatus == ConnectivityStatus.offline) {
        markOnline();
      }
    }
  }

  void markOnline() {
    _consecutiveFailures = 0;
    if (_currentStatus != ConnectivityStatus.online) {
      _currentStatus = ConnectivityStatus.online;
      _statusController.add(_currentStatus);
    }
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
    try {
      if (_isObserverRegistered) {
        WidgetsBinding.instance.removeObserver(this);
        _isObserverRegistered = false;
      }
    } catch (_) {}
  }

  Future<bool> checkConnectivity({bool forceImmediate = false}) async {
    if (!_isInForeground && !forceImmediate) {
      return isOnline;
    }

    final sw = Stopwatch()..start();
    bool reachable = false;

    try {
      final res = await http
          .get(Uri.parse(_primaryPingUrl))
          .timeout(_pingTimeout);
      sw.stop();
      if (res.statusCode == 204 ||
          (res.statusCode >= 200 && res.statusCode < 400)) {
        reachable = true;
      }
    } catch (_) {
      try {
        final res = await http
            .get(Uri.parse(_secondaryPingUrl))
            .timeout(_pingTimeout);
        sw.stop();
        if (res.statusCode >= 200 && res.statusCode < 400) {
          reachable = true;
        }
      } catch (_) {
        try {
          final res = await http
              .get(Uri.parse(
                  'https://cloudflare-dns.com/dns-query?name=google.com&type=A'))
              .timeout(_pingTimeout);
          sw.stop();
          if (res.statusCode >= 200 && res.statusCode < 400) {
            reachable = true;
          }
        } catch (_) {
          reachable = false;
        }
      }
    }

    _lastLatencyMs = sw.elapsedMilliseconds;
    ConnectivityStatus newStatus = _currentStatus;

    if (!reachable) {
      _consecutiveFailures++;
      if (forceImmediate || _consecutiveFailures >= 2) {
        newStatus = ConnectivityStatus.offline;
      }
    } else {
      _consecutiveFailures = 0;
      if (_lastLatencyMs > 5000) {
        newStatus = ConnectivityStatus.slow;
      } else {
        newStatus = ConnectivityStatus.online;
      }
    }

    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _statusController.add(_currentStatus);
    }

    return reachable;
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}
