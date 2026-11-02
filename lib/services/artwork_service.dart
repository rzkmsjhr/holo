import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/text_encoding_utils.dart';

class ArtworkService {
  static const String _storageKey = 'artwork_cache_v3';
  static const String _legacyStorageKey = 'artwork_cache_v2';
  final Map<String, String> _cache = {};
  bool _isInitialized = false;

  static const List<String> _derivativeKeywords = [
    'karaoke',
    'originally performed by',
    'backing track',
    'tribute',
    'instrumental',
    'cover by',
    'minus one',
  ];

  /// Loads cached artworks from local storage
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getString(_storageKey) ?? prefs.getString(_legacyStorageKey);
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

  /// Resolves high-resolution album cover artwork via iTunes or Deezer
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
      _cache[rawKey] = itunesArt;
      _persistCache();
      return itunesArt;
    }

    // 3. Try Deezer Search API fallback
    final deezerArt = await _queryDeezer(cleanArtist, cleanTitle);
    if (deezerArt != null && deezerArt.isNotEmpty) {
      _cache[key] = deezerArt;
      _cache[rawKey] = deezerArt;
      _persistCache();
      return deezerArt;
    }

    return null;
  }

  bool _isDerivative(String text) {
    final lower = text.toLowerCase();
    return _derivativeKeywords.any((k) => lower.contains(k));
  }

  Future<String?> _queryItunes(
      String artist, String title, bool isIndonesian) async {
    final query = Uri.encodeComponent('$artist $title');
    final countryParam = isIndonesian ? '&country=id' : '';

    try {
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$query$countryParam&entity=song&limit=5');
      final res = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          for (final item in results) {
            final tName = item['trackName']?.toString() ?? '';
            final aName = item['artistName']?.toString() ?? '';
            final cName = item['collectionName']?.toString() ?? '';
            if (_isDerivative(tName) || _isDerivative(aName) || _isDerivative(cName)) {
              continue;
            }
            final rawArt = item['artworkUrl100'] as String?;
            if (rawArt != null && rawArt.isNotEmpty) {
              return rawArt.replaceAll('100x100bb.jpg', '600x600bb.jpg');
            }
          }
        }
      }
    } catch (_) {}

    // Retry with global if Indonesian search returned nothing clean
    if (isIndonesian) {
      try {
        final url = Uri.parse(
            'https://itunes.apple.com/search?term=$query&entity=song&limit=5');
        final res = await http.get(url, headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        }).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
          final data = jsonDecode(decoded);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            for (final item in results) {
              final tName = item['trackName']?.toString() ?? '';
              final aName = item['artistName']?.toString() ?? '';
              final cName = item['collectionName']?.toString() ?? '';
              if (_isDerivative(tName) || _isDerivative(aName) || _isDerivative(cName)) {
                continue;
              }
              final rawArt = item['artworkUrl100'] as String?;
              if (rawArt != null && rawArt.isNotEmpty) {
                return rawArt.replaceAll('100x100bb.jpg', '600x600bb.jpg');
              }
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
          Uri.parse('https://api.deezer.com/search?q=$query&limit=5');
      final res = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          for (final item in list) {
            final tTitle = item['title']?.toString() ?? '';
            final aName = item['artist']?['name']?.toString() ?? '';
            if (_isDerivative(tTitle) || _isDerivative(aName)) {
              continue;
            }
            final album = item['album'] as Map<String, dynamic>?;
            if (album != null) {
              final xl = album['cover_xl'] as String?;
              final big = album['cover_big'] as String?;
              final med = album['cover_medium'] as String?;
              final result = xl ?? big ?? med;
              if (result != null && result.isNotEmpty) {
                return result;
              }
            }
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
