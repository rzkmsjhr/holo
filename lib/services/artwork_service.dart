import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'youtube_music_service.dart';

class ArtworkService {
  static const String _storageKey = 'artwork_cache_v4_yt';
  static const String _legacyStorageKey = 'artwork_cache_v2';
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Set<String> _failedKeys = {};
  static final Map<String, String> _cleanCache = {};

  bool _isInitialized = false;
  final YouTubeMusicService _ytmService = YouTubeMusicService();
  Timer? _persistDebounceTimer;

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
      final saved = prefs.getString(_storageKey) ??
          prefs.getString('artwork_cache_v3') ??
          prefs.getString(_legacyStorageKey);
      if (saved != null && saved.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(saved);
        decoded.forEach((key, val) {
          if (val is String && val.isNotEmpty) {
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

    final future = _fetchArtworkNetwork(artist, title, key, rawKey);
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
      if (songs.isNotEmpty) {
        final ytArt = songs.first.thumbnailUrl;
        if (ytArt.isNotEmpty) {
          final highRes = Track.toHighResUrl(ytArt);
          _cache[key] = highRes;
          _cache[rawKey] = highRes;
          _debouncePersistCache();
          return highRes;
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
