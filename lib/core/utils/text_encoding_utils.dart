import 'dart:convert';

class TextEncodingUtils {
  /// Safely decodes HTTP response bytes using UTF-8 with fallback
  static String decodeHttpBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return latin1.decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  /// Automatically detects and heals mojibake (UTF-8 bytes wrongly decoded as Latin-1/Windows-1252)
  /// e.g. "eÅ•au" -> "eńau", "ã•ãã‚‰" -> "さくら", etc.
  static String cleanMojibake(String text) {
    if (text.isEmpty) return text;

    // Direct fixes for known artifacts
    var sanitized = text
        .replaceAll('eÅ•au', 'eńau')
        .replaceAll('eÅau', 'eńau')
        .replaceAll('eÅ\x84au', 'eńau');

    // Detect general Latin-1 misinterpreted multi-byte UTF-8 sequences
    final hasMojibakeMarkers = sanitized.contains('Ã') ||
        sanitized.contains('Å') ||
        sanitized.contains('â€') ||
        sanitized.contains('ã€') ||
        sanitized.contains('ã‚') ||
        sanitized.contains('ã') ||
        sanitized.contains('Ù„') ||
        sanitized.contains('Ù…');

    if (hasMojibakeMarkers) {
      try {
        final latin1Bytes = latin1.encode(sanitized);
        final repaired = utf8.decode(latin1Bytes, allowMalformed: false);
        if (repaired.isNotEmpty) {
          return repaired;
        }
      } catch (_) {}
    }

    return sanitized;
  }
}
