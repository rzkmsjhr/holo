import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../core/utils/text_encoding_utils.dart';

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});

  Map<String, dynamic> toJson() => {
        'ms': timestamp.inMilliseconds,
        'text': text,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['ms'] as num?)?.toInt() ?? 0),
      text: LyricsService.normalizeLyricText(json['text']?.toString() ?? ''),
    );
  }
}

class LyricsService {
  static const String _lrclibGetUrl = 'https://lrclib.net/api/get';
  static const String _lrclibSearchUrl = 'https://lrclib.net/api/search';
  static const String _diskPrefix = 'lyrics_cache_v1_';

  static final Map<String, List<LyricLine>> _cache = {};

  static String _makeKey(String title, String artist) =>
      '${title.toLowerCase().trim()}|${artist.toLowerCase().trim()}';

  /// Returns cached lyrics synchronously from memory if already loaded
  List<LyricLine>? getCachedSync(String trackName, String artistName) {
    final k1 = _makeKey(trackName, artistName);
    if (_cache.containsKey(k1) && _cache[k1]!.isNotEmpty) {
      return _cache[k1];
    }
    final k2 = _makeKey(cleanTitle(trackName), cleanArtist(artistName));
    if (_cache.containsKey(k2) && _cache[k2]!.isNotEmpty) {
      return _cache[k2];
    }
    return null;
  }

  Future<List<LyricLine>?> _loadFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_diskPrefix$key');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final lines = decoded
            .map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
            .where((l) => l.text.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          _cache[key] = lines;
          return lines;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveToDisk(String key1, String key2, List<LyricLine> lines) async {
    if (lines.isEmpty) return;
    _cache[key1] = lines;
    _cache[key2] = lines;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(lines.map((l) => l.toJson()).toList());
      await prefs.setString('$_diskPrefix$key1', encoded);
      if (key2 != key1) {
        await prefs.setString('$_diskPrefix$key2', encoded);
      }
    } catch (_) {}
  }

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

  /// Detects expected primary language code for a song based on title and artist
  static String detectExpectedLanguage(String title, String artist) {
    final combined = '$title $artist';

    // 1. Korean Hangul
    if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(combined)) {
      return 'ko';
    }

    // 2. Japanese Kana
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(combined)) {
      return 'ja';
    }

    // 3. Chinese Hanzi
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(combined)) {
      return 'zh';
    }

    // 4. Indonesian / Malay common keywords and artists
    final lower = combined.toLowerCase();
    const idIndicators = [
      'terbelah', 'jadi', 'dua', 'bukan', 'cinta', 'kamu', 'dan', 'yang', 'tak',
      'jangan', 'rindu', 'hati', 'lagu', 'gloria jessica', 'ade govinda', 'tiara andini',
      'mahalini', 'judika', 'tulus', 'sheila on 7', 'dewa 19', 'noah', 'vierratale',
      'hindia', 'fiersa besari', 'sal priadi', 'bernardya', 'yura yunita'
    ];
    for (final ind in idIndicators) {
      if (lower.contains(ind)) {
        return 'id';
      }
    }

    // Default to English for Latin alphabet titles
    return 'en';
  }

  /// Normalizes lyric text by removing musical notes, bracketed noise tags,
  /// sound effects ([music], [musik], [bernyanyi], (applause)), and HTML entities.
  static String normalizeLyricText(String text) {
    var cleaned = text;

    // 1. Strip XML / WebVTT subtitle tags (<c.color>, <font>, etc.) & styling blocks
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\{[^}]*\}'), '');

    // 2. Decode HTML entities
    cleaned = cleaned
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');

    // 3. Strip musical note symbols (♪, ♫, ♩, ♬, ♭, ♮, ♯)
    cleaned = cleaned.replaceAll(RegExp(r'[♪♫♩♬♭♮♯]+'), '');

    // 4. Universal Square & Lenticular Bracket Stripping (Inline & Standalone):
    // In lyric transcriptions, singers never sing bracketed content.
    // Brackets strictly denote ASR sound descriptions ([musik], [bernyanyi], [music],
    // [applause], [música]) or structural section headers ([Chorus], [Verse 1], 【サビ】).
    cleaned = cleaned
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'［[^］]*］'), '')
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'〔[^〕]*〕'), '')
        .replaceAll(RegExp(r'《[^》]*》'), '');

    // 5. Multi-lingual Parenthetical Audio Descriptor Stripping:
    // Parentheses (...) can contain legitimate backing vocals ('(I need you)', '(cinta)').
    // Therefore, only strip known multi-lingual sound effect cues and production markers.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\((?:music|musik|música|musique|musica|singing|bernyanyi|canto|cantando|chant|vocalizing|applause|tepuk\s*tangan|aplausos|applaudissements|laughter|tertawa|risas|rires|cheering|sorak(?:an)?|instrumental|instrumen|intro|outro|beat\s*drops?|solo|guitar\s*solo|drum\s*solo|whistling|siulan|screaming|teriakan)[^)]*\)',
        caseSensitive: false,
      ),
      '',
    );

    // If an entire line is enclosed in parentheses and contains purely a non-lyric cue, prune it
    if (RegExp(r'^\s*\([^)]{0,35}\)\s*$').hasMatch(cleaned)) {
      final inside = cleaned
          .replaceAll(RegExp(r'^\s*\(|\)\s*$'), '')
          .toLowerCase()
          .trim();
      const nonLyricCues = {
        'instrumental',
        'instrumen',
        'music',
        'musik',
        'música',
        'musique',
        'musica',
        'solo',
        'guitar solo',
        'drum solo',
        'intro',
        'outro',
        'applause',
        'cheering',
      };
      if (inside.isEmpty || nonLyricCues.contains(inside)) {
        cleaned = '';
      }
    }

    // 6. Clean dangling spaces before punctuation left by tag removals
    cleaned = cleaned.replaceAll(RegExp(r'\s+([.,!?:;])'), r'$1');

    // 7. Normalize whitespace and trim
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 8. If the line only consists of residual punctuation without letters/digits, treat as empty
    if (RegExp(r'^[.,!?:;\-_~—]+$').hasMatch(cleaned)) {
      cleaned = '';
    }

    return cleaned;
  }

  /// Selects the best caption track that matches the song's expected language,
  /// rejecting unrelated translations (e.g. Chinese or Turkish on English/Korean tracks).
  static ClosedCaptionTrackInfo? selectBestCaptionTrack(
      List<ClosedCaptionTrackInfo> tracks, String expectedLang) {
    if (tracks.isEmpty) return null;

    // 1. Exact match with non-auto caption
    for (final t in tracks) {
      final code = t.language.code.toLowerCase();
      if (!t.isAutoGenerated &&
          (code == expectedLang || code.startsWith('$expectedLang-'))) {
        return t;
      }
    }

    // 2. Exact match with auto-generated caption
    for (final t in tracks) {
      final code = t.language.code.toLowerCase();
      if (code == expectedLang || code.startsWith('$expectedLang-')) {
        return t;
      }
    }

    // 3. If expected is English or Indonesian, allow English captions
    if (expectedLang != 'ko' && expectedLang != 'ja' && expectedLang != 'zh') {
      for (final t in tracks) {
        final code = t.language.code.toLowerCase();
        if (!t.isAutoGenerated && (code == 'en' || code.startsWith('en-'))) {
          return t;
        }
      }
      for (final t in tracks) {
        final code = t.language.code.toLowerCase();
        if (code == 'en' || code.startsWith('en-')) {
          return t;
        }
      }
    }

    // 4. Filter out incompatible foreign translation languages
    const incompatibleLangs = {
      'zh', 'zh-hans', 'zh-hant', 'tr', 'ru', 'ar', 'th', 'vi', 'fa', 'he'
    };

    if (!incompatibleLangs.contains(expectedLang)) {
      final compatible = tracks.where((t) {
        final prefix = t.language.code.toLowerCase().split('-').first;
        return !incompatibleLangs.contains(prefix);
      }).toList();

      if (compatible.isNotEmpty) {
        return compatible.firstWhere(
          (t) => !t.isAutoGenerated,
          orElse: () => compatible.first,
        );
      }
      return null;
    }

    // If expected is Korean or Japanese, reject Turkish, Arabic, etc.
    if (expectedLang == 'ko' || expectedLang == 'ja') {
      final compatible = tracks.where((t) {
        final code = t.language.code.toLowerCase();
        return code.startsWith('ko') || code.startsWith('ja') || code.startsWith('en');
      }).toList();

      if (compatible.isNotEmpty) {
        return compatible.firstWhere(
          (t) => !t.isAutoGenerated,
          orElse: () => compatible.first,
        );
      }
      return null;
    }

    return tracks.firstWhere((t) => !t.isAutoGenerated, orElse: () => tracks.first);
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
    final cleanedTitle = cleanTitle(trackName);
    final cleanedArtist = cleanArtist(artistName);
    final cacheKey = _makeKey(trackName, artistName);
    final cleanKey = _makeKey(cleanedTitle, cleanedArtist);

    // 1. Check in-memory cache
    final memCached = getCachedSync(trackName, artistName);
    if (memCached != null && memCached.isNotEmpty) {
      return memCached;
    }

    // 2. Check persistent disk cache (SharedPreferences)
    final diskCached =
        await _loadFromDisk(cacheKey) ?? await _loadFromDisk(cleanKey);
    if (diskCached != null && diskCached.isNotEmpty) {
      _cache[cacheKey] = diskCached;
      _cache[cleanKey] = diskCached;
      return diskCached;
    }

    // 3. Parallel fetch: try both LRCLIB and YouTube closed captions simultaneously
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
      await _saveToDisk(cacheKey, cleanKey, lrclibResult);
      return lrclibResult;
    }

    if (_isValidLyrics(ytResult)) {
      await _saveToDisk(cacheKey, cleanKey, ytResult);
      return ytResult;
    }

    if (lrclibResult.isNotEmpty) {
      await _saveToDisk(cacheKey, cleanKey, lrclibResult);
      return lrclibResult;
    }

    if (ytResult.isNotEmpty) {
      await _saveToDisk(cacheKey, cleanKey, ytResult);
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
    final expectedLang = detectExpectedLanguage(title, artist);

    try {
      String? targetId = videoId;
      if (targetId == null ||
          targetId.isEmpty ||
          targetId.startsWith('trending_')) {
        try {
          final searchResults = await yt.search
              .search('$title $artist lyrics')
              .timeout(const Duration(seconds: 5));
          if (searchResults.isNotEmpty) {
            targetId = searchResults.first.id.value;
          } else {
            final standardResults = await yt.search
                .search('$title $artist')
                .timeout(const Duration(seconds: 5));
            if (standardResults.isNotEmpty) {
              targetId = standardResults.first.id.value;
            }
          }
        } catch (_) {}
      }

      if (targetId == null || targetId.isEmpty) return [];

      ClosedCaptionManifest? manifest;
      try {
        manifest = await yt.videos.closedCaptions
            .getManifest(targetId)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}

      // If manifest is empty on primary video, search lyrics videos
      if (manifest == null || manifest.tracks.isEmpty) {
        try {
          final lyricSearch = await yt.search
              .search('$title $artist lyrics')
              .timeout(const Duration(seconds: 5));

          for (final video in lyricSearch.take(3)) {
            if (video.id.value == targetId) continue;
            try {
              final m = await yt.videos.closedCaptions
                  .getManifest(video.id)
                  .timeout(const Duration(seconds: 4));

              final trackInfo = selectBestCaptionTrack(m.tracks, expectedLang);
              if (trackInfo != null) {
                final sub = await yt.videos.closedCaptions
                    .get(trackInfo)
                    .timeout(const Duration(seconds: 4));

                final lines = sub.captions
                    .map((c) => LyricLine(
                          timestamp: c.offset,
                          text: normalizeLyricText(c.text.replaceAll('\n', ' ')),
                        ))
                    .where((l) => l.text.isNotEmpty)
                    .toList();

                if (_isValidLyrics(lines)) return lines;
              }
            } catch (_) {}
          }
        } catch (_) {}
        return [];
      }

      final trackInfo = selectBestCaptionTrack(manifest.tracks, expectedLang);
      if (trackInfo == null) return [];

      final sub = await yt.videos.closedCaptions
          .get(trackInfo)
          .timeout(const Duration(seconds: 5));

      final lines = sub.captions
          .map((c) => LyricLine(
                timestamp: c.offset,
                text: normalizeLyricText(c.text.replaceAll('\n', ' ')),
              ))
          .where((l) => l.text.isNotEmpty)
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
      }).timeout(const Duration(seconds: 6));

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
                  .map(normalizeLyricText)
                  .where((l) => l.isNotEmpty)
                  .map((line) => LyricLine(timestamp: Duration.zero, text: line))
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
      }).timeout(const Duration(seconds: 6));

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
            .map(normalizeLyricText)
            .where((l) => l.isNotEmpty)
            .map((line) => LyricLine(timestamp: Duration.zero, text: line))
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

  /// Parses synchronized [mm:ss.xx] lines into timestamped objects and normalizes text
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
        final rawText = match.group(4)!.trim();
        final text = normalizeLyricText(rawText);

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
