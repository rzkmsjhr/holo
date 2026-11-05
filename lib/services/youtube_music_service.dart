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
    'カラオケ', 'karaoke', 'karoke',
    'off vocal', 'offvocal', 'off-vocal', 'without vocal', 'no vocal', 'tanpa vokal',
    'backing track', 'minus one', 'minus 1', 'minus-one', '-1', 'instrumen',
    '纯音乐', '伴奏', '原版伴奏', '伴唱', '消音',
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

  static bool isKaraokeOrDerivative(String title, String channel, String rawQuery) {
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

    final keyShiftRegex = RegExp(
        r'[+-]\s*\d+\s*(?:key|キー)|(?:key|キー)\s*[+-]\s*\d+',
        caseSensitive: false);
    if (keyShiftRegex.hasMatch(lowerTitle)) {
      return true;
    }

    return false;
  }

  /// Checks if a record represents a video, music video, lyric video, or visualizer
  static bool isVideoRecord(String title, String channel) {
    final lowerTitle = title.toLowerCase();
    final lowerChannel = channel.toLowerCase();
    return lowerTitle.contains('official music video') ||
        lowerTitle.contains('official video') ||
        lowerTitle.contains('music video') ||
        lowerTitle.contains('official hd video') ||
        lowerTitle.contains('lyric video') ||
        lowerTitle.contains('lyrics video') ||
        lowerTitle.contains('visualizer') ||
        lowerTitle.contains('[mv]') ||
        lowerTitle.contains('(mv)') ||
        lowerTitle.contains('live performance') ||
        lowerChannel.contains('vevo');
  }

  /// Checks whether a string contains CJK characters (Hiragana, Katakana, Kanji, Hangul)
  static bool hasCjk(String s) {
    for (final rune in s.runes) {
      if ((rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0x4e00 && rune <= 0x9faf) ||
          (rune >= 0xac00 && rune <= 0xd7af)) {
        return true;
      }
    }
    return false;
  }

  /// Converts Katakana string to Romaji for cross-script title matching,
  /// mirroring nadanada's `katakana_to_romaji`.
  static String katakanaToRomaji(String s) {
    final out = StringBuffer();
    final chars = s.runes.map(String.fromCharCode).toList();
    int i = 0;
    while (i < chars.length) {
      final c = chars[i];
      final next = (i + 1 < chars.length) ? chars[i + 1] : null;

      String? combo;
      int advance = 1;

      if (c == 'シ') {
        if (next == 'ャ') { combo = 'sha'; advance = 2; }
        else if (next == 'ュ') { combo = 'shu'; advance = 2; }
        else if (next == 'ョ') { combo = 'sho'; advance = 2; }
        else if (next == 'ェ') { combo = 'she'; advance = 2; }
      } else if (c == 'チ') {
        if (next == 'ャ') { combo = 'cha'; advance = 2; }
        else if (next == 'ュ') { combo = 'chu'; advance = 2; }
        else if (next == 'ョ') { combo = 'cho'; advance = 2; }
        else if (next == 'ェ') { combo = 'che'; advance = 2; }
      } else if (c == 'ジ') {
        if (next == 'ャ') { combo = 'ja'; advance = 2; }
        else if (next == 'ュ') { combo = 'ju'; advance = 2; }
        else if (next == 'ョ') { combo = 'jo'; advance = 2; }
        else if (next == 'ェ') { combo = 'je'; advance = 2; }
      } else if (c == 'フ') {
        if (next == 'ァ') { combo = 'fa'; advance = 2; }
        else if (next == 'ィ') { combo = 'fi'; advance = 2; }
        else if (next == 'ェ') { combo = 'fe'; advance = 2; }
        else if (next == 'ォ') { combo = 'fo'; advance = 2; }
      } else if (c == 'テ' && next == 'ィ') {
        combo = 'ti'; advance = 2;
      } else if (c == 'デ' && next == 'ィ') {
        combo = 'di'; advance = 2;
      } else if (c == 'ッ' && next != null) {
        final nextRune = next.runes.first;
        if (nextRune >= 0x30a1 && nextRune <= 0x30f6) {
          i += 1;
          continue;
        }
      }

      if (combo != null) {
        out.write(combo);
        i += advance;
        continue;
      }

      const singleMap = {
        'ア': 'a', 'ァ': 'a', 'イ': 'i', 'ィ': 'i', 'ウ': 'u', 'ゥ': 'u', 'エ': 'e', 'ェ': 'e', 'オ': 'o', 'ォ': 'o',
        'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
        'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
        'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
        'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
        'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ホ': 'ho',
        'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
        'ヤ': 'ya', 'ャ': 'ya', 'ユ': 'yu', 'ュ': 'yu', 'ヨ': 'yo', 'ョ': 'yo',
        'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
        'ワ': 'wa', 'ヲ': 'o', 'ン': 'n',
        'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
        'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
        'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
        'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'ベ': 'be', 'ボ': 'bo',
        'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ポ': 'po',
        'ヴ': 'vu', 'ー': '', '・': ' ',
      };

      if (singleMap.containsKey(c)) {
        out.write(singleMap[c]);
      } else {
        out.write(c);
      }
      i += 1;
    }
    return out.toString();
  }

  static const List<List<String>> japaneseArtistPairs = [
    ['mariya takeuchi', '竹内まりや'],
    ['takeuchi mariya', '竹内まりや'],
    ['reiko takahashi', '高橋玲子'],
    ['takahashi reiko', '高橋玲子'],
    ['noriyuki makihara', '槇原敬之'],
    ['makihara noriyuki', '槇原敬之'],
    ['tatsuro yamashita', '山下達郎'],
    ['yamashita tatsuro', '山下達郎'],
    ['miki matsubara', '松原みき'],
    ['matsubara miki', '松原みき'],
    ['taeko onuki', '大貫妙子'],
    ['onuki taeko', '大貫妙子'],
    ['anri', '杏里'],
    ['akina nakamori', '中森明菜'],
    ['nakamori akina', '中森明菜'],
    ['seiko matsuda', '松田聖子'],
    ['matsuda seiko', '松田聖子'],
    ['junko yagami', '八神純子'],
    ['yagami junko', '八神純子'],
    ['tomoko aran', '亜蘭知子'],
    ['aran tomoko', '亜蘭知子'],
    ['meiko nakahara', '中原めいこ'],
    ['nakahara meiko', '中原めいこ'],
    ['masayoshi takanaka', '高中正義'],
    ['takanaka masayoshi', '高中正義'],
  ];

  static const List<List<String>> japaneseTitlePairs = [
    ['シングル アゲイン', 'single again'],
    ['シングルアゲイン', 'single again'],
    ['プラスティック ラブ', 'plastic love'],
    ['プラスチック ラブ', 'plastic love'],
    ['サンセット ロード', 'sunset road'],
    ['ステイ ウィズ ミー', 'stay with me'],
    ['フライディ チャイナタウン', 'fly day chinatown'],
    ['フライデー チャイナタウン', 'friday chinatown'],
    ['真夜中のドア', 'stay with me'],
    ['もう恋なんてしない', 'mo koi nante shinai'],
    ['元気を出して', 'genki wo dashite'],
    ['元気を出して', 'genki o dashite'],
    ['縁の糸', 'enishi no ito'],
  ];

  /// Matches a candidate title against a query term, handling cross-script Katakana/English
  static bool titleMatchesTerm(String cleanTitle, String term) {
    if (cleanTitle.contains(term)) return true;
    if (hasCjk(term)) {
      final romaji = katakanaToRomaji(term);
      final cleanRomaji = romaji.replaceAll(' ', '');
      final cleanCand = cleanTitle.replaceAll(' ', '');
      if (cleanRomaji.isNotEmpty && cleanCand.contains(cleanRomaji)) {
        return true;
      }
      for (final pair in japaneseTitlePairs) {
        final jp = pair[0].replaceAll(' ', '');
        final en = pair[1];
        if (term.contains(jp) && cleanTitle.contains(en)) return true;
      }
      if ((term.contains('シングル') && cleanTitle.contains('single')) ||
          (term.contains('アゲイン') && cleanTitle.contains('again')) ||
          ((term.contains('プラスティック') || term.contains('プラスチック')) && cleanTitle.contains('plastic')) ||
          (term.contains('ラブ') && cleanTitle.contains('love')) ||
          (term.contains('サンセット') && cleanTitle.contains('sunset')) ||
          (term.contains('ロード') && cleanTitle.contains('road'))) {
        return true;
      }
    }
    if (term == 'single' && cleanTitle.contains('シングル')) return true;
    if (term == 'again' && cleanTitle.contains('アゲイン')) return true;
    if (term == 'plastic' && (cleanTitle.contains('プラスティック') || cleanTitle.contains('プラスチック'))) return true;
    if (term == 'love' && cleanTitle.contains('ラブ')) return true;
    if (term == 'sunset' && cleanTitle.contains('サンセット')) return true;
    if (term == 'road' && cleanTitle.contains('ロード')) return true;
    return false;
  }

  static bool _artistMatchesQuery(String channel, String title, String rawQuery) {
    final lowerCh = channel.toLowerCase();
    final lowerTitle = title.toLowerCase();
    final lowerQuery = rawQuery.toLowerCase();

    // 1. Cross-script Japanese/Latin pairs
    for (final pair in japaneseArtistPairs) {
      final latin = pair[0];
      final kanji = pair[1];
      if (lowerQuery.contains(latin) || lowerQuery.contains(kanji)) {
        if (lowerCh.contains(latin) || lowerCh.contains(kanji) ||
            lowerTitle.startsWith(latin) || lowerTitle.startsWith(kanji)) {
          return true;
        }
      }
    }

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
      final inClean = titleMatchesTerm(cleanT, w);
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

    // Check if title has "OtherArtist ft. TargetArtist" format (e.g. "2Pac ft. Mariya Takeuchi")
    bool isFtLeadMismatch = false;
    if (lowerRawTitle.contains(' - ')) {
      final prefix = lowerRawTitle.split(' - ').first;
      if (prefix.contains(' ft. ') ||
          prefix.contains(' ft ') ||
          prefix.contains(' feat. ') ||
          prefix.contains(' feat ')) {
        final ftSplit = prefix.split(' ft')[0].split(' feat')[0];
        if (!queryWords.any((w) => ftSplit.contains(w))) {
          isFtLeadMismatch = true;
        }
      }
    }
    if (isFtLeadMismatch) {
      score += 400;
    }

    if (track.durationSeconds > 600) {
      score += 1500;
    }

    if (isKaraokeOrDerivative(track.title, track.artist, rawQuery)) {
      score += 1000;
    }

    final mvt = track.extraData?['musicVideoType']?.toString() ?? '';
    final isTopic = track.artist.toLowerCase().endsWith('- topic') ||
        mvt == 'MUSIC_VIDEO_TYPE_ATV';
    if (isTopic) {
      score -= 200;
    } else if (mvt == 'MUSIC_VIDEO_TYPE_OMV' || mvt == 'MUSIC_VIDEO_TYPE_UGC') {
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
        // Strictly retain songs only, never mix in videos or karaoke derivatives
        results.removeWhere((t) =>
            t.extraData?['itemType'] != 'song' ||
            isVideoRecord(t.title, t.artist) ||
            isKaraokeOrDerivative(t.title, t.artist, effectiveQuery));
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

  /// Searches YouTube Web for video records, mirroring nadanada's `search_youtube(query, Some("video"))`.
  Future<List<Track>> searchVideos(String query) async {
    final cleanQuery = cleanTitleForMatching(query);
    if (cleanQuery.isEmpty) return [];

    try {
      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_ytWebSearchUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': query,
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
          .timeout(const Duration(seconds: 7));

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
                final cleanArtist =
                    rawChannel.replaceAll(_topicRegex, '').trim();
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
                    extraData: const {'itemType': 'video'},
                  ));
                }
              }
              if (tracks.length >= 20) break;
            }
          }
        }
      }
      return tracks;
    } catch (_) {
      return [];
    }
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

                final isTopic = rawChannel.toLowerCase().endsWith('- topic');
                final isVideo = isVideoRecord(title, rawChannel);
                final isKaraoke =
                    isKaraokeOrDerivative(title, rawChannel, effectiveQuery);
                final artistMatches =
                    _artistMatchesQuery(rawChannel, title, effectiveQuery);

                if (vId.isNotEmpty &&
                    title.isNotEmpty &&
                    !isVideo &&
                    !isKaraoke &&
                    (isTopic || artistMatches) &&
                    seen.add(vId)) {
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
      if (tracks.isNotEmpty) {
        final cleanQ = cleanTitleForMatching(effectiveQuery);
        final queryWords = cleanQ.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (queryWords.length >= 2) {
          tracks.sort((a, b) => scoreSearchCandidate(a, queryWords, effectiveQuery)
              .compareTo(scoreSearchCandidate(b, queryWords, effectiveQuery)));
        }
      }
      return tracks;
    } catch (_) {
      return [];
    }
  }

  /// Helper function to space out tracks by the same artist (at least 7 tracks apart),
  /// mirroring nadanada's space_out_artist_tracks.
  static List<Track> spaceOutArtistTracks(List<Track> tracks) {
    if (tracks.isEmpty) return const [];
    final spaced = <Track>[];
    final pending = List<Track>.from(tracks);

    spaced.add(pending.removeAt(0));

    (String, String) getArtistInfo(Track t) {
      final title = t.title.toLowerCase();
      final channel = t.artist
          .toLowerCase()
          .replaceAll(' - topic', '')
          .replaceAll('vevo', '')
          .replaceAll('official', '')
          .trim();
      String titleArtist = '';
      if (title.contains(' - ')) {
        titleArtist = title.split(' - ')[0].trim();
      } else if (title.contains(' ~ ')) {
        titleArtist = title.split(' ~ ')[0].trim();
      }
      return (titleArtist, channel);
    }

    String clean(String s) =>
        s.replaceAll(RegExp(r'[^a-zA-Z0-9\u3040-\u30ff\u4e00-\u9faf]'), '').toLowerCase();

    bool checkPair(String a, String b) {
      if (a.isEmpty || b.isEmpty) return false;
      if (a == b) return true;
      if (a.length > 3 && b.length > 3 && (a.contains(b) || b.contains(a))) return true;
      return false;
    }

    bool isSameArtistInfo((String, String) a1, (String, String) a2) {
      final ta1C = clean(a1.$1);
      final ch1C = clean(a1.$2);
      final ta2C = clean(a2.$1);
      final ch2C = clean(a2.$2);

      return checkPair(ta1C, ta2C) ||
          checkPair(ch1C, ch2C) ||
          checkPair(ta1C, ch2C) ||
          checkPair(ch1C, ta2C);
    }

    while (pending.isNotEmpty) {
      int foundIndex = 0;

      for (int i = 0; i < pending.length; i++) {
        final currentArtist = getArtistInfo(pending[i]);
        bool recentConflict = false;

        final checkLen = spaced.length < 7 ? spaced.length : 7;
        for (int r = spaced.length - 1; r >= spaced.length - checkLen; r--) {
          final recentArtist = getArtistInfo(spaced[r]);
          if (isSameArtistInfo(currentArtist, recentArtist)) {
            recentConflict = true;
            break;
          }
        }

        if (!recentConflict) {
          foundIndex = i;
          break;
        }
      }

      spaced.add(pending.removeAt(foundIndex));
    }

    return spaced;
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

              final musicVideoType = panelItem['navigationEndpoint']?['watchEndpoint']
                      ?['watchEndpointMusicSupportedConfigs']
                      ?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
                  panelItem['playNavigationEndpoint']?['watchEndpoint']
                      ?['watchEndpointMusicSupportedConfigs']
                      ?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
                  '';

              final isTopic = rawArtist.toLowerCase().endsWith('- topic') ||
                  musicVideoType == 'MUSIC_VIDEO_TYPE_ATV';
              final isExplicitOmv = musicVideoType == 'MUSIC_VIDEO_TYPE_OMV' ||
                  musicVideoType == 'MUSIC_VIDEO_TYPE_UGC';
              final isVideo = (isExplicitOmv || isVideoRecord(title, rawArtist)) && !isTopic;

              if (vId.isNotEmpty && title.isNotEmpty && vId != videoId && (!isVideo || isTopic)) {
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
                  extraData: {
                    'itemType': 'song',
                    if (musicVideoType.isNotEmpty) 'musicVideoType': musicVideoType,
                  },
                ));
              }
            }
          }
        }
      }

      return spaceOutArtistTracks(tracks);
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
            final track = parseListItem(item['musicResponsiveListItemRenderer']);
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
  static Track? parseListItem(Map<String, dynamic>? item) {
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
        for (final run in flex1) {
          final pageType = run['navigationEndpoint']
              ?['browseEndpoint']
              ?['browseEndpointContextSupportedConfigs']
              ?['browseEndpointContextMusicConfig']
              ?['pageType']
              ?.toString();
          if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
            final txt = run['text']?.toString().trim();
            if (txt != null && txt.isNotEmpty) {
              album = txt;
              break;
            }
          }
        }

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
            if (album.isEmpty && parts.length > 2 && !parts[2].contains(':')) {
              album = parts[2].trim();
            }
          } else {
            artist = first;
            if (album.isEmpty && parts.length > 1 && !parts[1].contains(':')) {
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

      final musicVideoType = item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
              ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']
              ?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
          item['flexColumns']?[0]
              ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]
              ?['navigationEndpoint']?['watchEndpoint']
              ?['watchEndpointMusicSupportedConfigs']
              ?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
          item['navigationEndpoint']?['watchEndpoint']
              ?['watchEndpointMusicSupportedConfigs']
              ?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
          '';

      final rawArtist = artist;
      final isTopicChannel = rawArtist.toLowerCase().endsWith('- topic') ||
          musicVideoType == 'MUSIC_VIDEO_TYPE_ATV';
      artist = artist
          .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
          .trim();

      final isExplicitOmv = musicVideoType == 'MUSIC_VIDEO_TYPE_OMV' ||
          musicVideoType == 'MUSIC_VIDEO_TYPE_UGC' ||
          (musicVideoType.contains('VIDEO') && !musicVideoType.contains('ATV'));
      final isVideo = (isExplicitOmv || isVideoRecord(title, rawArtist)) && !isTopicChannel;
      final itemType = isVideo ? 'video' : 'song';

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
        extraData: {
          'itemType': itemType,
          if (musicVideoType.isNotEmpty) 'musicVideoType': musicVideoType,
        },
      );
    } catch (_) {
      return null;
    }
  }

  static int _parseDuration(String timeStr) {
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
