import 'dart:async';
import 'package:http/http.dart' as http;

enum ConnectivityStatus {
  online,
  slow,
  offline,
}

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  static const String _primaryPingUrl =
      'https://itunes.apple.com/search?term=ping&limit=1';
  static const String _secondaryPingUrl =
      'https://cloudflare-dns.com/dns-query?name=google.com&type=A';
  static const Duration _checkInterval = Duration(seconds: 15);
  static const Duration _pingTimeout = Duration(seconds: 6);

  Timer? _timer;
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
    checkConnectivity();
    _timer = Timer.periodic(_checkInterval, (_) => checkConnectivity());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> checkConnectivity() async {
    final sw = Stopwatch()..start();
    bool reachable = false;

    try {
      final res = await http
          .get(Uri.parse(_primaryPingUrl))
          .timeout(_pingTimeout);
      sw.stop();
      if (res.statusCode >= 200 && res.statusCode < 400) {
        reachable = true;
      }
    } catch (_) {
      // Try secondary endpoint fallback
      try {
        final res = await http
            .get(Uri.parse(_secondaryPingUrl))
            .timeout(_pingTimeout);
        sw.stop();
        if (res.statusCode >= 200 && res.statusCode < 400) {
          reachable = true;
        }
      } catch (_) {
        reachable = false;
      }
    }

    _lastLatencyMs = sw.elapsedMilliseconds;
    ConnectivityStatus newStatus;

    if (!reachable) {
      newStatus = ConnectivityStatus.offline;
    } else if (_lastLatencyMs > 4500) {
      newStatus = ConnectivityStatus.slow;
    } else {
      newStatus = ConnectivityStatus.online;
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
