import 'dart:convert';
import '../core/network/holo_http_client.dart';
import '../models/artist_details.dart';
import '../models/track.dart';
import 'artwork_service.dart';
import 'youtube_music_service.dart';

class ArtistService {
  static const String _innertubeSearchUrl =
      'https://music.youtube.com/youtubei/v1/search';
  static const String _innertubeBrowseUrl =
      'https://music.youtube.com/youtubei/v1/browse';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Artist search filter param
  static const String _artistFilterParam =
      'EgWKAQIgAWoOEAQQAxAFEAkQEBAKEBU%3D';

  final YouTubeMusicService _ytmService;
  final ArtworkService? _artworkService;

  final Map<String, ArtistDetails> _cache = {};

  ArtistService({
    YouTubeMusicService? ytmService,
    ArtworkService? artworkService,
  })  : _ytmService = ytmService ?? YouTubeMusicService(),
        _artworkService = artworkService;

  String _cleanArtistName(String name) {
    return name
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(Official\)$', caseSensitive: false), '')
        .trim();
  }

  /// Fetches comprehensive artist details including top songs, albums, singles, and bio
  Future<ArtistDetails> getArtistDetails(
    String artistName, {
    String? browseId,
  }) async {
    final cleanName = _cleanArtistName(artistName);
    if (cleanName.isEmpty) {
      throw ArgumentError('Artist name cannot be empty');
    }

    final cacheKey = cleanName.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    String targetBrowseId = browseId?.trim() ?? '';
    String? searchAvatar;

    // 1. Resolve artist browseId if not provided
    if (targetBrowseId.isEmpty) {
      final searchResult = await _searchArtistBrowseId(cleanName);
      if (searchResult != null) {
        targetBrowseId = searchResult['browseId'] ?? '';
        searchAvatar = searchResult['avatar'];
      }
    }

    // 2. If no browseId found, fallback to search-based artist details
    if (targetBrowseId.isEmpty) {
      final fallback = await _buildFallbackArtistDetails(cleanName, searchAvatar);
      _cache[cacheKey] = fallback;
      return fallback;
    }

    // 3. Browse artist page on YouTube Music
    try {
      final browsePayload = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'browseId': targetBrowseId,
      };

      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_innertubeBrowseUrl),
            headers: {
              'User-Agent': _userAgent,
              'Content-Type': 'application/json',
              'Referer': 'https://music.youtube.com/',
              'Origin': 'https://music.youtube.com',
            },
            body: jsonEncode(browsePayload),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) {
        final fallback = await _buildFallbackArtistDetails(cleanName, searchAvatar);
        _cache[cacheKey] = fallback;
        return fallback;
      }

      final data = jsonDecode(res.body);
      final details = _parseArtistBrowseResponse(
        data,
        cleanName,
        targetBrowseId,
        searchAvatar,
      );

      if (details.topSongs.isEmpty) {
        final fallbackSongs = await _ytmService.searchSongs(cleanName);
        final enhancedDetails = details.copyWith(
          topSongs: fallbackSongs,
        );
        _cache[cacheKey] = enhancedDetails;
        return enhancedDetails;
      }

      _cache[cacheKey] = details;
      if (details.name.isNotEmpty) {
        _cache[details.name.toLowerCase()] = details;
      }
      return details;
    } catch (_) {
      final fallback = await _buildFallbackArtistDetails(cleanName, searchAvatar);
      _cache[cacheKey] = fallback;
      return fallback;
    }
  }

  /// Searches for the artist's channel browseId and avatar
  Future<Map<String, String?>?> _searchArtistBrowseId(String artistName) async {
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': artistName,
      'params': _artistFilterParam,
    };

    try {
      final res = await HoloHttpClient.client
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

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final sectionList = data['contents']?['tabbedSearchResultsRenderer']
          ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents'];

      if (sectionList == null || sectionList is! List) return null;

      Map<String, dynamic>? bestItem;

      for (final section in sectionList) {
        final items = section['musicShelfRenderer']?['contents'];
        if (items != null && items is List) {
          for (final rawItem in items) {
            final item = rawItem['musicResponsiveListItemRenderer'];
            if (item == null) continue;

            final title = item['flexColumns']?[0]
                ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                ?[0]?['text'] as String?;

            if (title != null &&
                title.toLowerCase() == artistName.toLowerCase()) {
              bestItem = item;
              break;
            }
            bestItem ??= item;
          }
        }
        if (bestItem != null) break;
      }

      if (bestItem != null) {
        final bId = bestItem['navigationEndpoint']?['browseEndpoint']?['browseId'] ??
            bestItem['flexColumns']?[0]
                ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                ?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId'];

        final thumbs = bestItem['thumbnail']?['musicThumbnailRenderer']
            ?['thumbnail']?['thumbnails'] as List?;
        final avatar = (thumbs != null && thumbs.isNotEmpty)
            ? thumbs.last['url']?.toString()
            : null;

        if (bId != null) {
          return {
            'browseId': bId.toString(),
            'avatar': avatar,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  ArtistDetails _parseArtistBrowseResponse(
    Map<String, dynamic> data,
    String requestedName,
    String browseId,
    String? searchAvatar,
  ) {
    // Header parsing
    final header = data['header']?['musicImmersiveHeaderRenderer'] ??
        data['header']?['musicVisualHeaderRenderer'] ??
        data['header']?['musicHeaderRenderer'];

    final resolvedName = header?['title']?['runs']?[0]?['text']?.toString() ??
        requestedName;

    final headerThumbs = header?['thumbnail']?['musicThumbnailRenderer']
        ?['thumbnail']?['thumbnails'] as List?;
    final bannerImg = (headerThumbs != null && headerThumbs.isNotEmpty)
        ? headerThumbs.last['url']?.toString()
        : searchAvatar;

    final subscribers = header?['subscriptionButton']
        ?['subscribeButtonRenderer']?['subscriberCountText']?['runs']?[0]?['text']
        ?.toString();

    final monthly =
        header?['monthlyListenerCount']?['runs']?[0]?['text']?.toString();

    // Bio and description parsing
    String? bioText;
    String? wikiUrl;
    String? totalViews;

    final sections = data['contents']?['singleColumnBrowseResultsRenderer']
        ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
        ?['contents'] as List?;

    final List<Track> topSongs = [];
    String? topSongsPlaylistId;
    final List<ArtistRelease> albums = [];
    final List<ArtistRelease> singles = [];

    if (sections != null) {
      for (final s in sections) {
        // Shelf renderer (usually Top Songs)
        final shelf = s['musicShelfRenderer'];
        if (shelf != null) {
          final shelfTitle = (shelf['title']?['runs']?[0]?['text'] ?? '')
              .toString()
              .toLowerCase();

          if (shelfTitle.contains('song') || shelfTitle.contains('top')) {
            topSongsPlaylistId = shelf['bottomEndpoint']?['browseEndpoint']
                ?['browseId']
                ?.toString();

            final contents = shelf['contents'] as List?;
            if (contents != null) {
              for (final rawItem in contents) {
                final item = rawItem['musicResponsiveListItemRenderer'];
                if (item == null) continue;
                final track = _parseSongItem(item, resolvedName);
                if (track != null) {
                  topSongs.add(track);
                }
              }
            }
          }
        }

        // Carousel renderer (Albums, Singles, EPs)
        final carousel = s['musicCarouselShelfRenderer'];
        if (carousel != null) {
          final carouselTitle = (carousel['header']
                      ?['musicCarouselShelfBasicHeaderRenderer']?['title']
                      ?['runs']?[0]?['text'] ??
                  '')
              .toString()
              .toLowerCase();

          final contents = carousel['contents'] as List?;
          if (contents != null) {
            for (final rawItem in contents) {
              final twoRow = rawItem['musicTwoRowItemRenderer'];
              if (twoRow == null) continue;

              final title =
                  twoRow['title']?['runs']?[0]?['text']?.toString() ?? '';
              final subtitle = (twoRow['subtitle']?['runs'] as List?)
                      ?.map((r) => r['text']?.toString() ?? '')
                      .join('') ??
                  '';
              final bId = twoRow['navigationEndpoint']?['browseEndpoint']
                      ?['browseId']
                  ?.toString();
              final thumbs = twoRow['thumbnailRenderer']
                  ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
              final thumb = (thumbs != null && thumbs.isNotEmpty)
                  ? thumbs.last['url']?.toString() ?? ''
                  : '';

              if (title.isNotEmpty && bId != null) {
                final release = ArtistRelease(
                  title: title,
                  year: _extractYear(subtitle),
                  type: _extractReleaseType(subtitle, carouselTitle),
                  browseId: bId,
                  thumbnailUrl: thumb,
                );

                if (carouselTitle.contains('album')) {
                  albums.add(release);
                } else if (carouselTitle.contains('single') ||
                    carouselTitle.contains('ep')) {
                  singles.add(release);
                }
              }
            }
          }
        }

        // Description shelf (About / Bio)
        final descShelf = s['musicDescriptionShelfRenderer'];
        if (descShelf != null) {
          totalViews =
              descShelf['subheader']?['runs']?[0]?['text']?.toString();

          final runs = descShelf['description']?['runs'] as List?;
          if (runs != null) {
            final fullBio = runs.map((r) => r['text']?.toString() ?? '').join();
            final bioParsed = _parseBioAndWiki(fullBio);
            bioText = bioParsed['bio'];
            wikiUrl = bioParsed['wikiUrl'];

            // Also check urlEndpoint in runs for direct wikipedia url
            for (final run in runs) {
              final directUrl =
                  run['navigationEndpoint']?['urlEndpoint']?['url']?.toString();
              if (directUrl != null && directUrl.contains('wikipedia.org')) {
                wikiUrl = directUrl;
                break;
              }
            }
          }
        }
      }
    }

    return ArtistDetails(
      name: resolvedName,
      browseId: browseId,
      bannerUrl: bannerImg,
      avatarUrl: searchAvatar,
      subscribers: subscribers,
      monthlyAudience: monthly,
      bio: bioText,
      wikiUrl: wikiUrl,
      totalViews: totalViews,
      topSongs: topSongs,
      topSongsPlaylistId: topSongsPlaylistId,
      albums: albums,
      singles: singles,
      hasLoadedAllSongs: false,
    );
  }

  Track? _parseSongItem(Map<String, dynamic> item, String defaultArtist) {
    try {
      final videoId = item['playlistItemData']?['videoId'] ??
          item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
              ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['videoId'];

      if (videoId == null || (videoId as String).isEmpty) return null;

      final flexCols = item['flexColumns'] as List?;
      if (flexCols == null || flexCols.isEmpty) return null;

      final title = flexCols[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?[0]?['text']
          ?.toString() ??
          '';
      if (title.isEmpty) return null;

      String artist = defaultArtist;
      String? playsText;
      String album = '';

      if (flexCols.length > 1) {
        final flex1Runs = flexCols[1]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
        if (flex1Runs != null && flex1Runs.isNotEmpty) {
          artist = flex1Runs[0]['text']?.toString() ?? defaultArtist;
        }
      }

      if (flexCols.length > 2) {
        final flex2Runs = flexCols[2]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
        if (flex2Runs != null && flex2Runs.isNotEmpty) {
          final t = flex2Runs[0]['text']?.toString() ?? '';
          if (t.toLowerCase().contains('play') || t.toLowerCase().contains('view')) {
            playsText = t;
          }
        }
      }

      if (flexCols.length > 3) {
        final flex3Runs = flexCols[3]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
        if (flex3Runs != null && flex3Runs.isNotEmpty) {
          album = flex3Runs[0]['text']?.toString() ?? '';
        }
      }

      final thumbs = item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']
          ?['thumbnails'] as List?;
      final thumbUrl = (thumbs != null && thumbs.isNotEmpty)
          ? thumbs.last['url']?.toString() ?? ''
          : '';

      return Track(
        id: videoId,
        title: title,
        artist: artist,
        album: album,
        thumbnailUrl: Track.toHighResUrl(thumbUrl),
        durationSeconds: 210, // Default fallback duration
        youtubeVideoId: videoId,
        audioSource: 'youtube',
        isLossless: false,
        extraData: playsText != null ? {'plays': playsText} : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetches all top songs when user taps "Show all songs"
  Future<List<Track>> getArtistTopSongs(
    String playlistId, {
    required String artistName,
  }) async {
    final browseId =
        playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';

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

    try {
      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_innertubeBrowseUrl),
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
      final twoCol = data['contents']?['twoColumnBrowseResultsRenderer'];
      final secList = twoCol?['secondaryContents']?['sectionListRenderer']
              ?['contents'] as List? ??
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]
              ?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;

      if (secList == null || secList.isEmpty) return [];

      final pShelf = secList[0]['musicPlaylistShelfRenderer'] ??
          secList[0]['musicShelfRenderer'];
      final contents = pShelf?['contents'] as List?;

      if (contents == null) return [];

      final List<Track> songs = [];
      for (final item in contents) {
        final r = item['musicResponsiveListItemRenderer'];
        if (r == null) continue;
        final track = _parseSongItem(r, artistName);
        if (track != null) {
          songs.add(track);
        }
      }

      return songs;
    } catch (_) {
      return [];
    }
  }

  /// Fetches tracks from a specific album or EP
  Future<List<Track>> getAlbumTracks(
    String browseId, {
    required String artistName,
    required String albumName,
  }) async {
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

    try {
      final res = await HoloHttpClient.client
          .post(
            Uri.parse(_innertubeBrowseUrl),
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
      final twoCol = data['contents']?['twoColumnBrowseResultsRenderer'];
      final secList = twoCol?['secondaryContents']?['sectionListRenderer']
          ?['contents'] as List?;
      final shelf = secList?[0]?['musicShelfRenderer'];
      final contents = shelf?['contents'] as List?;

      if (contents == null) return [];

      final List<Track> albumSongs = [];
      for (final rawItem in contents) {
        final r = rawItem['musicResponsiveListItemRenderer'];
        if (r == null) continue;

        final videoId = r['playlistItemData']?['videoId'] ??
            r['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
                ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
                ?['watchEndpoint']?['videoId'];

        if (videoId == null) continue;

        final title = r['flexColumns']?[0]
                ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                ?[0]?['text']
            ?.toString() ??
            '';

        if (title.isNotEmpty) {
          albumSongs.add(Track(
            id: videoId,
            title: title,
            artist: artistName,
            album: albumName,
            thumbnailUrl: '',
            durationSeconds: 210,
            youtubeVideoId: videoId,
            audioSource: 'youtube',
            isLossless: false,
          ));
        }
      }

      return albumSongs;
    } catch (_) {
      return [];
    }
  }

  Future<ArtistDetails> _buildFallbackArtistDetails(
    String artistName,
    String? avatar,
  ) async {
    final songs = await _ytmService.searchSongs(artistName);
    String? resolvedBanner = avatar;

    if (resolvedBanner == null && _artworkService != null && songs.isNotEmpty) {
      resolvedBanner = await _artworkService.getArtwork(
        artistName,
        songs.first.title,
      );
    }

    return ArtistDetails(
      name: artistName,
      browseId: '',
      bannerUrl: resolvedBanner,
      avatarUrl: resolvedBanner,
      subscribers: null,
      monthlyAudience: null,
      bio: null,
      topSongs: songs,
      albums: const [],
      singles: const [],
    );
  }

  Map<String, String?> _parseBioAndWiki(String rawBio) {
    if (rawBio.isEmpty) return {'bio': null, 'wikiUrl': null};

    final match = RegExp(
      r'^(.*?)(?:(?:\r?\n)+|\s+)From Wikipedia\s*(?:\((https?:\/\/[^\s)]+)\))?(?:\s*under\s*Creative Commons[^\n]*)?\s*$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawBio);

    if (match != null) {
      return {
        'bio': match.group(1)?.trim(),
        'wikiUrl': match.group(2),
      };
    }

    final truncatedMatch = RegExp(
      r'^(.*?)(?:(?:\r?\n)+|\s+)From Wikipedia\s*\(?\s*$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawBio);

    if (truncatedMatch != null) {
      return {
        'bio': truncatedMatch.group(1)?.trim(),
        'wikiUrl': null,
      };
    }

    return {'bio': rawBio.trim(), 'wikiUrl': null};
  }

  String _extractYear(String subtitle) {
    final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(subtitle);
    return match?.group(1) ?? '';
  }

  String _extractReleaseType(String subtitle, String carouselTitle) {
    final subLower = subtitle.toLowerCase();
    if (subLower.contains('single') || carouselTitle.contains('single')) {
      return 'Single';
    }
    if (subLower.contains('ep') || carouselTitle.contains('ep')) {
      return 'EP';
    }
    return 'Album';
  }
}
