import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/network/holo_http_client.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';

class YouTubeMusicService {
  static const String _innertubeSearchUrl =
      'https://music.youtube.com/youtubei/v1/search';
  static const String _innertubeNextUrl =
      'https://music.youtube.com/youtubei/v1/next';
  static const String _ytWebSearchUrl =
      'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// YouTube Music WEB_REMIX parameter that strictly filters search results to "Songs"
  static const String _songsParam = 'EgWKAQIIAWoOEAQQAxAFEAkQEBAKEBU%3D';

  static Map<String, String> get _requestHeaders => {
        'Content-Type': 'application/json',
        if (!kIsWeb) ...{
          'User-Agent': _userAgent,
          'Referer': 'https://music.youtube.com/',
          'Origin': 'https://music.youtube.com',
        },
      };

  static final Map<String, (DateTime, List<Track>)> _searchCache = {};
  static final Map<String, Future<List<Track>>> _inFlightSearch = {};
  static final Map<String, (DateTime, List<Track>)> _relatedCache = {};
  static final Map<String, Future<List<Track>>> _inFlightRelated = {};

  static final RegExp _wordCharRegex = RegExp(
      r'[a-zA-Z0-9\u00C0-\u024F\u3040-\u30ff\u4e00-\u9faf\uac00-\ud7af]');
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _topicRegex =
      RegExp(r'\s*-\s*topic$', caseSensitive: false);

  static const Set<String> _titleStopwords = {
    'no', 'oh', 'to', 'in', 'on', 'at', 'of', 'me', 'my', 'is', 'it',
    'de', 'na', 'ga', 'ni', 'wa', 'ha', 'a', 'an', 'the',
  };

  static const List<String> _badDerivativePhrases = [
    '歌っちゃ王', '原曲歌手', '原曲キー', 'キー上げ', 'キー下げ',
    'ガイドメロ', 'ガイドなし', 'ガイド音', 'ガイドボーカル',
    'カラオケ', 'karaoke',
    'off vocal', 'offvocal', 'off-vocal', 'without vocal', 'no vocal',
    'backing track', 'minus one',
    '弾いてみた', '歌ってみた', '演奏してみた', '叩いてみた', '弾いてみ', '歌ってみ',
    'bass cover', 'guitar cover', 'drum cover', 'piano cover', 'vocal cover',
    'play along', 'playalong', 'tutorial', 'how to play', 'lesson', 'fingerstyle',
    'amateur cover', 'fan cover',
    'mashup', 'mash-up', 'mash up', 'bootleg',
    'slowed', 'reverb', 'sped up', 'speed up', 'nightcore',
    'instrumental', 'tribute', 'parody',
    'cover by', 'covered by', '(cover)', '[cover]', ' cover',
    'dj ', 'dj.', 'dj-', 'dj_', 'remix', 'rmx', 'koplo', 'hipdut', 'jedag jedug', 'funkot',
    'tiktok', 'tik tok',
    'lirik', 'lyric video', 'lyrics video', 'lirik lagu', 'music box', 'オルゴール', 'orgel',
    'originally performed by', 'original performer', 'megamix', 'kompilasi',
  ];

  /// Helper to clean title of parenthetical notes like (w/ Ade Govinda), [Cover], etc.
  /// Mirrors nadanada's `clean_title_for_matching`.
  static String cleanTitleForMatching(String title) {
    final buf = StringBuffer();
    int depth = 0;
    for (final rune in title.runes) {
      final c = String.fromCharCode(rune);
      if (c == '(' || c == '[' || c == '（' || c == '【') {
        depth++;
      } else if (c == ')' || c == ']' || c == '）' || c == '】') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        if (_wordCharRegex.hasMatch(c)) {
          buf.write(c);
        } else {
          buf.write(' ');
        }
      }
    }
    return buf.toString().toLowerCase().replaceAll(_multiSpaceRegex, ' ').trim();
  }

  static bool _isKaraokeOrDerivative(String title, String channel, String rawQuery) {
    final lowerTitle = title.toLowerCase();
    final lowerChannel = channel.toLowerCase();
    final lowerQuery = rawQuery.toLowerCase();

    if (lowerQuery.contains('karaoke') ||
        lowerQuery.contains('カラオケ') ||
        lowerQuery.contains('instrumental')) {
      return false;
    }

    if (lowerChannel.contains('歌っちゃ王') ||
        lowerChannel.contains('karafun') ||
        lowerChannel.contains('sing king') ||
        lowerChannel.contains('生音風カラオケ') ||
        lowerChannel.contains('カラオケ')) {
      return true;
    }

    for (final bad in _badDerivativePhrases) {
      if ((lowerTitle.contains(bad) || lowerChannel.contains(bad)) &&
          !lowerQuery.contains(bad)) {
        return true;
      }
    }
    return false;
  }

  static bool _artistMatchesQuery(String channel, String title, String rawQuery) {
    final lowerCh = channel.toLowerCase();
    final lowerTitle = title.toLowerCase();
    final lowerQuery = rawQuery.toLowerCase();

    final cleanCh = lowerCh
        .replaceAll('- topic', '')
        .replaceAll('vevo', '')
        .replaceAll('official', '')
        .replaceAll('channel', '')
        .trim();

    final chWords = cleanCh
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_titleStopwords.contains(w))
        .toList();

    for (final sep in [' - ', ' ~ ', ' – ', ' — ']) {
      if (lowerQuery.contains(sep)) {
        final parts = lowerQuery.split(sep);
        final p1 = parts.first.trim();
        final p2 = parts.sublist(1).join(sep).trim();
        if (p1.isNotEmpty &&
            (cleanCh == p1 || cleanCh.contains(p1) || p1.contains(cleanCh))) {
          return true;
        }
        if (p2.isNotEmpty &&
            (cleanCh == p2 || cleanCh.contains(p2) || p2.contains(cleanCh))) {
          return true;
        }
      }
    }

    final queryClean = cleanTitleForMatching(rawQuery);
    final qWords = queryClean
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_titleStopwords.contains(w))
        .toList();
    if (chWords.isNotEmpty && chWords.any((cw) => qWords.contains(cw))) {
      return true;
    }

    if (lowerTitle.contains(' - ')) {
      final prefix = lowerTitle.split(' - ').first.trim();
      final prefixWords = prefix
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3 && !_titleStopwords.contains(w))
          .toList();
      if (prefixWords.isNotEmpty &&
          prefixWords.every((pw) => lowerQuery.contains(pw))) {
        return true;
      }
    }

    return false;
  }

  /// Mirrors nadanada's `score_search_candidate` relevance scoring (lower is better).
  static int scoreSearchCandidate(
      Track track, List<String> queryWords, String rawQuery) {
    final cleanT = cleanTitleForMatching(track.title);
    final channelLower = track.artist.toLowerCase();
    final lowerRawTitle = track.title.toLowerCase();

    int matchedTitleWords = 0;
    int matchedSignificantTitleWords = 0;
    int matchedChannelWords = 0;

    final chWords = channelLower
        .split(RegExp(r'\s+'))
        .where((cw) => cw.length >= 3 && !_titleStopwords.contains(cw))
        .toList();

    for (final w in queryWords) {
      final inClean = cleanT.contains(w);
      final inRaw = lowerRawTitle.contains(w);
      if (inClean || inRaw) {
        matchedTitleWords++;
        if (!_titleStopwords.contains(w) && w.runes.length >= 3) {
          matchedSignificantTitleWords++;
        }
      }
      if (!_titleStopwords.contains(w) && w.runes.length >= 3) {
        if (chWords.any((cw) => cw == w || cw.contains(w) || w.contains(cw))) {
          matchedChannelWords++;
        }
      }
    }

    final isSong = track.extraData?['itemType'] == 'song';
    final artistMatched =
        _artistMatchesQuery(track.artist, track.title, rawQuery) ||
            matchedChannelWords > 0;

    final hasQuerySignificant = queryWords
        .any((w) => !_titleStopwords.contains(w) && w.runes.length >= 3);
    final titleMatched = hasQuerySignificant
        ? matchedSignificantTitleWords > 0
        : matchedTitleWords > 0;

    int score = 0;
    final missing =
        (queryWords.length - (matchedTitleWords + matchedChannelWords))
            .clamp(0, queryWords.length);
    score += missing * 40;

    if (!titleMatched) {
      score += !artistMatched ? 500 : 50;
    }
    if (!artistMatched) {
      score += 500;
    }

    if (track.durationSeconds > 600) {
      score += 1500;
    }

    if (_isKaraokeOrDerivative(track.title, track.artist, rawQuery)) {
      score += 1000;
    }

    if (isSong && titleMatched && artistMatched) {
      score -= 150;
    } else if (!isSong) {
      score += 50;
    }

    return score;
  }

  /// Searches YouTube Music strictly for "song" / "- Topic" tracks matching [query],
  /// mirroring nadanada's `search_youtube(query, Some("song"))`.
  Future<List<Track>> searchSongs(String query) async {
    final cleanQuery = cleanTitleForMatching(query);
    final effectiveQuery =
        ((query.contains('(') || query.contains('[')) && cleanQuery.isNotEmpty)
            ? cleanQuery
            : query.trim();
    if (effectiveQuery.isEmpty) return [];

    final cacheKey = effectiveQuery.toLowerCase();
    final cached = _searchCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2;
    }

    if (_inFlightSearch.containsKey(cacheKey)) {
      return _inFlightSearch[cacheKey]!;
    }

    final future = _executeSearchSongs(effectiveQuery, cleanQuery, query);
    _inFlightSearch[cacheKey] = future;
    try {
      final res = await future;
      _searchCache[cacheKey] = (DateTime.now(), res);
      if (_searchCache.length > 200) {
        _searchCache.remove(_searchCache.keys.first);
      }
      return res;
    } finally {
      _inFlightSearch.remove(cacheKey);
    }
  }

  Future<List<Track>> _executeSearchSongs(
    String effectiveQuery,
    String cleanQuery,
    String originalQuery,
  ) async {
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': effectiveQuery,
      'params': _songsParam,
    };

    try {
      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_innertubeSearchUrl),
            headers: _requestHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final results = _parseYtmResponse(data);
        if (results.isNotEmpty) {
          final queryWords = cleanQuery
              .split(_multiSpaceRegex)
              .where((w) => w.isNotEmpty)
              .toList();
          if (queryWords.length >= 2) {
            results.sort((a, b) => scoreSearchCandidate(
                    a, queryWords, originalQuery)
                .compareTo(
                    scoreSearchCandidate(b, queryWords, originalQuery)));
          }
          return results;
        }
      }
    } catch (_) {}

    // Fallback: Search regular YouTube with "<effectiveQuery> topic" (nadanada fallback)
    return _searchTopicFallback(effectiveQuery);
  }

  /// Fallback search appending " topic" to return "- Topic" song tracks from YouTube
  Future<List<Track>> _searchTopicFallback(String effectiveQuery) async {
    final topicQuery = '$effectiveQuery topic';
    try {
      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_ytWebSearchUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': topicQuery,
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': '2.20250201.00.00',
                  'hl': 'en',
                  'gl': 'US',
                }
              },
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return [];
      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      final List<Track> tracks = [];
      final seen = <String>{};

      final sections = data['contents']?['twoColumnSearchResultsRenderer']
          ?['primaryContents']?['sectionListRenderer']?['contents'];
      if (sections is List) {
        for (final sec in sections) {
          final contents = sec['itemSectionRenderer']?['contents'];
          if (contents is List) {
            for (final item in contents) {
              final video = item['videoRenderer'];
              if (video is Map) {
                final vId = video['videoId']?.toString() ?? '';
                final title =
                    video['title']?['runs']?[0]?['text']?.toString() ?? '';
                final rawChannel =
                    video['ownerText']?['runs']?[0]?['text']?.toString() ?? '';
                final cleanArtist = rawChannel
                    .replaceAll(_topicRegex, '')
                    .trim();
                final durStr =
                    video['lengthText']?['simpleText']?.toString() ?? '';
                final thumbs = video['thumbnail']?['thumbnails'] as List?;
                final thumb = (thumbs != null && thumbs.isNotEmpty)
                    ? thumbs.last['url']?.toString() ?? ''
                    : '';

                if (vId.isNotEmpty && title.isNotEmpty && seen.add(vId)) {
                  tracks.add(Track(
                    id: vId,
                    title: TextEncodingUtils.cleanMojibake(title),
                    artist: TextEncodingUtils.cleanMojibake(
                        cleanArtist.isNotEmpty ? cleanArtist : rawChannel),
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
      }
      return tracks;
    } catch (_) {
      return [];
    }
  }

  /// Fetches Endless Play (Radio Mode) matching tracks from YouTube Music
  Future<List<Track>> getRelatedTracks(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return [];

    final cached = _relatedCache[cleanId];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2;
    }

    if (_inFlightRelated.containsKey(cleanId)) {
      return _inFlightRelated[cleanId]!;
    }

    final future = _executeGetRelatedTracks(cleanId);
    _inFlightRelated[cleanId] = future;
    try {
      final res = await future;
      _relatedCache[cleanId] = (DateTime.now(), res);
      if (_relatedCache.length > 100) {
        _relatedCache.remove(_relatedCache.keys.first);
      }
      return res;
    } finally {
      _inFlightRelated.remove(cleanId);
    }
  }

  Future<List<Track>> _executeGetRelatedTracks(String videoId) async {
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
      final res = await HoloHttpClient.client
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
              final rawArtist =
                  panelItem['longBylineText']?['runs']?[0]?['text']?.toString() ?? '';
              final artist = rawArtist
                  .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
                  .trim();
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

  /// Parses an item from YouTube Music's `musicResponsiveListItemRenderer` into a "song" Track,
  /// mirroring nadanada's `parse_ytm_song_item`.
  Track? _parseListItem(Map<String, dynamic>? item) {
    if (item == null) return null;

    try {
      final videoId = item['playlistItemData']?['videoId'] ??
          item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
              ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['videoId'] ??
          item['flexColumns']?[0]
              ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]
              ?['navigationEndpoint']?['watchEndpoint']?['videoId'];

      if (videoId == null || (videoId as String).isEmpty) return null;

      final flex0 = item['flexColumns']?[0]
              ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] ??
          item['flexColumns']?[0]
              ?['musicResponsiveListItemFlexColumnRenderer']?['title']?['runs'];
      String title = '';
      if (flex0 != null && flex0 is List && flex0.isNotEmpty) {
        title = flex0[0]['text']?.toString() ?? '';
      }
      if (title.isEmpty) return null;

      // Check fixedColumns for explicit duration first (just like nadanada)
      int durationSecs = 0;
      final fixed0 = item['fixedColumns']?[0]
          ?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'];
      if (fixed0 != null && fixed0 is List && fixed0.isNotEmpty) {
        final dStr = fixed0[0]['text']?.toString() ?? '';
        durationSecs = _parseDuration(dStr);
      }

      final flex1 = item['flexColumns']?[1]
              ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] ??
          item['flexColumns']?[1]
              ?['musicResponsiveListItemFlexColumnRenderer']?['title']?['runs'];
      String artist = 'Unknown Artist';
      String album = '';

      if (flex1 != null && flex1 is List) {
        final List<String> texts = flex1
            .map((r) => r['text']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toList();

        final fullMeta = texts.join();
        final parts = fullMeta.split(' • ');

        if (durationSecs == 0 && parts.isNotEmpty) {
          final last = parts.last.trim();
          if (last.contains(':')) {
            durationSecs = _parseDuration(last);
          }
        }

        if (parts.isNotEmpty) {
          final first = parts.first.trim();
          if (first.toLowerCase() == 'song') {
            if (parts.length > 1) artist = parts[1].trim();
            if (parts.length > 2 && !parts[2].contains(':')) {
              album = parts[2].trim();
            }
          } else {
            artist = first;
            if (parts.length > 1 && !parts[1].contains(':')) {
              album = parts[1].trim();
            }
          }
        }
      }

      // Check flexColumns[2] if album wasn't found in flex1
      if (album.isEmpty && (item['flexColumns'] as List?) != null && (item['flexColumns'] as List).length > 2) {
        final flex2 = item['flexColumns']?[2]
            ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (flex2 is List && flex2.isNotEmpty) {
          final aText = flex2[0]?['text']?.toString() ?? '';
          if (aText.isNotEmpty && !aText.contains(':')) {
            album = aText.trim();
          }
        }
      }

      artist = artist
          .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
          .trim();

      final thumbs = item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']
          ?['thumbnails'];
      String thumbUrl = '';
      if (thumbs != null && thumbs is List && thumbs.isNotEmpty) {
        thumbUrl =
            (thumbs.last['url'] ?? thumbs.first['url'])?.toString() ?? '';
      }

      return Track(
        id: videoId,
        title: TextEncodingUtils.cleanMojibake(title),
        artist: TextEncodingUtils.cleanMojibake(artist),
        album: TextEncodingUtils.cleanMojibake(album),
        thumbnailUrl: Track.toHighResUrl(thumbUrl),
        durationSeconds: durationSecs > 0 ? durationSecs : 0,
        youtubeVideoId: videoId,
        audioSource: 'youtube',
        isLossless: false,
        extraData: const {'itemType': 'song'},
      );
    } catch (_) {
      return null;
    }
  }

  int _parseDuration(String timeStr) {
    final parts =
        timeStr.trim().split(':').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length == 2) {
      return parts[0] * 60 + parts[1];
    } else if (parts.length == 3) {
      return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    return 0;
  }
}
