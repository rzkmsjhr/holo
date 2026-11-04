import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../core/network/holo_http_client.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import 'youtube_music_service.dart';

enum PlaylistPlatform {
  youtube,
  spotify,
  unknown,
}

class ParsedPlaylistUrl {
  final PlaylistPlatform platform;
  final String playlistId;
  final String originalUrl;

  const ParsedPlaylistUrl({
    required this.platform,
    required this.playlistId,
    required this.originalUrl,
  });
}

class PlaylistImportResult {
  final String title;
  final String? coverUrl;
  final List<Track> tracks;
  final List<String> unmatchedTrackNames;
  final PlaylistPlatform platform;

  const PlaylistImportResult({
    required this.title,
    this.coverUrl,
    required this.tracks,
    this.unmatchedTrackNames = const [],
    required this.platform,
  });
}

class SpotifyPlaylistTrack {
  final String title;
  final String artist;
  final int durationMs;

  const SpotifyPlaylistTrack({
    required this.title,
    required this.artist,
    required this.durationMs,
  });
}

class PlaylistImportService {
  final YouTubeMusicService _ytmService;

  PlaylistImportService({YouTubeMusicService? ytmService})
      : _ytmService = ytmService ?? YouTubeMusicService();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const List<(String, String)> _japaneseArtistPairs = [
    ("mariya takeuchi", "竹内まりや"),
    ("takeuchi mariya", "竹内まりや"),
    ("reiko takahashi", "高橋玲子"),
    ("takahashi reiko", "高橋玲子"),
    ("noriyuki makihara", "槇原敬之"),
    ("makihara noriyuki", "槇原敬之"),
    ("tatsuro yamashita", "山下達郎"),
    ("yamashita tatsuro", "山下達郎"),
    ("miki matsubara", "松原みき"),
    ("matsubara miki", "松原みき"),
    ("taeko onuki", "大貫妙子"),
    ("onuki taeko", "大貫妙子"),
    ("anri", "杏里"),
    ("akina nakamori", "中森明菜"),
    ("nakamori akina", "中森明菜"),
    ("seiko matsuda", "松田聖子"),
    ("matsuda seiko", "松田聖子"),
    ("junko yagami", "八神純子"),
    ("yagami junko", "八神純子"),
    ("tomoko aran", "亜蘭知子"),
    ("aran tomoko", "亜蘭知子"),
    ("meiko nakahara", "中原めいこ"),
    ("nakahara meiko", "中原めいこ"),
    ("masayoshi takanaka", "高中正義"),
    ("takanaka masayoshi", "高中正義"),
  ];

  static const List<(String, String)> _japaneseTitlePairs = [
    ("シングル アゲイン", "single again"),
    ("シングルアゲイン", "single again"),
    ("プラスティック ラブ", "plastic love"),
    ("プラスチック ラブ", "plastic love"),
    ("サンセット ロード", "sunset road"),
    ("ステイ ウィズ ミー", "stay with me"),
    ("フライディ チャイナタウン", "fly day chinatown"),
    ("フライデー チャイナタウン", "friday chinatown"),
    ("真夜中のドア", "stay with me"),
    ("もう恋なんてしない", "mo koi nante shinai"),
    ("元気を出して", "genki wo dashite"),
    ("元気を出して", "genki o dashite"),
    ("縁の糸", "enishi no ito"),
  ];

  /// Parses any user-pasted input (including mobile share-text with surrounding prose)
  /// into a structured `ParsedPlaylistUrl`.
  static ParsedPlaylistUrl? parsePlaylistUrl(String input) {
    if (input.trim().isEmpty) return null;
    final trimmed = input.trim();

    // Extract URL if surrounded by mobile share text
    final urlMatch = RegExp(r'https?://[^\s<>"]+|(?:spotify:playlist:[a-zA-Z0-9]+)')
        .firstMatch(trimmed);
    final rawUrl = urlMatch != null ? urlMatch.group(0)! : trimmed;

    // Spotify URI format: spotify:playlist:xxxx
    final spotUriMatch =
        RegExp(r'spotify:playlist:([a-zA-Z0-9]+)').firstMatch(rawUrl);
    if (spotUriMatch != null) {
      return ParsedPlaylistUrl(
        platform: PlaylistPlatform.spotify,
        playlistId: spotUriMatch.group(1)!,
        originalUrl: rawUrl,
      );
    }

    try {
      final uri = Uri.parse(rawUrl);
      final host = uri.host.toLowerCase();
      final path = uri.path;

      // Spotify web URL
      if (host.contains('spotify.com')) {
        final match = RegExp(r'/playlist/([a-zA-Z0-9]+)').firstMatch(path);
        if (match != null) {
          return ParsedPlaylistUrl(
            platform: PlaylistPlatform.spotify,
            playlistId: match.group(1)!,
            originalUrl: rawUrl,
          );
        }
      }

      // Spotify mobile shortlink (spotify.link / spoti.fi)
      if (host == 'spotify.link' || host == 'spoti.fi') {
        return ParsedPlaylistUrl(
          platform: PlaylistPlatform.spotify,
          playlistId: '', // To be resolved via HTTP redirect follow
          originalUrl: rawUrl,
        );
      }

      // YouTube / YouTube Music playlist
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        final listParam = uri.queryParameters['list'];
        if (listParam != null && listParam.isNotEmpty) {
          return ParsedPlaylistUrl(
            platform: PlaylistPlatform.youtube,
            playlistId: listParam,
            originalUrl: rawUrl,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Follows mobile redirect shortlinks (e.g. spotify.link) to extract canonical playlist ID
  static Future<ParsedPlaylistUrl?> resolveShortlink(
      ParsedPlaylistUrl parsed) async {
    if (parsed.playlistId.isNotEmpty) return parsed;
    try {
      final client = HoloHttpClient.client;
      final request = http.Request('GET', Uri.parse(parsed.originalUrl))
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['User-Agent'] = _userAgent;

      final streamedRes =
          await client.send(request).timeout(const Duration(seconds: 8));
      final response = await http.Response.fromStream(streamedRes);

      final finalUrl = response.request?.url.toString();
      if (finalUrl != null && finalUrl.isNotEmpty) {
        final resolved = parsePlaylistUrl(finalUrl);
        if (resolved != null && resolved.playlistId.isNotEmpty) {
          return resolved;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Cleans Spotify track titles by stripping remaster/edition metadata for search parity.
  /// Mirrors nadanada's `clean_spotify_title`.
  static String cleanSpotifyTitle(String title) {
    final re = RegExp(
      r'\s*[-–—]\s*(?:\d{4}\s+)?(?:(?:\w+\s+)?(?:remaster(?:ed)?|mix|edit|version|mono|stereo|anniversary|live|deluxe|expanded|bonus track)).*$',
      caseSensitive: false,
    );
    final stripped = title.replaceAll(re, '').trim();
    final target = stripped.isEmpty ? title : stripped;
    return YouTubeMusicService.cleanTitleForMatching(target);
  }

  static String normalizeText(String? str) {
    if (str == null) return '';
    return str
        .toLowerCase()
        .replaceAll(RegExp(r'[・\uff65]'), ' ')
        .replaceAll(RegExp(r'[^\w\s\u3040-\u30ff\u4e00-\u9faf]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String cleanTitleForArtistMatch(String title) {
    return title
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'（[^）]*）'), ' ')
        .replaceAll(RegExp(r'【[^】]*】'), ' ')
        .replaceAll(RegExp(r'[・\uff65,!?;:~\\/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Evaluates whether a candidate track matches the target artist.
  /// Mirrors nadanada's `doesCandidateMatchArtist`.
  static bool doesCandidateMatchArtist(
      Track candidate, List<String> artistWords, String rawArtist) {
    if (artistWords.isEmpty) return true;
    if (YouTubeMusicService.isKaraokeOrDerivative(
        candidate.title, candidate.artist, '')) {
      return false;
    }

    final rawChannel = candidate.artist
        .replaceAll(RegExp(r'\s*-\s*topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'vevo$', caseSensitive: false), '')
        .trim();
    final channelNorm = normalizeText(rawChannel);
    final rawArtistNorm = normalizeText(rawArtist);

    // Cross-script Japanese artist matching
    for (final pair in _japaneseArtistPairs) {
      final latin = pair.$1;
      final kanji = pair.$2;
      if (rawArtistNorm.contains(latin) || rawArtistNorm.contains(kanji)) {
        if (channelNorm.contains(latin) || channelNorm.contains(kanji)) {
          return true;
        }
        final cleanTitle = cleanTitleForArtistMatch(candidate.title);
        final firstPart = normalizeText(
            cleanTitle.split(RegExp(r'\s*[-–—:]\s*')).firstOrNull ?? '');
        if (firstPart.contains(latin) || firstPart.contains(kanji)) {
          return true;
        }
        return false;
      }
    }

    // 1. Channel match
    final matchedInChannel =
        artistWords.where((w) => channelNorm.contains(w)).length;
    if (matchedInChannel >= (artistWords.length * 0.6).ceil()) {
      return true;
    }
    if (rawArtist.isNotEmpty && channelNorm.contains(rawArtistNorm)) {
      return true;
    }

    // Multi-artist collaboration matching
    final individualArtists = rawArtist
        .split(RegExp(
            r'[,&/]|(?:\s+ft\.?\s+|\s+feat\.?\s+|\s+featuring\s+|\s+x\s+|\s+with\s+)',
            caseSensitive: false))
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    for (final indArtist in individualArtists) {
      final indNorm = normalizeText(indArtist);
      if (indNorm.length >= 2) {
        if (channelNorm == indNorm || channelNorm.contains(indNorm)) {
          return true;
        }
        if (indNorm.contains(channelNorm) && channelNorm.length >= 3) {
          return true;
        }
        final indWords = indNorm.split(' ').where((w) => w.length > 2).toList();
        if (indWords.isNotEmpty &&
            indWords.every((w) => channelNorm.contains(w))) {
          return true;
        }
      }
    }

    // For official song items: artist must match channel
    final itemType = candidate.extraData?['itemType'] as String?;
    if (itemType == 'song') {
      return false;
    }

    // For video items only: check title prefix before delimiter
    final cleanTitle = cleanTitleForArtistMatch(candidate.title);
    final parts = cleanTitle.split(RegExp(r'\s*[-–—:]\s*'));
    if (parts.length >= 2) {
      final firstPart = parts[0];
      final firstPartNorm = normalizeText(firstPart);

      for (final indArtist in individualArtists) {
        final indNorm = normalizeText(indArtist);
        if (indNorm.length >= 2 &&
            (firstPartNorm.contains(indNorm) ||
                (firstPartNorm.length >= 3 && indNorm.contains(firstPartNorm)))) {
          return true;
        }
      }

      final ftMatch = RegExp(r'^(.*?)\s+(?:ft\.?|feat\.?|featuring)\s+(.*)$',
              caseSensitive: false)
          .firstMatch(firstPart);
      if (ftMatch != null) {
        final leadArtistNorm = normalizeText(ftMatch.group(1));
        final leadMatches =
            artistWords.where((w) => leadArtistNorm.contains(w)).length;
        if (leadMatches < (artistWords.length * 0.6).ceil()) {
          return false;
        }
      }

      final matchedInFirst =
          artistWords.where((w) => firstPartNorm.contains(w)).length;
      if (matchedInFirst >= (artistWords.length * 0.6).ceil()) {
        return true;
      }
    }

    return false;
  }

  /// Evaluates whether a candidate track matches the target title.
  /// Mirrors nadanada's `doesCandidateMatchTitle`.
  static bool doesCandidateMatchTitle(Track candidate, String expectedTitle) {
    if (expectedTitle.isEmpty) return false;

    final cleanExpected = cleanTitleForArtistMatch(expectedTitle);
    final cleanCand = cleanTitleForArtistMatch(candidate.title);

    final normExpected = normalizeText(cleanExpected);
    final normCand = normalizeText(cleanCand);

    if (cleanExpected.isNotEmpty &&
        candidate.title.toLowerCase().contains(cleanExpected.toLowerCase())) {
      return true;
    }
    if (normExpected.isNotEmpty &&
        normCand.isNotEmpty &&
        (normCand.contains(normExpected) || normExpected.contains(normCand))) {
      return true;
    }

    // Cross-script Japanese/English loanword title matching
    for (final pair in _japaneseTitlePairs) {
      final normJp = normalizeText(pair.$1);
      final normEn = normalizeText(pair.$2);
      if ((normExpected.contains(normJp) && normCand.contains(normEn)) ||
          (normExpected.contains(normEn) && normCand.contains(normJp))) {
        return true;
      }
    }

    return false;
  }

  /// High-level entry point: imports playlist from either YouTube or Spotify URL
  Future<PlaylistImportResult> importPlaylist(
    String inputUrl, {
    void Function(int current, int total, String trackName)? onProgress,
  }) async {
    var parsed = parsePlaylistUrl(inputUrl);
    if (parsed == null) {
      throw FormatException('Invalid or unsupported playlist URL: "$inputUrl"');
    }

    if (parsed.playlistId.isEmpty) {
      final resolved = await resolveShortlink(parsed);
      if (resolved == null || resolved.playlistId.isEmpty) {
        throw FormatException('Could not resolve shortlink playlist: "$inputUrl"');
      }
      parsed = resolved;
    }

    if (parsed.platform == PlaylistPlatform.youtube) {
      return fetchYouTubePlaylist(parsed.playlistId);
    } else if (parsed.platform == PlaylistPlatform.spotify) {
      return fetchSpotifyPlaylist(parsed.playlistId, onProgress: onProgress);
    } else {
      throw FormatException('Unsupported platform for URL: "$inputUrl"');
    }
  }

  /// Imports a YouTube or YouTube Music playlist with pure studio song resolution.
  /// Mirrors nadanada's `get_youtube_playlist` & `get_playlist_title`.
  Future<PlaylistImportResult> fetchYouTubePlaylist(String playlistId) async {
    // 1. Primary: YouTube Music Browse API (pure Song tracks + official metadata)
    try {
      final ytmResult = await _fetchYtmBrowsePlaylist(playlistId);
      if (ytmResult.tracks.isNotEmpty) {
        return ytmResult;
      }
    } catch (_) {}

    // 2. Fallback: YouTube Web playlist scraper (video tracks as last resort)
    final scrapeResult = await _scrapeYouTubeWebPlaylist(playlistId);
    if (scrapeResult.tracks.isNotEmpty) {
      return scrapeResult;
    }

    throw StateError('Could not find any playable tracks in this YouTube playlist.');
  }

  Future<PlaylistImportResult> _fetchYtmBrowsePlaylist(String playlistId) async {
    final browseId = playlistId.startsWith('VL') || playlistId.startsWith('MPRE')
        ? playlistId
        : 'VL$playlistId';

    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'browseId': browseId,
    };

    final res = await HoloHttpClient.client
        .post(
          Uri.parse('https://music.youtube.com/youtubei/v1/browse'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _userAgent,
            'Referer': 'https://music.youtube.com/',
            'Origin': 'https://music.youtube.com',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      return const PlaylistImportResult(
        title: '',
        tracks: [],
        platform: PlaylistPlatform.youtube,
      );
    }

    final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
    final data = jsonDecode(decoded) as Map<String, dynamic>;

    // Extract title & cover
    String title = 'Imported YouTube Playlist';
    String? coverUrl;

    final header = data['header']?['musicDetailHeaderRenderer'] ??
        data['header']?['musicEditablePlaylistDetailHeaderRenderer']?['header']
            ?['musicDetailHeaderRenderer'];

    if (header != null) {
      final t = header['title']?['runs']?[0]?['text'] ??
          header['title']?['simpleText'];
      if (t != null && t.toString().isNotEmpty) {
        title = TextEncodingUtils.cleanMojibake(t.toString());
      }
      final thumbs = header['thumbnail']?['croppedSquareThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List?;
      if (thumbs != null && thumbs.isNotEmpty) {
        coverUrl = thumbs.last['url']?.toString();
      }
    }

    final shelfContents = data['contents']?['twoColumnBrowseResultsRenderer']
            ?['secondaryContents']?['sectionListRenderer']?['contents']?[0]
        ?['musicPlaylistShelfRenderer']?['contents'] ??
        data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]
                ?['tabRenderer']?['content']?['sectionListRenderer']
            ?['contents']?[0]?['musicPlaylistShelfRenderer']?['contents'] ??
        data['contents']?['twoColumnBrowseResultsRenderer']
            ?['secondaryContents']?['sectionListRenderer']?['contents']?[0]
            ?['musicShelfRenderer']?['contents'];

    final List<Track> tracks = [];
    if (shelfContents is List) {
      for (final item in shelfContents) {
        final r = item['musicResponsiveListItemRenderer'];
        if (r != null) {
          final track = YouTubeMusicService.parseListItem(r);
          if (track != null) {
            tracks.add(track);
          }
        }
        if (tracks.length >= 200) break;
      }
    }

    if (coverUrl == null && tracks.isNotEmpty) {
      coverUrl = tracks.first.highResThumbnailUrl;
    }

    return PlaylistImportResult(
      title: title,
      coverUrl: coverUrl,
      tracks: tracks,
      platform: PlaylistPlatform.youtube,
    );
  }

  Future<PlaylistImportResult> _scrapeYouTubeWebPlaylist(String playlistId) async {
    final url = 'https://www.youtube.com/playlist?list=$playlistId';
    final res = await HoloHttpClient.client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'en-US,en;q=0.9',
        'Cookie': 'CONSENT=YES+cb.20210328-17-p0.en+FX+478',
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      return const PlaylistImportResult(
        title: '',
        tracks: [],
        platform: PlaylistPlatform.youtube,
      );
    }

    final match = RegExp(r'var ytInitialData\s*=\s*(\{.*?\});</script>')
        .firstMatch(res.body);
    if (match == null) {
      return const PlaylistImportResult(
        title: '',
        tracks: [],
        platform: PlaylistPlatform.youtube,
      );
    }

    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;

    String title = data['header']?['playlistHeaderRenderer']?['title']
            ?['simpleText'] ??
        data['header']?['playlistHeaderRenderer']?['title']?['runs']?[0]
            ?['text'] ??
        data['metadata']?['playlistMetadataRenderer']?['title'] ??
        'Imported YouTube Playlist';
    title = TextEncodingUtils.cleanMojibake(title);

    String? coverUrl = data['header']?['playlistHeaderRenderer']
            ?['playlistHeaderBanner']?['heroPlaylistThumbnailRenderer']
        ?['thumbnail']?['thumbnails']?.last?['url'];

    final List<Track> tracks = [];

    // Check watch next panel
    final watchContents = data['contents']?['twoColumnWatchNextResults']
        ?['playlist']?['playlist']?['contents'];
    final browseContents = data['contents']?['twoColumnBrowseResultsRenderer']
            ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
            ?['contents']?[0]?['itemSectionRenderer']?['contents']?[0]
        ?['playlistVideoListRenderer']?['contents'];

    final contents = (watchContents is List && watchContents.isNotEmpty)
        ? watchContents
        : (browseContents is List ? browseContents : []);

    for (final item in contents) {
      final vid =
          item['playlistVideoRenderer'] ?? item['playlistPanelVideoRenderer'];
      if (vid != null) {
        final id = vid['videoId']?.toString() ?? '';
        final vTitle = vid['title']?['simpleText']?.toString() ??
            vid['title']?['runs']?[0]?['text']?.toString() ??
            '';
        final channel =
            vid['shortBylineText']?['runs']?[0]?['text']?.toString() ?? '';
        final durStr = vid['lengthText']?['simpleText']?.toString() ??
            vid['lengthText']?['runs']?[0]?['text']?.toString() ??
            '';
        final thumbs = vid['thumbnail']?['thumbnails'] as List?;
        final thumb = (thumbs != null && thumbs.isNotEmpty)
            ? thumbs.last['url']?.toString() ?? ''
            : '';

        if (id.isNotEmpty && vTitle.isNotEmpty) {
          final isTopic = channel.toLowerCase().endsWith('- topic');
          tracks.add(Track(
            id: id,
            title: TextEncodingUtils.cleanMojibake(vTitle),
            artist: TextEncodingUtils.cleanMojibake(
                channel.isNotEmpty ? channel : 'Various Artists'),
            thumbnailUrl: Track.toHighResUrl(thumb),
            durationSeconds: _parseDurationString(durStr),
            youtubeVideoId: id,
            audioSource: 'youtube',
            isLossless: false,
            extraData: {'itemType': isTopic ? 'song' : 'video'},
          ));
        }
      }
      if (tracks.length >= 200) break;
    }

    if (coverUrl == null && tracks.isNotEmpty) {
      coverUrl = tracks.first.highResThumbnailUrl;
    }

    return PlaylistImportResult(
      title: title,
      coverUrl: coverUrl,
      tracks: tracks,
      platform: PlaylistPlatform.youtube,
    );
  }

  /// Imports a Spotify playlist via the public embed JSON metadata and matches
  /// each track against YouTube Music using nadanada's 4-pass verification.
  Future<PlaylistImportResult> fetchSpotifyPlaylist(
    String playlistId, {
    void Function(int current, int total, String trackName)? onProgress,
  }) async {
    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
    final res = await HoloHttpClient.client.get(
      Uri.parse(embedUrl),
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw StateError('Failed to fetch Spotify playlist (HTTP ${res.statusCode}).');
    }

    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(res.body);

    if (match == null) {
      throw StateError('Could not parse Spotify playlist metadata.');
    }

    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final entity = data['props']?['pageProps']?['state']?['data']?['entity'];

    if (entity == null) {
      throw StateError('Spotify playlist entity not found or is private.');
    }

    final playlistTitle = entity['name']?.toString() ?? 'Imported Spotify Playlist';
    final coverArt = entity['coverArt']?['sources']?[0]?['url']?.toString() ??
        entity['images']?[0]?['url']?.toString();

    final rawTrackList = entity['trackList'] as List? ?? [];
    final List<SpotifyPlaylistTrack> spotifyTracks = [];

    for (final item in rawTrackList) {
      final tTitle = item['title']?.toString() ?? '';
      final tArtist = item['subtitle']?.toString() ?? '';
      final durationMs = (item['duration'] as num?)?.toInt() ?? 0;
      if (tTitle.isNotEmpty) {
        spotifyTracks.add(SpotifyPlaylistTrack(
          title: tTitle,
          artist: tArtist,
          durationMs: durationMs,
        ));
      }
    }

    if (spotifyTracks.isEmpty) {
      throw StateError('This Spotify playlist is empty or private.');
    }

    final List<Track> importedTracks = [];
    final List<String> unmatchedTrackNames = [];

    // Concurrent batched resolution: 3 tracks at a time to optimize speed
    // without triggering HTTP 429 rate limits
    const batchSize = 3;
    for (int i = 0; i < spotifyTracks.length; i += batchSize) {
      final batch = spotifyTracks.sublist(
        i,
        min(i + batchSize, spotifyTracks.length),
      );

      final results = await Future.wait(batch.map((st) async {
        try {
          return await _resolveSpotifyTrack(st);
        } catch (_) {
          return null;
        }
      }));

      for (int b = 0; b < batch.length; b++) {
        final st = batch[b];
        final matched = results[b];
        final label = st.artist.isNotEmpty ? '${st.artist} - ${st.title}' : st.title;

        if (matched != null) {
          importedTracks.add(matched);
        } else {
          unmatchedTrackNames.add(label);
        }
      }

      final progressCount = min(i + batchSize, spotifyTracks.length);
      final currentTrackName = batch.last.title;
      onProgress?.call(progressCount, spotifyTracks.length, currentTrackName);

      if (i + batchSize < spotifyTracks.length) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    return PlaylistImportResult(
      title: TextEncodingUtils.cleanMojibake(playlistTitle),
      coverUrl: coverArt,
      tracks: importedTracks,
      unmatchedTrackNames: unmatchedTrackNames,
      platform: PlaylistPlatform.spotify,
    );
  }

  Future<Track?> _resolveSpotifyTrack(SpotifyPlaylistTrack st) async {
    final cleanTitle = cleanSpotifyTitle(st.title);
    final query = '$cleanTitle ${st.artist}'.trim();

    // 1. Search YouTube Music Songs (1:1 nadanada query parity)
    var results = await _ytmService.searchSongs(query);

    final artistWords = st.artist.isNotEmpty
        ? normalizeText(st.artist)
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 1)
            .toSet()
            .toList()
        : <String>[];

    // Check if any candidate genuinely matches BOTH title and artist
    final hasFullMatch = results.any((r) =>
        doesCandidateMatchTitle(r, st.title) &&
        doesCandidateMatchArtist(r, artistWords, st.artist));

    // Fallback to video search if official song doesn't have a full match
    if (!hasFullMatch) {
      try {
        final videoResults = await _ytmService.searchVideos(query);
        for (final vid in videoResults) {
          if (!results.any((r) => r.id == vid.id)) {
            results.add(vid);
          }
        }
      } catch (_) {}
    }

    if (results.isEmpty) return null;

    final cleanResults = results.where((r) {
      return !YouTubeMusicService.isKaraokeOrDerivative(r.title, r.artist, query);
    }).toList();

    // Pass 1: Candidate matching BOTH target artist AND target title
    Track? bestVideo = cleanResults.where((r) =>
        doesCandidateMatchArtist(r, artistWords, st.artist) &&
        doesCandidateMatchTitle(r, st.title)).firstOrNull;

    // Pass 2: Candidate matching title AND any individual collaborator
    if (bestVideo == null && st.artist.isNotEmpty) {
      final collaborators = st.artist
          .split(RegExp(
              r'[,&/]|(?:\s+ft\.?\s+|\s+feat\.?\s+|\s+featuring\s+|\s+x\s+|\s+with\s+)',
              caseSensitive: false))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();

      bestVideo = cleanResults.where((r) {
        if (!doesCandidateMatchTitle(r, st.title)) return false;
        final candNorm = normalizeText('${r.title} ${r.artist}');
        return collaborators.any((ind) {
          final indNorm = normalizeText(ind);
          return indNorm.length >= 3 && candNorm.contains(indNorm);
        });
      }).firstOrNull;
    }

    // Pass 3: Candidate matching title AND has artist word connection (>= 3 chars)
    if (bestVideo == null && artistWords.isNotEmpty) {
      bestVideo = cleanResults.where((r) {
        if (!doesCandidateMatchTitle(r, st.title)) return false;
        final candNorm = normalizeText('${r.title} ${r.artist}');
        return artistWords.any((w) => w.length >= 3 && candNorm.contains(w));
      }).firstOrNull;
    }

    // Pass 4: Fallback only if no artist was specified
    if (bestVideo == null && st.artist.isEmpty) {
      bestVideo = cleanResults.isNotEmpty ? cleanResults.first : results.first;
    }

    if (bestVideo != null) {
      // Sync duration from Spotify if candidate duration was 0
      if (bestVideo.durationSeconds == 0 && st.durationMs > 0) {
        bestVideo = bestVideo.copyWith(
          durationSeconds: st.durationMs ~/ 1000,
        );
      }
    }

    return bestVideo;
  }

  static int _parseDurationString(String timeStr) {
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
