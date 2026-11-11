import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Shared persistent HTTP client instance with keep-alive socket reuse,
/// strict idle connection recycling, and reset capability on network switch.
class HoloHttpClient {
  static http.Client _client = _createClient();

  static http.Client get client => _client;

  static http.Client _createClient() {
    if (!kIsWeb) {
      final inner = HttpClient()
        ..idleTimeout = const Duration(seconds: 12)
        ..connectionTimeout = const Duration(seconds: 5)
        ..maxConnectionsPerHost = 8;
      return IOClient(inner);
    }
    return http.Client();
  }

  /// Closes dead keep-alive sockets and allocates a fresh client on network resume / reconnect.
  static void resetConnections() {
    try {
      _client.close();
    } catch (_) {}
    _client = _createClient();
  }
}
