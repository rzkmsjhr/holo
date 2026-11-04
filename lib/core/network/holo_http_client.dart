import 'package:http/http.dart' as http;

/// Shared persistent HTTP client instance with keep-alive socket reuse.
/// Avoids the expensive TCP + TLS handshake penalty on every request.
class HoloHttpClient {
  static final http.Client client = http.Client();
}
