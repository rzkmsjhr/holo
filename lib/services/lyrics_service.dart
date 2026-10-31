import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../core/utils/text_encoding_utils.dart';

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}

class LyricsService {
  static const String _lrclibGetUrl = 'https://lrclib.net/api/get';
  static const String _lrclibSearchUrl = 'https://lrclib.net/api/search';

  static final Map<String, List<LyricLine>> _cache = {};

  /// Cleans titles of common YouTube metadata noise to maximize LRCLIB match rates
  String cleanTitle(String title) {
    var cleaned = title
        .replaceAll(
            RegExp(
                r'\([^)]*(?:version|remix|official|video|audio|lyrics?|live|remaster|edit|prod|feat|ft)[^)]*\)',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\[[^\]]*(?:version|remix|official|video|audio|lyrics?|live|remaster|edit|prod|feat|ft)[^\]]*\]',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\s*[-|~/:]\s*(?:official(?:\s*music)?\s*video|lyric\s*video|official\s*audio|video|audio|visualizer|remaster(?:ed)?|live).*$',
                caseSensitive: false),
            '')
        .trim();

    return cleaned.isNotEmpty ? cleaned : title;
  }

  /// Cleans artist names of common channel noise
  String cleanArtist(String artist) {
    var cleaned = artist
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*Official', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '')
        .trim();

    return cleaned.isNotEmpty ? cleaned : artist;
  }

  /// Validates that a lyrics result contains real, complete lyrics rather than a single placeholder/troll line
  bool _isValidLyrics(List<LyricLine> lines) {
    if (lines.length < 3) return false;
    final totalChars = lines.fold<int>(0, (sum, l) => sum + l.text.length);
    return totalChars >= 15;
  }

  /// Fetches synchronized timestamped lyrics for a track
  Future<List<LyricLine>> fetchLyrics({
    required String trackName,
    required String artistName,
    int? durationSeconds,
    String? youtubeVideoId,
  }) async {
    final cacheKey = '$trackName|$artistName';
    if (_cache.containsKey(cacheKey) &&
        _cache[cacheKey] != null &&
        _cache[cacheKey]!.isNotEmpty) {
      return _cache[cacheKey]!;
    }

    final cleanedTitle = cleanTitle(trackName);
    final cleanedArtist = cleanArtist(artistName);

    // Parallel fetch: try both LRCLIB and YouTube closed captions simultaneously
    final lrclibFuture = _fetchFromLrclibAll(
      cleanedTitle: cleanedTitle,
      cleanedArtist: cleanedArtist,
      rawTitle: trackName,
      rawArtist: artistName,
      durationSeconds: durationSeconds,
    );

    final ytFuture = _fetchFromYouTube(
      youtubeVideoId,
      cleanedTitle,
      cleanedArtist,
    );

    final results = await Future.wait([
      lrclibFuture.catchError((_) => <LyricLine>[]),
      ytFuture.catchError((_) => <LyricLine>[]),
    ]);

    final lrclibResult = results[0];
    final ytResult = results[1];

    if (_isValidLyrics(lrclibResult)) {
      _cache[cacheKey] = lrclibResult;
      return lrclibResult;
    }

    if (_isValidLyrics(ytResult)) {
      _cache[cacheKey] = ytResult;
      return ytResult;
    }

    if (lrclibResult.isNotEmpty) {
      _cache[cacheKey] = lrclibResult;
      return lrclibResult;
    }

    if (ytResult.isNotEmpty) {
      _cache[cacheKey] = ytResult;
      return ytResult;
    }

    return [];
  }

  Future<List<LyricLine>> _fetchFromLrclibAll({
    required String cleanedTitle,
    required String cleanedArtist,
    required String rawTitle,
    required String rawArtist,
    int? durationSeconds,
  }) async {
    try {
      // 1. Search endpoint with cleaned query
      var res = await _fetchFromLrclibSearch(
        query: '$cleanedTitle $cleanedArtist',
        targetDurationSeconds: durationSeconds,
      );
      if (_isValidLyrics(res)) return res;

      // 2. Direct get with cleaned title and artist
      res = await _fetchFromLrclibGet(cleanedTitle, cleanedArtist, durationSeconds);
      if (_isValidLyrics(res)) return res;

      // 3. Fallback search with raw query if different
      if (cleanedTitle != rawTitle || cleanedArtist != rawArtist) {
        res = await _fetchFromLrclibSearch(
          query: '$rawTitle $rawArtist',
          targetDurationSeconds: durationSeconds,
        );
        if (_isValidLyrics(res)) return res;
      }

      if (res.isNotEmpty) return res;
    } catch (_) {}
    return [];
  }

  Future<List<LyricLine>> _fetchFromYouTube(
      String? videoId, String title, String artist) async {
    final yt = YoutubeExplode();
    try {
      String? targetId = videoId;
      if (targetId == null ||
          targetId.isEmpty ||
          targetId.startsWith('trending_')) {
        try {
          final searchResults = await yt.search
              .search('$title $artist lyrics')
              .timeout(const Duration(seconds: 4));
          if (searchResults.isNotEmpty) {
            targetId = searchResults.first.id.value;
          } else {
            final standardResults = await yt.search
                .search('$title $artist')
                .timeout(const Duration(seconds: 4));
            if (standardResults.isNotEmpty) {
              targetId = standardResults.first.id.value;
            }
          }
        } catch (_) {}
      }

      if (targetId == null || targetId.isEmpty) return [];

      ClosedCaptionManifest manifest;
      try {
        manifest = await yt.videos.closedCaptions
            .getManifest(targetId)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        return [];
      }

      if (manifest.tracks.isEmpty) {
        try {
          final lyricSearch = await yt.search
              .search('$title $artist lyrics')
              .timeout(const Duration(seconds: 4));
          for (final video in lyricSearch.take(3)) {
            if (video.id.value == targetId) continue;
            try {
              final m = await yt.videos.closedCaptions
                  .getManifest(video.id)
                  .timeout(const Duration(seconds: 3));
              if (m.tracks.isNotEmpty) {
                final trackInfo = m.tracks.firstWhere(
                  (t) => !t.isAutoGenerated,
                  orElse: () => m.tracks.first,
                );
                final sub = await yt.videos.closedCaptions
                    .get(trackInfo)
                    .timeout(const Duration(seconds: 3));
                final lines = sub.captions
                    .map((c) => LyricLine(
                          timestamp: c.offset,
                          text: c.text.replaceAll('\n', ' ').trim(),
                        ))
                    .where((l) => l.text.isNotEmpty && !l.text.startsWith('['))
                    .toList();
                if (lines.length >= 4) return lines;
              }
            } catch (_) {}
          }
        } catch (_) {}
        return [];
      }

      final trackInfo = manifest.tracks.firstWhere(
        (t) => !t.isAutoGenerated,
        orElse: () => manifest.tracks.first,
      );

      final sub = await yt.videos.closedCaptions
          .get(trackInfo)
          .timeout(const Duration(seconds: 4));

      final lines = sub.captions
          .map((c) => LyricLine(
                timestamp: c.offset,
                text: c.text.replaceAll('\n', ' ').trim(),
              ))
          .where((l) => l.text.isNotEmpty && !l.text.startsWith('['))
          .toList();

      return lines;
    } catch (_) {
      return [];
    } finally {
      yt.close();
    }
  }

  Future<List<LyricLine>> _fetchFromLrclibSearch({
    required String query,
    int? targetDurationSeconds,
  }) async {
    final uri = Uri.parse('$_lrclibSearchUrl?q=${Uri.encodeQueryComponent(query)}');

    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'PulseAudio/1.0.0 (https://github.com/pulseaudio)',
      }).timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) return [];

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final list = jsonDecode(decoded);
      if (list is! List || list.isEmpty) return [];

      // Collect all candidates with syncedLyrics
      final candidates = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final synced = item['syncedLyrics'] as String?;
          if (synced != null && synced.trim().isNotEmpty) {
            candidates.add(item);
          }
        }
      }

      if (candidates.isEmpty) {
        // Plain lyrics fallback if no synced candidates exist
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final plain = item['plainLyrics'] as String?;
            if (plain != null && plain.trim().isNotEmpty) {
              final parsed = plain
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .map((line) => LyricLine(timestamp: Duration.zero, text: line.trim()))
                  .toList();
              if (_isValidLyrics(parsed)) return parsed;
            }
          }
        }
        return [];
      }

      // Rank synced candidates:
      // Prefer candidates matching target duration closely, then by highest line count
      candidates.sort((a, b) {
        final linesA = (a['syncedLyrics'] as String).split('\n').length;
        final linesB = (b['syncedLyrics'] as String).split('\n').length;

        if (targetDurationSeconds != null && targetDurationSeconds > 0) {
          final durA = (a['duration'] as num?)?.toDouble() ?? 0.0;
          final durB = (b['duration'] as num?)?.toDouble() ?? 0.0;
          final diffA = (durA - targetDurationSeconds).abs();
          final diffB = (durB - targetDurationSeconds).abs();

          if (diffA < 6 && diffB >= 6) return -1;
          if (diffB < 6 && diffA >= 6) return 1;
        }

        return linesB.compareTo(linesA);
      });

      for (final candidate in candidates) {
        final syncedText = candidate['syncedLyrics'] as String;
        final parsed = parseLrc(syncedText);
        if (_isValidLyrics(parsed)) {
          return parsed;
        }
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<LyricLine>> _fetchFromLrclibGet(
      String title, String artist, int? durationSeconds) async {
    final queryParams = {
      'track_name': title,
      'artist_name': artist,
    };
    if (durationSeconds != null && durationSeconds > 0) {
      queryParams['duration'] = durationSeconds.toString();
    }

    final uri = Uri.parse(_lrclibGetUrl).replace(queryParameters: queryParams);

    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'PulseAudio/1.0.0 (https://github.com/pulseaudio)',
      }).timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) return [];

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      final syncedLyrics = data['syncedLyrics'] as String?;

      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        final parsed = parseLrc(syncedLyrics);
        if (_isValidLyrics(parsed)) {
          return parsed;
        }
      }

      final plainLyrics = data['plainLyrics'] as String?;
      if (plainLyrics != null && plainLyrics.isNotEmpty) {
        final parsed = plainLyrics
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((line) => LyricLine(timestamp: Duration.zero, text: line.trim()))
            .toList();
        if (_isValidLyrics(parsed)) {
          return parsed;
        }
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  /// Parses synchronized [mm:ss.xx] lines into timestamped objects
  List<LyricLine> parseLrc(String lrcText) {
    final lines = lrcText.split('\n');
    final List<LyricLine> parsed = [];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final line in lines) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final mins = int.tryParse(match.group(1)!) ?? 0;
        final secs = int.tryParse(match.group(2)!) ?? 0;
        final millis = int.tryParse(match.group(3)!.padRight(3, '0')) ?? 0;
        final text = match.group(4)!.trim();

        if (text.isNotEmpty) {
          final timestamp =
              Duration(minutes: mins, seconds: secs, milliseconds: millis);
          parsed.add(LyricLine(timestamp: timestamp, text: text));
        }
      }
    }

    return parsed;
  }
}
