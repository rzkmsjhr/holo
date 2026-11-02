import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';

class MonochromeService {
  static const String baseUrl = 'https://tracks.monochrome.st';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  DateTime? _cooldownUntil;
  static const Duration _failureCooldown = Duration(seconds: 60);

  /// Searches tracks on Monochrome for lossless FLAC audio
  Future<List<Track>> searchTracks(String query, {int limit = 20}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    if (_cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!)) {
      return [];
    }

    final url = Uri.parse(
        '$baseUrl/search/tracks?q=${Uri.encodeComponent(cleanQuery)}&limit=$limit');

    try {
      final res = await http
          .get(url, headers: {
            if (!kIsWeb) 'User-Agent': userAgent,
            'Accept': 'application/json',
          })
          .timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) {
        _cooldownUntil = DateTime.now().add(_failureCooldown);
        return [];
      }

      _cooldownUntil = null;
      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      final List rawTracks = data['tracks'] ?? [];
      final List<Track> tracks = [];

      for (final t in rawTracks) {
        final id = t['trackId'] ?? t['id'];
        if (id == null) continue;

        final title = TextEncodingUtils.cleanMojibake(
            t['title']?.toString() ?? 'Unknown Title');
        final artist = TextEncodingUtils.cleanMojibake(
            _extractArtistNames(t['artistNames'], t['artists']));
        final artwork = t['artwork'] ?? t['cover'] ?? '';
        final durMs = t['duration'] ?? 0;
        final durSecs = (durMs is num) ? (durMs / 1000).round() : 0;
        final recordingId = t['recordingId'] ?? id;
        final streamUrl = '$baseUrl/track/$recordingId';

        final isHiRes = t['audioQuality'] == 'HI_RES_LOSSLESS' ||
            t['audioQuality'] == 'HI_RES' ||
            t['bitDepth'] == 24;

        tracks.add(Track(
          id: 'mono_$id',
          title: title,
          artist: artist,
          thumbnailUrl: artwork,
          durationSeconds: durSecs,
          flacStreamUrl: streamUrl,
          audioSource: 'monochrome',
          isLossless: true,
          audioFormat: isHiRes
              ? '24-bit • 96kHz Lossless FLAC'
              : '16-bit • 44.1kHz Lossless FLAC',
        ));
      }

      return tracks;
    } catch (_) {
      _cooldownUntil = DateTime.now().add(_failureCooldown);
      return [];
    }
  }

  /// Verifies that a Monochrome stream URL is reachable and strictly serves valid FLAC audio bytes.
  Future<bool> verifyStreamUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              if (!kIsWeb) 'User-Agent': userAgent,
              'Range': 'bytes=0-3',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (res.statusCode != 200 && res.statusCode != 206) {
        return false;
      }

      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('text/html') ||
          contentType.contains('application/json')) {
        return false;
      }

      // A genuine lossless FLAC stream strictly starts with the 4-byte ASCII signature 'fLaC' [0x66, 0x4C, 0x61, 0x43]
      if (res.bodyBytes.length >= 4) {
        final isFlacHeader = res.bodyBytes[0] == 0x66 &&
            res.bodyBytes[1] == 0x4C &&
            res.bodyBytes[2] == 0x61 &&
            res.bodyBytes[3] == 0x43;
        return isFlacHeader;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  String _extractArtistNames(dynamic artistNames, dynamic artists) {
    if (artistNames is List && artistNames.isNotEmpty) {
      return artistNames.join(', ');
    }
    if (artists is List && artists.isNotEmpty) {
      final names = artists
          .map((a) => a['name'] ?? a['displayName'] ?? '')
          .where((s) => s.toString().trim().isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names.join(', ');
    }
    return 'Unknown Artist';
  }
}
