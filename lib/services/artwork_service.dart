import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/text_encoding_utils.dart';

class ArtworkService {
  static const String _storageKey = 'artwork_cache_v2';
  final Map<String, String> _cache = {};
  bool _isInitialized = false;

  /// Loads cached artworks from local storage
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
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

  String _cacheKey(String artist, String title) {
    final cleanA = artist.toLowerCase().trim();
    final cleanT = title.toLowerCase().trim();
    return '$cleanA - $cleanT';
  }

  /// Returns cached artwork URL synchronously if available
  String? getCached(String artist, String title) {
    return _cache[_cacheKey(artist, title)];
  }

  /// Resolves high-resolution album cover artwork via iTunes or Deezer
  Future<String?> getArtwork(
    String artist,
    String title, {
    bool isIndonesian = false,
  }) async {
    final key = _cacheKey(artist, title);
    if (_cache.containsKey(key) && _cache[key]!.isNotEmpty) {
      return _cache[key];
    }

    // 1. Clean query strings
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

    // 2. Try iTunes Search API
    final itunesArt = await _queryItunes(cleanArtist, cleanTitle, isIndonesian);
    if (itunesArt != null && itunesArt.isNotEmpty) {
      _cache[key] = itunesArt;
      _persistCache();
      return itunesArt;
    }

    // 3. Try Deezer Search API fallback
    final deezerArt = await _queryDeezer(cleanArtist, cleanTitle);
    if (deezerArt != null && deezerArt.isNotEmpty) {
      _cache[key] = deezerArt;
      _persistCache();
      return deezerArt;
    }

    return null;
  }

  Future<String?> _queryItunes(
      String artist, String title, bool isIndonesian) async {
    final query = Uri.encodeComponent('$artist $title');
    final countryParam = isIndonesian ? '&country=id' : '';

    try {
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$query$countryParam&entity=song&limit=1');
      final res = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final rawArt = results[0]['artworkUrl100'] as String?;
          if (rawArt != null && rawArt.isNotEmpty) {
            return rawArt.replaceAll('100x100bb.jpg', '600x600bb.jpg');
          }
        }
      }
    } catch (_) {}

    // Retry with opposite country setting if first attempt had no match
    if (isIndonesian) {
      try {
        final url = Uri.parse(
            'https://itunes.apple.com/search?term=$query&entity=song&limit=1');
        final res = await http.get(url, headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        }).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
          final data = jsonDecode(decoded);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final rawArt = results[0]['artworkUrl100'] as String?;
            if (rawArt != null && rawArt.isNotEmpty) {
              return rawArt.replaceAll('100x100bb.jpg', '600x600bb.jpg');
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String?> _queryDeezer(String artist, String title) async {
    try {
      final query = Uri.encodeComponent('$artist $title');
      final url =
          Uri.parse('https://api.deezer.com/search?q=$query&limit=1');
      final res = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          final album = list[0]['album'] as Map<String, dynamic>?;
          if (album != null) {
            final xl = album['cover_xl'] as String?;
            final big = album['cover_big'] as String?;
            final med = album['cover_medium'] as String?;
            return xl ?? big ?? med;
          }
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
