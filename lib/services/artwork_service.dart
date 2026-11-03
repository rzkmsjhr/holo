import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'youtube_music_service.dart';

class ArtworkService {
  static const String _storageKey = 'artwork_cache_v4_yt';
  static const String _legacyStorageKey = 'artwork_cache_v2';
  final Map<String, String> _cache = {};
  bool _isInitialized = false;
  final YouTubeMusicService _ytmService = YouTubeMusicService();

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
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'\b(feat|ft|featuring|with|w/)\b.*', caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s*-\s*topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'remaster(ed)?(\s*\d{4})?', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
    final rawKey = '${artist.toLowerCase().trim()} - ${title.toLowerCase().trim()}';
    return _cache[rawKey];
  }

  /// Resolves high-resolution album cover artwork exclusively via YouTube
  Future<String?> getArtwork(
    String artist,
    String title, {
    bool isIndonesian = false,
  }) async {
    final key = _cacheKey(artist, title);
    final rawKey = '${artist.toLowerCase().trim()} - ${title.toLowerCase().trim()}';
    if (_cache.containsKey(key) && _cache[key]!.isNotEmpty) {
      return _cache[key];
    }
    if (_cache.containsKey(rawKey) && _cache[rawKey]!.isNotEmpty) {
      return _cache[rawKey];
    }

    final cleanTitle = title
        .replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'feat\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'ft\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'w/.*', caseSensitive: false), '')
        .trim();

    final cleanArtist = artist
        .replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'feat\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'ft\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'w/.*', caseSensitive: false), '')
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
          _persistCache();
          return highRes;
        }
      }
    } catch (_) {}

    return null;
  }

  void _persistCache() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_storageKey, jsonEncode(_cache));
    }).catchError((_) {});
  }
}
