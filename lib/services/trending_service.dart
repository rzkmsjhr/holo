import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/trending_track.dart';
import 'kworb_data_snapshot.dart';
import 'youtube_music_service.dart';

class TrendingService {
  final YouTubeMusicService _ytmService;

  static const String _globalUrl =
      'https://kworb.net/spotify/country/global_daily.html';
  static const String _idUrl =
      'https://kworb.net/spotify/country/id_daily.html';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // In-memory cache of resolved YouTube tracks for fast replay
  final Map<String, Track> _resolvedCache = {};

  TrendingService({YouTubeMusicService? ytmService})
      : _ytmService = ytmService ?? YouTubeMusicService();

  /// Fetches top 50 trending songs for either 'global' or 'indonesia'
  Future<List<TrendingTrack>> getTrending(String region) async {
    final isGlobal = region.toLowerCase() != 'indonesia' && region.toLowerCase() != 'id';
    final url = isGlobal ? _globalUrl : _idUrl;

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _userAgent,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final parsed = _parseKworbHtml(res.body, isGlobal);
        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
    } catch (_) {}

    // Fallback to real Kworb snapshot if network request fails or has CORS restrictions
    final snapshot = isGlobal ? kGlobalTop50Snapshot : kIndonesiaTop50Snapshot;
    return snapshot.map(TrendingTrack.fromMap).toList();
  }

  /// Resolves a TrendingTrack to a playable Track with YouTube stream & album artwork
  Future<Track?> resolveTrack(TrendingTrack item) async {
    final cacheKey = '${item.artist} - ${item.title}'.toLowerCase();
    if (_resolvedCache.containsKey(cacheKey)) {
      return _resolvedCache[cacheKey];
    }

    try {
      final query = '${item.artist} ${item.title}';
      final searchResults = await _ytmService.searchSongs(query);

      if (searchResults.isNotEmpty) {
        // Pick best matching track
        final match = searchResults.firstWhere(
          (t) => _matchesArtistOrTitle(t, item.artist, item.title),
          orElse: () => searchResults.first,
        );

        final resolved = match.copyWith(
          title: item.title,
          artist: item.artist,
          thumbnailUrl: match.thumbnailUrl.isNotEmpty
              ? match.thumbnailUrl
              : (item.thumbnailUrl ?? ''),
        );

        _resolvedCache[cacheKey] = resolved;
        return resolved;
      }
    } catch (_) {}

    // Fallback placeholder track
    final fallback = item.toTrack();
    _resolvedCache[cacheKey] = fallback;
    return fallback;
  }

  bool _matchesArtistOrTitle(Track cand, String targetArtist, String targetTitle) {
    final cArtist = cand.artist.toLowerCase();
    final cTitle = cand.title.toLowerCase();
    final tArtist = targetArtist.toLowerCase();
    final tTitle = targetTitle.toLowerCase();

    final artistMatch = cArtist.contains(tArtist) || tArtist.contains(cArtist);
    final titleMatch = cTitle.contains(tTitle) || tTitle.contains(cTitle);
    return artistMatch || titleMatch;
  }

  List<TrendingTrack> _parseKworbHtml(String html, bool isGlobal) {
    final rowsRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
    final tdRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
    final tagStrip = RegExp(r'<[^>]+>');

    final snapshot = isGlobal ? kGlobalTop50Snapshot : kIndonesiaTop50Snapshot;
    final List<TrendingTrack> tracks = [];

    for (final rowMatch in rowsRegex.allMatches(html)) {
      final rowHtml = rowMatch.group(1) ?? '';
      final tds = tdRegex.allMatches(rowHtml).map((m) => m.group(1) ?? '').toList();

      if (tds.length >= 7) {
        final rankStr = tds[0].replaceAll(tagStrip, '').trim();
        final rank = int.tryParse(rankStr);
        if (rank == null) continue;
        if (rank > 50) break;

        final trend = tds[1].replaceAll(tagStrip, '').trim();
        var fullTitle = tds[2].replaceAll(tagStrip, '').trim();
        fullTitle = fullTitle.replaceAll(RegExp(r'\s+'), ' ');

        String artist = 'Various Artists';
        String title = fullTitle;
        if (fullTitle.contains(' - ')) {
          final parts = fullTitle.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        final plays = tds[6].replaceAll(tagStrip, '').trim();

        // Match artwork from verified snapshot
        String? thumb;
        for (final s in snapshot) {
          final sA = (s['artist'] as String? ?? '').toLowerCase().trim();
          final sT = (s['title'] as String? ?? '').toLowerCase().trim();
          if ((sA == artist.toLowerCase().trim() && sT == title.toLowerCase().trim()) ||
              (rank == s['rank'] && (sA.contains(artist.toLowerCase()) || artist.toLowerCase().contains(sA)))) {
            thumb = s['thumbnailUrl'] as String?;
            break;
          }
        }

        tracks.add(TrendingTrack(
          rank: rank,
          trend: trend.isNotEmpty ? trend : '=',
          artist: artist,
          title: title,
          plays: plays,
          query: '$artist - $title',
          thumbnailUrl: thumb,
        ));
      }
    }

    return tracks;
  }
}
