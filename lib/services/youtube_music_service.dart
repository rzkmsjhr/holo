import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';

class YouTubeMusicService {
  static const String _innertubeSearchUrl =
      'https://music.youtube.com/youtubei/v1/search';
  static const String _innertubeNextUrl =
      'https://music.youtube.com/youtubei/v1/next';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _songsParam = 'EgWKAQIIAWoOEAQQAxAFEAkQEBAKEBU%3D';

  static Map<String, String> get _requestHeaders => {
        'Content-Type': 'application/json',
        if (!kIsWeb) ...{
          'User-Agent': _userAgent,
          'Referer': 'https://music.youtube.com/',
          'Origin': 'https://music.youtube.com',
        },
      };

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
            headers: _requestHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) {
        return [];
      }

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
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
            headers: _requestHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) return [];

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
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
                  title: TextEncodingUtils.cleanMojibake(title),
                  artist: TextEncodingUtils.cleanMojibake(
                      artist.isNotEmpty ? artist : 'Various Artists'),
                  thumbnailUrl: Track.toHighResUrl(thumb),
                  durationSeconds: _parseDuration(durStr),
                  youtubeVideoId: vId,
                  audioSource: 'youtube',
                  isLossless: false,
                  extraData: const {'itemType': 'song'},
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
      String itemType = 'song';

      if (flex1 != null && flex1 is List) {
        final List<String> texts = flex1
            .map((r) => r['text']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toList();

        final full = texts.join();
        final parts = full.split(' • ');
        if (parts.isNotEmpty) {
          int artistIdx = 0;
          final first = parts[0].toLowerCase().trim();
          if (first == 'song') {
            itemType = 'song';
            artistIdx = 1;
          } else if (first == 'video') {
            itemType = 'video';
            artistIdx = 1;
          } else if (first == 'single' || first == 'album' || first == 'ep') {
            artistIdx = 1;
          }

          if (parts.length > artistIdx) {
            artist = parts[artistIdx].trim();
          }
        }
        if (parts.length > 1) {
          final last = parts.last.trim();
          durationSecs = _parseDuration(last);
        }
      }

      // Check fixedColumns for explicit duration
      final fixed0 = item['fixedColumns']?[0]
          ?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'];
      if (fixed0 != null && fixed0 is List && fixed0.isNotEmpty) {
        final dStr = fixed0[0]['text']?.toString() ?? '';
        final dSecs = _parseDuration(dStr);
        if (dSecs > 0) {
          durationSecs = dSecs;
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
        title: TextEncodingUtils.cleanMojibake(title),
        artist: TextEncodingUtils.cleanMojibake(artist),
        thumbnailUrl: Track.toHighResUrl(thumbUrl),
        durationSeconds: durationSecs > 0 ? durationSecs : 0,
        youtubeVideoId: videoId,
        audioSource: 'youtube',
        isLossless: false,
        extraData: {'itemType': itemType},
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
