import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

class YouTubeMusicService {
  static const String _innertubeSearchUrl =
      'https://music.youtube.com/youtubei/v1/search';
  static const String _innertubeNextUrl =
      'https://music.youtube.com/youtubei/v1/next';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _songsParam = 'EgWKAQIIAWoOEAQQAxAFEAkQEBAKEBU%3D';

  /// Searches YouTube Music for songs matching the query
  Future<List<Track>> searchSongs(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': cleanQuery,
      'params': _songsParam,
    };

    try {
      final res = await http
          .post(
            Uri.parse(_innertubeSearchUrl),
            headers: {
              'User-Agent': _userAgent,
              'Content-Type': 'application/json',
              'Referer': 'https://music.youtube.com/',
              'Origin': 'https://music.youtube.com',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(res.body);
      return _parseYtmResponse(data);
    } catch (_) {
      return [];
    }
  }

  /// Fetches Endless Play (Radio Mode) matching tracks from YouTube Music
  Future<List<Track>> getRelatedTracks(String videoId) async {
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'videoId': videoId,
      'playlistId': 'RDAMVM$videoId',
      'isAudioOnly': true,
    };

    try {
      final res = await http
          .post(
            Uri.parse(_innertubeNextUrl),
            headers: {
              'User-Agent': _userAgent,
              'Content-Type': 'application/json',
              'Referer': 'https://music.youtube.com/',
              'Origin': 'https://music.youtube.com',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      final List<Track> tracks = [];

      final tabs = data['contents']?['singleColumnMusicWatchNextResultsRenderer']
          ?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs'];

      if (tabs != null && tabs is List && tabs.isNotEmpty) {
        final contents = tabs[0]?['tabRenderer']?['content']
            ?['musicQueueRenderer']?['content']?['playlistPanelRenderer']
            ?['contents'];

        if (contents != null && contents is List) {
          for (final item in contents) {
            final panelItem = item['playlistPanelVideoRenderer'];
            if (panelItem != null) {
              final vId = panelItem['videoId']?.toString() ?? '';
              final title = panelItem['title']?['runs']?[0]?['text']?.toString() ?? '';
              final artist = panelItem['longBylineText']?['runs']?[0]?['text']?.toString() ?? '';
              final durStr = panelItem['lengthText']?['runs']?[0]?['text']?.toString() ?? '';
              final thumbs = panelItem['thumbnail']?['thumbnails'] as List?;
              final thumb = (thumbs != null && thumbs.isNotEmpty)
                  ? thumbs.last['url']?.toString() ?? ''
                  : '';

              if (vId.isNotEmpty && title.isNotEmpty && vId != videoId) {
                tracks.add(Track(
                  id: vId,
                  title: title,
                  artist: artist.isNotEmpty ? artist : 'Various Artists',
                  thumbnailUrl: Track.toHighResUrl(thumb),
                  durationSeconds: _parseDuration(durStr),
                  youtubeVideoId: vId,
                  audioSource: 'youtube',
                  isLossless: false,
                ));
              }
            }
          }
        }
      }

      return tracks;
    } catch (_) {
      return [];
    }
  }

  List<Track> _parseYtmResponse(Map<String, dynamic> data) {
    final List<Track> tracks = [];

    try {
      final sectionList = data['contents']?['tabbedSearchResultsRenderer']
              ?['tabs']?[0]?['tabRenderer']?['content']
          ?['sectionListRenderer']?['contents'];

      if (sectionList == null || sectionList is! List) return tracks;

      for (final section in sectionList) {
        final items = section['musicShelfRenderer']?['contents'];
        if (items != null && items is List) {
          for (final item in items) {
            final track = _parseListItem(item['musicResponsiveListItemRenderer']);
            if (track != null) {
              tracks.add(track);
            }
          }
        }
      }
    } catch (_) {}

    return tracks;
  }

  Track? _parseListItem(Map<String, dynamic>? item) {
    if (item == null) return null;

    try {
      final videoId = item['playlistItemData']?['videoId'] ??
          item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
              ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['videoId'];

      if (videoId == null || (videoId as String).isEmpty) return null;

      final flex0 = item['flexColumns']?[0]
          ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      String title = '';
      if (flex0 != null && flex0 is List && flex0.isNotEmpty) {
        title = flex0[0]['text'] ?? '';
      }
      if (title.isEmpty) return null;

      final flex1 = item['flexColumns']?[1]
          ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      String artist = 'Unknown Artist';
      int durationSecs = 0;

      if (flex1 != null && flex1 is List) {
        final List<String> texts = flex1
            .map((r) => r['text']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toList();

        final full = texts.join();
        final parts = full.split(' • ');
        if (parts.isNotEmpty) {
          artist = parts[0].trim();
        }
        if (parts.length > 1) {
          final last = parts.last.trim();
          durationSecs = _parseDuration(last);
        }
      }

      final thumbs = item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']
          ?['thumbnails'];
      String thumbUrl = '';
      if (thumbs != null && thumbs is List && thumbs.isNotEmpty) {
        thumbUrl = thumbs.last['url'] ?? '';
      }

      return Track(
        id: videoId,
        title: title,
        artist: artist,
        thumbnailUrl: Track.toHighResUrl(thumbUrl),
        durationSeconds: durationSecs > 0 ? durationSecs : 210,
        youtubeVideoId: videoId,
        audioSource: 'youtube',
        isLossless: false,
      );
    } catch (_) {
      return null;
    }
  }

  int _parseDuration(String timeStr) {
    final parts = timeStr.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length == 2) {
      return parts[0] * 60 + parts[1];
    } else if (parts.length == 3) {
      return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    return 0;
  }
}
