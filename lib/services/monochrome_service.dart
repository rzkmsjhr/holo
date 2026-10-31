import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';

class MonochromeService {
  static const String baseUrl = 'https://tracks.monochrome.st';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  /// Searches tracks on Monochrome for lossless FLAC audio
  Future<List<Track>> searchTracks(String query, {int limit = 20}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final url = Uri.parse(
        '$baseUrl/search/tracks?q=${Uri.encodeComponent(cleanQuery)}&limit=$limit');

    try {
      final res = await http.get(url, headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      });

      if (res.statusCode != 200) return [];

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      final List rawTracks = data['tracks'] ?? [];
      final List<Track> tracks = [];

      for (final t in rawTracks) {
        final id = t['trackId'] ?? t['id'];
        if (id == null) continue;

        final title = t['title'] ?? 'Unknown Title';
        final artist = _extractArtistNames(t['artistNames'], t['artists']);
        final artwork = t['artwork'] ?? t['cover'] ?? '';
        final durMs = t['duration'] ?? 0;
        final durSecs = (durMs is num) ? (durMs / 1000).round() : 0;
        final recordingId = t['recordingId'] ?? id;
        final streamUrl = '$baseUrl/track/$recordingId';

        tracks.add(Track(
          id: 'mono_$id',
          title: title,
          artist: artist,
          thumbnailUrl: artwork,
          durationSeconds: durSecs,
          flacStreamUrl: streamUrl,
          audioSource: 'monochrome',
          isLossless: true,
          audioFormat: '24-bit • 96kHz',
        ));
      }

      return tracks;
    } catch (_) {
      return [];
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
