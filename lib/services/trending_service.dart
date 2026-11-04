import 'package:flutter/foundation.dart';
import '../core/network/holo_http_client.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import '../models/trending_track.dart';
import 'hifi_matcher.dart';
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
      final res = await HoloHttpClient.client.get(
        Uri.parse(url),
        headers: {
          if (!kIsWeb) 'User-Agent': _userAgent,
          'Accept-Language': 'en-US,en;q=0.9,id;q=0.8,ja;q=0.7,ko;q=0.7,ar;q=0.7,th;q=0.7',
          'Accept-Charset': 'utf-8',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final decodedHtml = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final parsed = _parseKworbHtml(decodedHtml, isGlobal);
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
        Track? bestMatch;
        int bestScore = -1;

        for (final cand in searchResults) {
          int score = 0;
          if (HifiMatcher.doesArtistMatch(item.artist, cand.artist, item.title)) {
            score += 50;
          }
          final cClean = HifiMatcher.cleanString(cand.title);
          final tClean = HifiMatcher.cleanString(item.title);
          if (cClean == tClean) {
            score += 100;
          } else if (cClean.contains(tClean) || tClean.contains(cClean)) {
            score += 60;
          }
          if (HifiMatcher.isEligibleTrack(cand)) {
            score += 30;
          }
          if (score > bestScore) {
            bestScore = score;
            bestMatch = cand;
          }
        }

        final match = bestMatch ?? searchResults.first;
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

    // Fallback track (uses item.youtubeVideoId from snapshot if available)
    final fallback = item.toTrack();
    _resolvedCache[cacheKey] = fallback;
    return fallback;
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

        artist = TextEncodingUtils.cleanMojibake(artist);
        title = TextEncodingUtils.cleanMojibake(title);

        final plays = tds[6].replaceAll(tagStrip, '').trim();

        // Match artwork and youtubeVideoId from verified snapshot
        String? thumb;
        String? ytVid;
        for (final s in snapshot) {
          final sA = (s['artist'] as String? ?? '').toLowerCase().trim();
          final sT = (s['title'] as String? ?? '').toLowerCase().trim();
          if ((sA == artist.toLowerCase().trim() && sT == title.toLowerCase().trim()) ||
              (rank == s['rank'] && (sA.contains(artist.toLowerCase()) || artist.toLowerCase().contains(sA)))) {
            thumb = s['thumbnailUrl'] as String?;
            ytVid = s['youtubeVideoId'] as String?;
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
          youtubeVideoId: ytVid,
        ));
      }
    }

    return tracks;
  }
}
