import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/holo_http_client.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import 'hifi_matcher.dart';
import 'youtube_music_service.dart';

class ArtworkService {
  static const String _storageKey = 'artwork_cache_v5_clean';
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Set<String> _failedKeys = {};
  static final Map<String, String> _cleanCache = {};

  bool _isInitialized = false;
  final YouTubeMusicService _ytmService = YouTubeMusicService();
  Timer? _persistDebounceTimer;

  static const int _maxConcurrent = 2;
  int _activeRequests = 0;
  final List<({Completer<String?> completer, Future<String?> Function() task, bool isPriority})> _queue = [];

  /// Validates whether a thumbnail URL represents a genuine square music album cover
  /// rather than a 16:9 YouTube video thumbnail frame or generic placeholder.
  static bool isSquareAlbumArtworkUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.contains('unsplash.com')) return false;
    if (lower.contains('ytimg.com') || lower.contains('img.youtube.com')) return false;
    return lower.contains('googleusercontent.com') ||
        lower.contains('ggpht.com') ||
        lower.contains('mzstatic.com') ||
        lower.contains('scdn.co') ||
        lower.contains('kuwo.cn') ||
        lower.contains('music.126.net') ||
        lower.contains('qq.com') ||
        lower.contains('dzcdn.net');
  }

  void _processNextQueueItem() {
    if (_activeRequests >= _maxConcurrent || _queue.isEmpty) return;
    _activeRequests++;
    final item = _queue.removeAt(0);
    item.task().then((result) {
      if (!item.completer.isCompleted) {
        item.completer.complete(result);
      }
    }).catchError((err) {
      if (!item.completer.isCompleted) {
        item.completer.complete(null);
      }
    }).whenComplete(() {
      _activeRequests--;
      Future.delayed(const Duration(milliseconds: 60), () {
        _processNextQueueItem();
      });
    });
  }

  Future<String?> _scheduleNetworkFetch(
    Future<String?> Function() task, {
    bool isPriority = false,
  }) {
    final completer = Completer<String?>();
    if (isPriority) {
      _queue.insert(0, (completer: completer, task: task, isPriority: true));
    } else {
      _queue.add((completer: completer, task: task, isPriority: false));
    }
    _processNextQueueItem();
    return completer.future;
  }

  // Pre-compiled regular expressions for 0ms CPU execution
  static final RegExp _parensRegex = RegExp(r'\(.*?\)', caseSensitive: false);
  static final RegExp _bracketsRegex = RegExp(r'\[.*?\]', caseSensitive: false);
  static final RegExp _featRegex =
      RegExp(r'\b(feat|ft|featuring|with|w/)\b.*', caseSensitive: false);
  static final RegExp _topicRegex =
      RegExp(r'\s*-\s*topic$', caseSensitive: false);
  static final RegExp _remasterRegex =
      RegExp(r'remaster(ed)?(\s*\d{4})?', caseSensitive: false);
  static final RegExp _nonAlphaNumSpaceRegex =
      RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _cleanFeatRegex =
      RegExp(r'feat\..*', caseSensitive: false);
  static final RegExp _cleanFtRegex = RegExp(r'ft\..*', caseSensitive: false);
  static final RegExp _cleanWRegex = RegExp(r'w/.*', caseSensitive: false);

  /// Loads cached artworks from local storage
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Purge poisoned legacy caches containing 16:9 ytimg video thumbnails
      await prefs.remove('artwork_cache_v4_yt');
      await prefs.remove('artwork_cache_v3');
      await prefs.remove('artwork_cache_v2');

      final saved = prefs.getString(_storageKey);
      if (saved != null && saved.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(saved);
        decoded.forEach((key, val) {
          if (val is String && val.isNotEmpty && isSquareAlbumArtworkUrl(val)) {
            _cache[key] = val;
          }
        });
      }
    } catch (_) {}
    _isInitialized = true;
  }

  static String cleanForMatching(String text) {
    if (_cleanCache.containsKey(text)) {
      return _cleanCache[text]!;
    }
    final cleaned = text
        .toLowerCase()
        .replaceAll(_parensRegex, '')
        .replaceAll(_bracketsRegex, '')
        .replaceAll(_featRegex, '')
        .replaceAll(_topicRegex, '')
        .replaceAll(_remasterRegex, '')
        .replaceAll(_nonAlphaNumSpaceRegex, '')
        .replaceAll(_multiSpaceRegex, ' ')
        .trim();
    if (_cleanCache.length > 500) {
      _cleanCache.clear();
    }
    _cleanCache[text] = cleaned;
    return cleaned;
  }

  String _cacheKey(String artist, String title) {
    final cleanA = cleanForMatching(artist);
    final cleanT = cleanForMatching(title);
    return '$cleanA - $cleanT';
  }

  /// Returns cached artwork URL synchronously if available
  String? getCached(String artist, String title) {
    final key = _cacheKey(artist, title);
    if (_cache.containsKey(key) && _cache[key]!.isNotEmpty) {
      return _cache[key];
    }
    final rawKey =
        '${artist.toLowerCase().trim()} - ${title.toLowerCase().trim()}';
    return _cache[rawKey];
  }

  /// Resolves high-resolution album cover artwork exclusively via YouTube,
  /// with deduplication of in-flight requests and negative caching for misses.
  Future<String?> getArtwork(
    String artist,
    String title, {
    bool isIndonesian = false,
  }) async {
    final key = _cacheKey(artist, title);
    final rawKey =
        '${artist.toLowerCase().trim()} - ${title.toLowerCase().trim()}';

    if (_cache.containsKey(key) && _cache[key]!.isNotEmpty) {
      return _cache[key];
    }
    if (_cache.containsKey(rawKey) && _cache[rawKey]!.isNotEmpty) {
      return _cache[rawKey];
    }
    if (_failedKeys.contains(key) || _failedKeys.contains(rawKey)) {
      return null;
    }

    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _scheduleNetworkFetch(
      () => _fetchArtworkNetwork(artist, title, key, rawKey),
      isPriority: isIndonesian,
    );
    _inFlight[key] = future;

    try {
      final res = await future;
      return res;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<String?> _fetchArtworkNetwork(
    String artist,
    String title,
    String key,
    String rawKey,
  ) async {
    final cleanTitle = title
        .replaceAll(_parensRegex, '')
        .replaceAll(_bracketsRegex, '')
        .replaceAll(_cleanFeatRegex, '')
        .replaceAll(_cleanFtRegex, '')
        .replaceAll(_cleanWRegex, '')
        .trim();

    final cleanArtist = artist
        .replaceAll(_parensRegex, '')
        .replaceAll(_cleanFeatRegex, '')
        .replaceAll(_cleanFtRegex, '')
        .replaceAll(_cleanWRegex, '')
        .split('/')[0]
        .split('&')[0]
        .trim();

    try {
      final songs = await _ytmService.searchSongs('$cleanArtist $cleanTitle');
      for (final s in songs) {
        final artistMatches =
            HifiMatcher.doesArtistMatch(cleanArtist, s.artist, cleanTitle);
        final titleMatches = HifiMatcher.isTitleAcceptable(cleanTitle, s.title);
        if (artistMatches && titleMatches && isSquareAlbumArtworkUrl(s.thumbnailUrl)) {
          final highRes = Track.toHighResUrl(s.thumbnailUrl);
          _cache[key] = highRes;
          _cache[rawKey] = highRes;
          _debouncePersistCache();
          return highRes;
        }
      }
    } catch (_) {}

    // Fallback: iTunes Search API for guaranteed official square artwork
    try {
      final itunesQuery = Uri.encodeComponent('$cleanArtist $cleanTitle');
      final itunesUri = Uri.parse(
          'https://itunes.apple.com/search?term=$itunesQuery&entity=song&limit=5');
      final res = await HoloHttpClient.client
          .get(itunesUri)
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final decoded =
            jsonDecode(TextEncodingUtils.decodeHttpBytes(res.bodyBytes));
        final results = decoded['results'] as List?;
        if (results != null) {
          for (final r in results) {
            final aName = r['artistName']?.toString() ?? '';
            final tName = r['trackName']?.toString() ?? '';
            final art100 = r['artworkUrl100']?.toString() ?? '';
            if (HifiMatcher.doesArtistMatch(cleanArtist, aName, cleanTitle) &&
                HifiMatcher.isTitleAcceptable(cleanTitle, tName) &&
                art100.isNotEmpty) {
              final art600 = art100.replaceAll('100x100bb.jpg', '600x600bb.jpg');
              _cache[key] = art600;
              _cache[rawKey] = art600;
              _debouncePersistCache();
              return art600;
            }
          }
        }
      }
    } catch (_) {}

    _failedKeys.add(key);
    _failedKeys.add(rawKey);
    return null;
  }

  void _debouncePersistCache() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(seconds: 2), () {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_storageKey, jsonEncode(_cache));
      }).catchError((_) {});
    });
  }
}
