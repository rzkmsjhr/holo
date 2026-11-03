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

    // Mix 1: Primary Taste Mix (Top Artist #1)
    final primaryArtist = topArtists[0];
    final mix1 = await _createMixForArtist(
      id: 'mix_1',
      title: 'Daily Mix 1',
      badge: 'MIX 1',
      artist: primaryArtist,
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFFFF5416), Color(0xFF5A32A3)],
    );
    mixes.add(mix1);

    // Mix 2: Alternate Vibe Mix (Top Artist #2 or secondary cluster)
    final secondaryArtist = topArtists.length > 1
        ? topArtists[1]
        : (fallbackCatalog.length > 1 ? fallbackCatalog[1].artist : 'Pop');
    final mix2 = await _createMixForArtist(
      id: 'mix_2',
      title: 'Daily Mix 2',
      badge: 'MIX 2',
      artist: secondaryArtist,
      fallbackCatalog: fallbackCatalog,
      gradientColors: const [Color(0xFF5A32A3), Color(0xFF0F2027)],
    );
    mixes.add(mix2);

    // Mix 3: Chill Vibe Mix
    final mix3 = await _createMoodMix(
      id: 'mix_chill',
      title: 'Chill Lounge',
      badge: 'CHILL',
      query: 'chill lofi acoustic r&b',
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
  }) async {
    // 1. Find anchor track in fallbackCatalog or search
    Track? anchor = fallbackCatalog.firstWhere(
      (t) => _cleanArtist(t.artist).contains(artist.toLowerCase()),
      orElse: () => fallbackCatalog.first,
    );

    List<Track> mixTracks = [];
    final anchorId = anchor.youtubeVideoId ?? anchor.id;

    if (anchorId.isNotEmpty) {
      try {
        mixTracks = await _ytmService.getRelatedTracks(anchorId);
      } catch (_) {}
    }

    if (mixTracks.isEmpty) {
      try {
        mixTracks = await _ytmService.searchSongs('$artist songs');
      } catch (_) {}
    }

    if (mixTracks.isEmpty) {
      mixTracks = fallbackCatalog
          .where((t) => _cleanArtist(t.artist).contains(artist.toLowerCase()))
          .toList();
      if (mixTracks.isEmpty) mixTracks = List.from(fallbackCatalog);
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
        : anchor.highResThumbnailUrl;

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

  Future<DailyMix> _createMoodMix({
    required String id,
    required String title,
    required String badge,
    required String query,
    required List<Track> fallbackCatalog,
    required List<Color> gradientColors,
  }) async {
    List<Track> mixTracks = [];
    try {
      mixTracks = await _ytmService.searchSongs(query);
    } catch (_) {}

    if (mixTracks.isEmpty) {
      mixTracks = List.from(fallbackCatalog);
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
        : 'Mellow tracks to unwind';

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
    final mix2Tracks = enhancedCatalog.reversed.take(4).toList();

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
        coverUrl: enhancedCatalog.length > 2 ? enhancedCatalog[2].highResThumbnailUrl : '',
        gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
        tracks: enhancedCatalog,
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
