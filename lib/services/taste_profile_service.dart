import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_mix.dart';
import '../models/track.dart';
import 'hifi_matcher.dart';
import 'youtube_music_service.dart';

/// Tracks listening behavior, calculates artist and genre affinities,
/// and clusters user taste into personalized Daily Mixes.
class TasteProfileService {
  final YouTubeMusicService _ytmService;

  // In-memory cache of taste profile
  Map<String, int> _artistWeights = {};
  Map<String, int> _trackPlayCounts = {};
  final Set<String> _favoriteTrackIds = {};
  final List<String> _recentHistoryIds = [];

  bool _isLoaded = false;

  TasteProfileService({YouTubeMusicService? ytmService})
      : _ytmService = ytmService ?? YouTubeMusicService();

  /// Loads persisted taste profile from local storage
  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final weightsJson = prefs.getString('taste_artist_weights');
      if (weightsJson != null && weightsJson.isNotEmpty) {
        final decoded = jsonDecode(weightsJson) as Map<String, dynamic>;
        _artistWeights = decoded.map((k, v) => MapEntry(k, v as int));
      }

      final playCountsJson = prefs.getString('taste_track_play_counts');
      if (playCountsJson != null && playCountsJson.isNotEmpty) {
        final decoded = jsonDecode(playCountsJson) as Map<String, dynamic>;
        _trackPlayCounts = decoded.map((k, v) => MapEntry(k, v as int));
      }

      final favsList = prefs.getStringList('taste_favorite_ids');
      if (favsList != null) {
        _favoriteTrackIds.addAll(favsList);
      }

      final historyList = prefs.getStringList('taste_recent_history');
      if (historyList != null) {
        _recentHistoryIds.addAll(historyList);
      }
    } catch (_) {}
    _isLoaded = true;
  }

  /// Records a track play event, updating artist and track weights
  Future<void> recordPlay(Track track) async {
    await init();
    final artist = _cleanArtist(track.artist);
    if (artist.isNotEmpty && artist != 'various artists') {
      _artistWeights[artist] = (_artistWeights[artist] ?? 0) + 1;
    }

    final tId = track.youtubeVideoId ?? track.id;
    if (tId.isNotEmpty) {
      _trackPlayCounts[tId] = (_trackPlayCounts[tId] ?? 0) + 1;
      _recentHistoryIds.remove(tId);
      _recentHistoryIds.insert(0, tId);
      if (_recentHistoryIds.length > 50) {
        _recentHistoryIds.removeLast();
      }
    }

    _persistTasteProfile();
  }

  /// Records liking or unliking a track
  Future<void> recordFavorite(Track track, bool isFavorited) async {
    await init();
    final tId = track.youtubeVideoId ?? track.id;
    final artist = _cleanArtist(track.artist);

    if (isFavorited) {
      _favoriteTrackIds.add(tId);
      if (artist.isNotEmpty && artist != 'various artists') {
        _artistWeights[artist] = (_artistWeights[artist] ?? 0) + 3;
      }
    } else {
      _favoriteTrackIds.remove(tId);
      if (artist.isNotEmpty && artist != 'various artists') {
        final current = _artistWeights[artist] ?? 0;
        if (current > 3) {
          _artistWeights[artist] = current - 3;
        }
      }
    }

    _persistTasteProfile();
  }

  /// Checks if a track is favorited
  bool isFavorite(String trackId) {
    return _favoriteTrackIds.contains(trackId);
  }

  /// Returns user's top artists sorted by affinity weight
  List<String> getTopArtists({int limit = 5}) {
    if (_artistWeights.isEmpty) return [];
    final sorted = _artistWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Generates 3-4 personalized Daily Mixes based on listening profile
  Future<List<DailyMix>> generateDailyMixes({
    required List<Track> fallbackCatalog,
  }) async {
    await init();
    final topArtists = getTopArtists();

    // Cold-start / Starter Mixes if listening history is minimal
    if (topArtists.isEmpty || fallbackCatalog.isEmpty) {
      return _buildStarterMixes(fallbackCatalog);
    }

    final mixes = <DailyMix>[];
    final excludedIds = <String>{};

    // Mix 1: Primary Taste Mix (Top Artist #1)
    final primaryArtist = topArtists[0];
    final mix1 = await _createMixForArtist(
      id: 'mix_1',
      title: 'Daily Mix 1',
      badge: 'MIX 1',
      artist: primaryArtist,
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFFFF5416), Color(0xFF5A32A3)],
      excludedTrackIds: excludedIds,
    );
    for (final t in mix1.tracks) {
      final id = t.youtubeVideoId ?? t.id;
      if (id.isNotEmpty) excludedIds.add(id);
    }
    mixes.add(mix1);

    // Mix 2: Alternate Vibe Mix (Top Artist #2 or secondary cluster, strictly distinct from Artist #1)
    String secondaryArtist = '';
    if (topArtists.length > 1 && _cleanArtist(topArtists[1]) != _cleanArtist(primaryArtist)) {
      secondaryArtist = topArtists[1];
    } else {
      for (final t in fallbackCatalog) {
        final a = _cleanArtist(t.artist);
        if (a.isNotEmpty && a != _cleanArtist(primaryArtist) && a != 'various artists') {
          secondaryArtist = t.artist;
          break;
        }
      }
      if (secondaryArtist.isEmpty) {
        const fallbackSeeds = ['The Weeknd', 'Coldplay', 'Taylor Swift', 'SZA', 'Queen', 'Bruno Mars'];
        secondaryArtist = fallbackSeeds.firstWhere(
          (s) => _cleanArtist(s) != _cleanArtist(primaryArtist),
          orElse: () => 'The Weeknd',
        );
      }
    }

    final mix2 = await _createMixForArtist(
      id: 'mix_2',
      title: 'Daily Mix 2',
      badge: 'MIX 2',
      artist: secondaryArtist,
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFF5A32A3), Color(0xFF0F2027)],
      excludedTrackIds: excludedIds,
    );
    for (final t in mix2.tracks) {
      final id = t.youtubeVideoId ?? t.id;
      if (id.isNotEmpty) excludedIds.add(id);
    }
    mixes.add(mix2);

    // Mix 3: Chill Vibe Mix (anchored on genuine chill artists, never bot spam)
    final mix3 = await _createChillLoungeMix(
      id: 'mix_chill',
      title: 'Chill Lounge',
      badge: 'CHILL',
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
    );
    mixes.add(mix3);

    // Mix 4: Hi-Fi Lossless Discovery Mix
    final mix4 = await _createHiFiMix(
      id: 'mix_hifi',
      title: 'Hi-Fi Discovery',
      badge: 'FLAC MIX',
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFFCCFF00), Color(0xFF1D212C)],
    );
    mixes.add(mix4);

    return mixes;
  }

  Future<DailyMix> _createMixForArtist({
    required String id,
    required String title,
    required String badge,
    required String artist,
    required List<Track> fallbackCatalog,
    required List<Color> gradientColors,
    Set<String>? excludedTrackIds,
  }) async {
    // 1. Find anchor track in fallbackCatalog or search
    Track? anchor = fallbackCatalog
        .where((t) => _cleanArtist(t.artist).contains(artist.toLowerCase()))
        .firstOrNull;

    List<Track> mixTracks = [];

    // 2. If anchor not in fallbackCatalog, query YouTube Music search for this specific artist
    if (anchor == null) {
      try {
        final searched = await _ytmService.searchSongs('$artist songs');
        if (searched.isNotEmpty) {
          anchor = searched.first;
        }
      } catch (_) {}
    }

    final anchorId = anchor?.youtubeVideoId ?? anchor?.id ?? '';

    if (anchorId.isNotEmpty) {
      try {
        final related = await _ytmService.getRelatedTracks(anchorId);
        mixTracks = related.where((t) => !isSpamOrBotTrack(t)).toList();
      } catch (_) {}
    }

    if (mixTracks.isEmpty) {
      try {
        final songs = await _ytmService.searchSongs('$artist songs');
        mixTracks = songs.where((t) => !isSpamOrBotTrack(t)).toList();
      } catch (_) {}
    }

    if (mixTracks.isEmpty) {
      mixTracks = fallbackCatalog
          .where((t) =>
              _cleanArtist(t.artist).contains(artist.toLowerCase()) &&
              !isSpamOrBotTrack(t))
          .toList();
      if (mixTracks.isEmpty) {
        mixTracks = fallbackCatalog.where((t) => !isSpamOrBotTrack(t)).toList();
      }
    }

    // 3. Strictly deduplicate against previous mix tracks
    if (excludedTrackIds != null && excludedTrackIds.isNotEmpty) {
      mixTracks = mixTracks.where((t) {
        final tid = t.youtubeVideoId ?? t.id;
        return !excludedTrackIds.contains(tid);
      }).toList();
    }

    // Build subtitle from top unique artists in the mix
    final artistsInMix = <String>{};
    for (final t in mixTracks) {
      final clean = _cleanArtist(t.artist);
      if (clean.isNotEmpty && clean != 'various artists') {
        artistsInMix.add(t.artist);
      }
      if (artistsInMix.length >= 3) break;
    }

    final subtitle = artistsInMix.isNotEmpty
        ? '${artistsInMix.join(", ")}, and more'
        : 'Curated mix based on $artist';

    final cover = mixTracks.isNotEmpty
        ? (mixTracks.first.highResThumbnailUrl.isNotEmpty
            ? mixTracks.first.highResThumbnailUrl
            : mixTracks.first.thumbnailUrl)
        : (anchor?.highResThumbnailUrl ?? '');

    final matcher = HifiMatcher();
    final enhancedTracks =
        mixTracks.map((t) => matcher.getCachedHiFi(t) ?? t).toList();

    return DailyMix(
      id: id,
      title: title,
      subtitle: subtitle,
      badge: badge,
      coverUrl: cover,
      gradientColors: gradientColors,
      tracks: enhancedTracks,
      seedArtist: artist,
    );
  }

  Future<DailyMix> _createChillLoungeMix({
    required String id,
    required String title,
    required String badge,
    required List<Track> fallbackCatalog,
    required List<Color> gradientColors,
  }) async {
    // 1. Identify a high-quality chill anchor from user's taste or fallback catalog
    Track? chillAnchor;
    const chillKeywords = [
      'bruno major',
      'fkj',
      'men i trust',
      'norah jones',
      'cigarettes after sex',
      'laufey',
      'daniel caesar',
      'keshi',
      'pamungkas',
      'feby putri',
      'niki',
      'wave to earth',
      'tom misch',
      'leon bridges',
      'mac demarco',
      'honne',
      'john mayer',
      'boy pablo',
      'phum viphurit',
      'khruangbin',
      'ardhito pramono',
      'frank ocean',
      'billie eilish',
      'sza',
      'kunto aji',
      'bernadya',
    ];

    for (final track in fallbackCatalog) {
      final cleanA = _cleanArtist(track.artist);
      if (chillKeywords.any((kw) => cleanA.contains(kw))) {
        chillAnchor = track;
        break;
      }
    }

    // Curated classic anchors if user history does not yet include chill artists
    final curatedAnchors = [
      const {'artist': 'Bruno Major', 'title': 'Nothing', 'id': 'kffacze53mg'},
      const {'artist': 'Men I Trust', 'title': 'Show Me How', 'id': 'OZURY4m4Fq0'},
      const {'artist': 'FKJ', 'title': 'Tadow', 'id': 'hC8CH0Z3L54'},
      const {'artist': 'Cigarettes After Sex', 'title': 'Apocalypse', 'id': 'sElE_BfQ67s'},
      const {'artist': 'Laufey', 'title': 'From The Start', 'id': 'lSD_L-x775s'},
      const {'artist': 'Daniel Caesar', 'title': 'Best Part', 'id': 'hKgl5-lkT8U'},
      const {'artist': 'Norah Jones', 'title': 'Don\'t Know Why', 'id': 'tO4dxvguQDk'},
    ];

    List<Track> mixTracks = [];

    // Strategy 1: YouTube Music radio algorithm via getRelatedTracks on anchor
    if (chillAnchor != null) {
      final anchorId = chillAnchor.youtubeVideoId ?? chillAnchor.id;
      if (anchorId.isNotEmpty) {
        try {
          final related = await _ytmService.getRelatedTracks(anchorId);
          mixTracks = related.where((t) => !isSpamOrBotTrack(t)).toList();
        } catch (_) {}
      }
    }

    // Strategy 2: Curated anchor radio rotation if no anchor or too few tracks
    if (mixTracks.length < 5) {
      final curated = curatedAnchors[DateTime.now().day % curatedAnchors.length];
      try {
        final related = await _ytmService.getRelatedTracks(curated['id']!);
        final filtered = related.where((t) => !isSpamOrBotTrack(t)).toList();
        if (filtered.isNotEmpty) {
          mixTracks = filtered;
        }
      } catch (_) {}
    }

    // Strategy 3: Targeted search for renowned chill artists instead of generic search
    if (mixTracks.length < 5) {
      try {
        final res = await _ytmService.searchSongs('Bruno Major FKJ Men I Trust');
        final filtered = res.where((t) => !isSpamOrBotTrack(t)).toList();
        if (filtered.isNotEmpty) {
          mixTracks = filtered;
        }
      } catch (_) {}
    }

    // Strategy 4: Fallback to non-spam catalog tracks or verified starter chill tracks
    if (mixTracks.isEmpty) {
      mixTracks = fallbackCatalog.where((t) => !isSpamOrBotTrack(t)).toList();
      if (mixTracks.isEmpty) {
        mixTracks = _buildStarterChillTracks();
      }
    }

    final artistsInMix = <String>{};
    for (final t in mixTracks) {
      final clean = _cleanArtist(t.artist);
      if (clean.isNotEmpty && clean != 'various artists') {
        artistsInMix.add(t.artist);
      }
      if (artistsInMix.length >= 3) break;
    }

    final subtitle = artistsInMix.isNotEmpty
        ? '${artistsInMix.join(", ")}, and more'
        : 'Mellow grooves & relaxing acoustic';

    final cover = mixTracks.isNotEmpty
        ? (mixTracks.first.highResThumbnailUrl.isNotEmpty
            ? mixTracks.first.highResThumbnailUrl
            : mixTracks.first.thumbnailUrl)
        : '';

    final matcher = HifiMatcher();
    final enhancedTracks =
        mixTracks.map((t) => matcher.getCachedHiFi(t) ?? t).toList();

    return DailyMix(
      id: id,
      title: title,
      subtitle: subtitle,
      badge: badge,
      coverUrl: cover,
      gradientColors: gradientColors,
      tracks: enhancedTracks,
    );
  }

  /// Checks whether a track originates from an algorithmic SEO bot channel,
  /// relaxation/sleep spam, white noise, or loop sound generator.
  static bool isSpamOrBotTrack(Track track) {
    final title = track.title.toLowerCase();
    final artist = track.artist.toLowerCase();

    const spamTerms = [
      'lo-fi',
      'lofi',
      'chillhop',
      'beats to',
      'relaxing',
      'relaxation',
      'sleep music',
      'sleep sounds',
      'nature sounds',
      'rain sounds',
      'white noise',
      'study music',
      'study beats',
      'ambient sound',
      'sound effect',
      'sound effects',
      'bgm',
      'meditation',
      'binaural',
      'frequency',
      'vibrations of',
      'healing music',
      'zen music',
      'asmr',
      'cafe music',
      'coffee shop sounds',
      '1 hour',
      '10 hours',
      'deep sleep',
      'relaxing guitar',
      'relaxing piano',
      'smooth lo-fi',
    ];

    for (final term in spamTerms) {
      if (title.contains(term) || artist.contains(term)) {
        return true;
      }
    }

    // Artist naming patterns typical of spam channels
    if (artist.endsWith(' lofi') ||
        artist.startsWith('lofi ') ||
        artist.endsWith(' beats') ||
        artist.startsWith('beats ') ||
        artist.contains('lo-fi') ||
        artist.contains('records &') ||
        artist.contains('& records') ||
        artist.contains('relaxing radio') ||
        artist.contains('vibe records') ||
        artist.contains('relaxing r')) {
      return true;
    }

    return false;
  }

  static List<Track> _buildStarterChillTracks() {
    return [
      Track(
        id: 'bruno_major_nothing',
        title: 'Nothing',
        artist: 'Bruno Major',
        album: 'To As Good As It Gets',
        durationSeconds: 162,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/44/27/c2/4427c244-884d-2a1c-5bb5-3ef3d0bb2be7/194491763188.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'men_i_trust_show_me_how',
        title: 'Show Me How',
        artist: 'Men I Trust',
        album: 'Oncle Jazz',
        durationSeconds: 215,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3d/8c/fb/3d8cfba3-5591-ba47-160a-a82f3484f227/cover.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'fkj_masego_tadow',
        title: 'Tadow',
        artist: 'Masego & FKJ',
        album: 'Lady Lady',
        durationSeconds: 301,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/7c/4f/95/7c4f958f-2a32-15f1-3316-c3f2d250c663/18UMGIM52317.rgb.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'cigarettes_after_sex_apocalypse',
        title: 'Apocalypse',
        artist: 'Cigarettes After Sex',
        album: 'Cigarettes After Sex',
        durationSeconds: 290,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/d5/43/e8/d543e8bb-76f5-ef85-4ae2-bcde64feee97/cover.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'laufey_from_the_start',
        title: 'From The Start',
        artist: 'Laufey',
        album: 'Bewitched',
        durationSeconds: 169,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/fa/ec/7b/faec7bd4-315c-fb82-9694-82548cb45e99/197188711411.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'daniel_caesar_best_part',
        title: 'Best Part',
        artist: 'Daniel Caesar ft. H.E.R.',
        album: 'Freudian',
        durationSeconds: 210,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/6c/49/7f/6c497fb2-c11c-d760-4648-52c6f140df95/cover.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'norah_jones_dont_know_why',
        title: "Don't Know Why",
        artist: 'Norah Jones',
        album: 'Come Away With Me',
        durationSeconds: 185,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b9/e7/76/b9e776ea-86ad-953b-e3c3-6e6a17b075e8/00602537021703.rgb.jpg/600x600bb.jpg',
      ),
      Track(
        id: 'pamungkas_to_the_bone',
        title: 'To the Bone',
        artist: 'Pamungkas',
        album: 'Flying Solo',
        durationSeconds: 345,
        thumbnailUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/55/b1/74/55b17409-5b72-f67b-2321-df621c17621c/cover.jpg/600x600bb.jpg',
      ),
    ];
  }

  Future<DailyMix> _createHiFiMix({
    required String id,
    required String title,
    required String badge,
    required List<Track> fallbackCatalog,
    required List<Color> gradientColors,
  }) async {
    final losslessTracks =
        fallbackCatalog.where((t) => t.isLossless).toList();
    final pool = losslessTracks.isNotEmpty ? losslessTracks : fallbackCatalog;

    final artistsInMix = pool.map((t) => t.artist).toSet().take(3).toList();
    final subtitle = artistsInMix.isNotEmpty
        ? '${artistsInMix.join(", ")}, and more'
        : 'Pure lossless audio quality';

    final cover = pool.isNotEmpty ? pool.first.highResThumbnailUrl : '';

    return DailyMix(
      id: id,
      title: title,
      subtitle: subtitle,
      badge: badge,
      coverUrl: cover,
      gradientColors: gradientColors,
      tracks: pool,
    );
  }

  List<DailyMix> _buildStarterMixes(List<Track> catalog) {
    if (catalog.isEmpty) return [];

    final matcher = HifiMatcher();
    final enhancedCatalog =
        catalog.map((t) => matcher.getCachedHiFi(t) ?? t).toList();
    final mix1Tracks = enhancedCatalog.take(4).toList();
    final mix2Tracks = enhancedCatalog.length > 4
        ? enhancedCatalog.skip(4).take(4).toList()
        : _buildStarterChillTracks().take(4).toList();

    final starterChill = _buildStarterChillTracks();
    final cleanChillCatalog =
        enhancedCatalog.where((t) => !isSpamOrBotTrack(t)).toList();
    final chillTracks =
        cleanChillCatalog.isNotEmpty ? cleanChillCatalog : starterChill;

    return [
      DailyMix(
        id: 'starter_1',
        title: 'Daily Mix 1',
        subtitle: mix1Tracks.map((t) => t.artist).toSet().take(3).join(', '),
        badge: 'MIX 1',
        coverUrl: mix1Tracks.isNotEmpty ? mix1Tracks.first.highResThumbnailUrl : '',
        gradientColors: const [Color(0xFFFF5416), Color(0xFF5A32A3)],
        tracks: mix1Tracks,
      ),
      DailyMix(
        id: 'starter_2',
        title: 'Daily Mix 2',
        subtitle: mix2Tracks.map((t) => t.artist).toSet().take(3).join(', '),
        badge: 'MIX 2',
        coverUrl: mix2Tracks.isNotEmpty ? mix2Tracks.first.highResThumbnailUrl : '',
        gradientColors: const [Color(0xFF5A32A3), Color(0xFF0F2027)],
        tracks: mix2Tracks,
      ),
      DailyMix(
        id: 'starter_3',
        title: 'Chill Lounge',
        subtitle: 'Mellow grooves & relaxing acoustic',
        badge: 'CHILL',
        coverUrl:
            chillTracks.isNotEmpty ? chillTracks.first.highResThumbnailUrl : '',
        gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
        tracks: chillTracks,
      ),
      DailyMix(
        id: 'starter_4',
        title: 'Hi-Fi Discovery',
        subtitle: 'Pure lossless masters in FLAC',
        badge: 'FLAC MIX',
        coverUrl: enhancedCatalog.first.highResThumbnailUrl,
        gradientColors: const [Color(0xFFCCFF00), Color(0xFF1D212C)],
        tracks: enhancedCatalog.where((t) => t.isLossless).toList(),
      ),
    ];
  }

  String _cleanArtist(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\s*-\s*topic$'), '')
        .replaceAll(RegExp(r'vevo$'), '')
        .trim();
  }

  Future<void> _persistTasteProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('taste_artist_weights', jsonEncode(_artistWeights));
      await prefs.setString(
          'taste_track_play_counts', jsonEncode(_trackPlayCounts));
      await prefs.setStringList(
          'taste_favorite_ids', _favoriteTrackIds.toList());
      await prefs.setStringList('taste_recent_history', _recentHistoryIds);
    } catch (_) {}
  }
}
