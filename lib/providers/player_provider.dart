import 'dart:async';
import 'dart:convert';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_mix.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/trending_track.dart';
import '../services/artwork_service.dart';
import '../services/connectivity_service.dart';
import '../services/hifi_matcher.dart';
import '../services/kworb_data_snapshot.dart';
import '../services/lyrics_service.dart';
import '../services/playlist_service.dart';
import '../services/taste_profile_service.dart';
import '../services/trending_service.dart';
import '../services/vibe_recommendation_service.dart';
import '../services/youtube_music_service.dart';
import '../services/youtube_stream_resolver.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final HifiMatcher _hifiMatcher = HifiMatcher();
  final YouTubeStreamResolver _ytResolver = YouTubeStreamResolver();
  final YouTubeMusicService _ytmService = YouTubeMusicService();
  final LyricsService _lyricsService = LyricsService();
  final PlaylistService _playlistService = PlaylistService();
  final ArtworkService _artworkService = ArtworkService();
  late final TasteProfileService _tasteProfile =
      TasteProfileService(ytmService: _ytmService);
  late final VibeRecommendationService _vibeService =
      VibeRecommendationService(ytmService: _ytmService);
  late final TrendingService _trendingService =
      TrendingService(ytmService: _ytmService);

  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _queue = [];
  List<Track>? _recentlyPlayed = [];
  List<DailyMix>? _dailyMixes = [];
  bool? _isLoadingMixes = false;
  List<TrendingTrack>? _globalTrending =
      kGlobalTop50Snapshot.map(TrendingTrack.fromMap).toList();
  List<TrendingTrack>? _indonesiaTrending =
      kIndonesiaTop50Snapshot.map(TrendingTrack.fromMap).toList();
  bool? _isLoadingTrending = false;
  String? _resolvingTrendingKey;
  List<Playlist>? _playlists = [];
  int _currentIndex = 0;
  bool _isShuffled = false;
  int _repeatMode = 0; // 0 = off, 1 = all, 2 = one
  double _volume = 1.0; // Locked to maximum unity gain (100% volume)
  bool _isHifiResolving = false;
  bool _isDarkMode = true;
  String? _playbackError;
  bool _isBuffering = false;

  // Settings
  bool _isEndlessPlay = true; // default on
  bool _isHifiEnabled = true; // default on
  bool _isFetchingEndless = false;

  // Real-time lyrics state
  bool? _hasSyncedLyrics = false;
  List<LyricLine>? _currentLyrics = [];
  bool? _isLoadingLyrics = false;

  // Stream subscriptions
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _eventSub;
  StreamSubscription? _connectivitySub;

  // Getters
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => _queue;
  bool get isOnline => ConnectivityService().isOnline;
  bool get isSlowConnection => ConnectivityService().isSlow;
  ConnectivityStatus get connectivityStatus => ConnectivityService().status;
  List<Track> get recentlyPlayed {
    final list = _recentlyPlayed;
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return _queue;
  }
  int get currentIndex => _currentIndex;
  bool get isShuffled => _isShuffled;
  int get repeatMode => _repeatMode;
  double get volume => _volume;
  bool get isHifiResolving => _isHifiResolving;
  bool get isDarkMode => _isDarkMode;
  String? get playbackError => _playbackError;
  bool get isEndlessPlay => _isEndlessPlay;
  bool get isHifiEnabled => _isHifiEnabled;
  bool get isFetchingEndless => _isFetchingEndless;
  bool get hasSyncedLyrics => _hasSyncedLyrics ?? false;
  List<LyricLine> get currentLyrics => _currentLyrics ?? const [];
  bool get isLoadingLyrics => _isLoadingLyrics ?? false;
  List<DailyMix> get dailyMixes => _dailyMixes ?? const [];
  bool get isLoadingMixes => _isLoadingMixes ?? false;
  List<TrendingTrack> get globalTrending {
    final list = _globalTrending;
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return kGlobalTop50Snapshot.map(TrendingTrack.fromMap).toList();
  }

  List<TrendingTrack> get indonesiaTrending {
    final list = _indonesiaTrending;
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return kIndonesiaTop50Snapshot.map(TrendingTrack.fromMap).toList();
  }
  bool get isLoadingTrending => _isLoadingTrending ?? false;
  String? get resolvingTrendingKey => _resolvingTrendingKey;
  List<Playlist> get playlists => _playlists ?? const [];
  static const String _likedTracksKey = 'user_liked_tracks_v2';
  static const String _recentlyPlayedKey = 'holo_recently_played_v2';
  static const String _lastTrackKey = 'holo_last_track_v2';
  static const String _lastQueueKey = 'holo_last_queue_v2';
  static const String _lastIndexKey = 'holo_last_index_v2';
  List<Track> _likedTracks = [];
  List<Track> get likedTracks => _likedTracks;

  bool isFavorite(String trackId) {
    return _likedTracks.any((t) => (t.youtubeVideoId ?? t.id) == trackId) ||
        _tasteProfile.isFavorite(trackId);
  }

  List<String> get topArtists => _tasteProfile.getTopArtists(limit: 10);

  String? getArtwork(String artist, String title) =>
      _artworkService.getCached(artist, title);

  void resolveArtworkFor(String artist, String title, [bool isId = false]) {
    _artworkService.getArtwork(artist, title, isIndonesian: isId).then((art) {
      if (art != null && art.isNotEmpty) {
        _updateAllMatchingTrackArtworks(artist, title, art);
      }
    });
  }

  PlayerProvider() {
    _initConnectivity();
    _initAudioListeners();
    _initSavedPlayerState();
    _initTasteAndMixes();
    _initTrending();
    _initPlaylists();
    _initArtworkService();
    _initLikedTracks();
  }

  void _initConnectivity() {
    final connectivity = ConnectivityService();
    connectivity.startMonitoring();
    _connectivitySub = connectivity.statusStream.listen((status) {
      if (status == ConnectivityStatus.offline) {
        if (_isPlaying) {
          _playbackError = 'Connection lost. Operating offline.';
        }
      } else if (status == ConnectivityStatus.online && _playbackError != null) {
        if (_playbackError!.contains('connection') ||
            _playbackError!.contains('internet') ||
            _playbackError!.contains('timed out')) {
          _playbackError = null;
        }
      }
      notifyListeners();
    });
  }

  void _initLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_likedTracksKey);
      if (saved != null && saved.isNotEmpty) {
        final List<dynamic> list = jsonDecode(saved);
        _likedTracks = list
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _likedTracks.map((t) => t.toJson()).toList();
      await prefs.setString(_likedTracksKey, jsonEncode(list));
    } catch (_) {}
  }

  void _initArtworkService() async {
    await _artworkService.init();
    _ensureArtworksLoaded();
  }

  void _initTasteAndMixes() async {
    await _tasteProfile.init();
    await refreshDailyMixes();
  }

  void _initTrending() async {
    await loadTrending();
  }

  void _initPlaylists() async {
    await loadPlaylists();
  }

  void _initAudioListeners() async {
    try {
      await _audioPlayer.setVolume(1.0);
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    _posSub = _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _stateSub = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      notifyListeners();
    });

    _eventSub = _audioPlayer.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        _playbackError = 'Streaming interrupted. Tap to retry.';
        _isBuffering = false;
        notifyListeners();
      },
    );
  }

  void _initSavedPlayerState() async {
    _queue = [];
    _currentTrack = null;
    _recentlyPlayed = [];

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore recently played
      final savedRecent = prefs.getString(_recentlyPlayedKey);
      if (savedRecent != null && savedRecent.isNotEmpty) {
        final List<dynamic> list = jsonDecode(savedRecent);
        _recentlyPlayed = list
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      // 2. Restore playing queue & index
      final savedQueue = prefs.getString(_lastQueueKey);
      if (savedQueue != null && savedQueue.isNotEmpty) {
        final List<dynamic> list = jsonDecode(savedQueue);
        _queue = list
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      final savedIndex = prefs.getInt(_lastIndexKey) ?? 0;
      if (_queue.isNotEmpty) {
        _currentIndex = savedIndex.clamp(0, _queue.length - 1);
      }

      // 3. Restore last played track
      final savedTrack = prefs.getString(_lastTrackKey);
      if (savedTrack != null && savedTrack.isNotEmpty) {
        final Map<String, dynamic> trackJson = jsonDecode(savedTrack);
        final track = Track.fromJson(trackJson);
        _currentTrack = track;
        _duration = Duration(seconds: track.durationSeconds);
        _position = Duration.zero;
        _isPlaying = false;
      } else if (_queue.isNotEmpty && _currentIndex < _queue.length) {
        _currentTrack = _queue[_currentIndex];
        _duration = Duration(seconds: _currentTrack!.durationSeconds);
        _position = Duration.zero;
        _isPlaying = false;
      }

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistPlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Save recently played
      if (_recentlyPlayed != null) {
        final recentList = _recentlyPlayed!.map((t) => t.toJson()).toList();
        await prefs.setString(_recentlyPlayedKey, jsonEncode(recentList));
      }

      // 2. Save queue and index
      if (_queue.isNotEmpty) {
        final queueList = _queue.map((t) => t.toJson()).toList();
        await prefs.setString(_lastQueueKey, jsonEncode(queueList));
        await prefs.setInt(_lastIndexKey, _currentIndex);
      }

      // 3. Save current track
      if (_currentTrack != null) {
        await prefs.setString(_lastTrackKey, jsonEncode(_currentTrack!.toJson()));
      }
    } catch (_) {}
  }

  void _addToRecentlyPlayed(Track track) {
    _recentlyPlayed ??= <Track>[];
    _recentlyPlayed!.removeWhere((t) =>
        (t.youtubeVideoId ?? t.id) == (track.youtubeVideoId ?? track.id) ||
        (t.title.toLowerCase().trim() == track.title.toLowerCase().trim() &&
            t.artist.toLowerCase().trim() == track.artist.toLowerCase().trim()));
    _recentlyPlayed!.insert(0, track);
    if (_recentlyPlayed!.length > 20) {
      _recentlyPlayed!.removeLast();
    }
    _persistPlayerState();
  }

  void _updateAllMatchingTrackArtworks(
      String artist, String title, String art) {
    if (art.isEmpty) return;
    final cleanA = artist.toLowerCase().trim();
    final cleanT = title.toLowerCase().trim();

    bool changed = false;

    if (_currentTrack != null &&
        _currentTrack!.artist.toLowerCase().trim() == cleanA &&
        _currentTrack!.title.toLowerCase().trim() == cleanT &&
        _currentTrack!.thumbnailUrl.isEmpty) {
      _currentTrack = _currentTrack!.copyWith(thumbnailUrl: art);
      changed = true;
    }

    if (_recentlyPlayed != null) {
      for (var i = 0; i < _recentlyPlayed!.length; i++) {
        final t = _recentlyPlayed![i];
        if (t.artist.toLowerCase().trim() == cleanA &&
            t.title.toLowerCase().trim() == cleanT &&
            t.thumbnailUrl.isEmpty) {
          _recentlyPlayed![i] = t.copyWith(thumbnailUrl: art);
          changed = true;
        }
      }
    }

    for (var i = 0; i < _queue.length; i++) {
      final t = _queue[i];
      if (t.artist.toLowerCase().trim() == cleanA &&
          t.title.toLowerCase().trim() == cleanT &&
          t.thumbnailUrl.isEmpty) {
        _queue[i] = t.copyWith(thumbnailUrl: art);
        changed = true;
      }
    }

    if (_globalTrending != null) {
      for (var i = 0; i < _globalTrending!.length; i++) {
        final t = _globalTrending![i];
        if (t.artist.toLowerCase().trim() == cleanA &&
            t.title.toLowerCase().trim() == cleanT &&
            (t.thumbnailUrl == null || t.thumbnailUrl!.isEmpty)) {
          _globalTrending![i] = t.copyWith(thumbnailUrl: art);
          changed = true;
        }
      }
    }

    if (_indonesiaTrending != null) {
      for (var i = 0; i < _indonesiaTrending!.length; i++) {
        final t = _indonesiaTrending![i];
        if (t.artist.toLowerCase().trim() == cleanA &&
            t.title.toLowerCase().trim() == cleanT &&
            (t.thumbnailUrl == null || t.thumbnailUrl!.isEmpty)) {
          _indonesiaTrending![i] = t.copyWith(thumbnailUrl: art);
          changed = true;
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _ensureArtworksLoaded() async {
    if (_recentlyPlayed != null) {
      for (final t in _recentlyPlayed!) {
        if (t.thumbnailUrl.isEmpty) {
          final art = await _artworkService.getArtwork(t.artist, t.title);
          if (art != null && art.isNotEmpty) {
            _updateAllMatchingTrackArtworks(t.artist, t.title, art);
          }
        }
      }
    }

    for (final t in _queue) {
      if (t.thumbnailUrl.isEmpty) {
        final art = await _artworkService.getArtwork(t.artist, t.title);
        if (art != null && art.isNotEmpty) {
          _updateAllMatchingTrackArtworks(t.artist, t.title, art);
        }
      }
    }

    _preloadTrendingArtworks();
  }

  void _preloadTrendingArtworks() async {
    final toCheck = <TrendingTrack>[];
    if (_globalTrending != null) {
      for (final t in _globalTrending!) {
        if (t.thumbnailUrl == null || t.thumbnailUrl!.isEmpty) {
          toCheck.add(t);
        }
      }
    }
    if (_indonesiaTrending != null) {
      for (final t in _indonesiaTrending!) {
        if (t.thumbnailUrl == null || t.thumbnailUrl!.isEmpty) {
          toCheck.add(t);
        }
      }
    }

    for (final item in toCheck) {
      final isId = _indonesiaTrending?.contains(item) == true;
      final art = await _artworkService.getArtwork(
        item.artist,
        item.title,
        isIndonesian: isId,
      );
      if (art != null && art.isNotEmpty) {
        _updateAllMatchingTrackArtworks(item.artist, item.title, art);
      }
    }
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void toggleEndlessPlay([bool? value]) {
    _isEndlessPlay = value ?? !_isEndlessPlay;
    notifyListeners();
    if (_isEndlessPlay) {
      _triggerEndlessPlayIfNeeded();
    }
  }

  void toggleHifi([bool? value]) {
    _isHifiEnabled = value ?? !_isHifiEnabled;
    notifyListeners();
    if (_isHifiEnabled) {
      _resolveQueueHiFiInBackground();
    }
  }

  void toggleFavorite(Track track) {
    final tId = track.youtubeVideoId ?? track.id;
    final isAlreadyFav = isFavorite(tId);
    final nowFav = !isAlreadyFav;

    if (nowFav) {
      if (!_likedTracks.any((t) => (t.youtubeVideoId ?? t.id) == tId)) {
        _likedTracks.insert(0, track);
      }
    } else {
      _likedTracks.removeWhere((t) => (t.youtubeVideoId ?? t.id) == tId);
    }

    _tasteProfile.recordFavorite(track, nowFav);
    _saveLikedTracks();
    notifyListeners();
  }

  void removeLikedTrack(String trackId) {
    final index = _likedTracks.indexWhere(
        (t) => (t.youtubeVideoId ?? t.id) == trackId);
    if (index != -1) {
      final removed = _likedTracks.removeAt(index);
      _tasteProfile.recordFavorite(removed, false);
      _saveLikedTracks();
      notifyListeners();
    }
  }

  void playDailyMix(DailyMix mix, [int startIndex = 0]) {
    if (mix.tracks.isEmpty) return;
    _queue = List.from(mix.tracks);
    final idx = startIndex.clamp(0, _queue.length - 1);
    _currentIndex = idx;
    playTrack(_queue[idx]);
  }

  Future<void> refreshDailyMixes() async {
    _isLoadingMixes = true;
    notifyListeners();
    try {
      final mixes =
          await _tasteProfile.generateDailyMixes(fallbackCatalog: _queue);
      if (mixes.isNotEmpty) {
        _dailyMixes = mixes;
      }
    } catch (_) {}
    _isLoadingMixes = false;
    notifyListeners();
  }

  Future<void> loadTrending() async {
    _isLoadingTrending = true;
    notifyListeners();
    try {
      final g = await _trendingService.getTrending('global');
      final id = await _trendingService.getTrending('indonesia');
      _globalTrending = g;
      _indonesiaTrending = id;
    } catch (_) {}
    _isLoadingTrending = false;
    notifyListeners();
  }

  Future<void> playTrendingTrack(TrendingTrack item) async {
    final key = '${item.artist} - ${item.title}'.toLowerCase();
    _resolvingTrendingKey = key;
    notifyListeners();
    Track? trackToPlay;
    try {
      final resolved = await _trendingService.resolveTrack(item);
      if (resolved != null) {
        trackToPlay = resolved;
        if (trackToPlay.thumbnailUrl.isEmpty) {
          final art = item.thumbnailUrl ??
              await _artworkService.getArtwork(item.artist, item.title);
          if (art != null && art.isNotEmpty) {
            trackToPlay = trackToPlay.copyWith(thumbnailUrl: art);
          }
        }
        _updateAllMatchingTrackArtworks(
            item.artist, item.title, trackToPlay.thumbnailUrl);
      }
    } catch (_) {
    } finally {
      // Clear resolving state as soon as the lookup finishes
      _resolvingTrendingKey = null;
      notifyListeners();
    }

    if (trackToPlay != null) {
      await playTrack(trackToPlay);
    }
  }

  Future<void> loadPlaylists() async {
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String title,
      {String description = '', List<Track>? initialTracks}) async {
    final p = await _playlistService.createPlaylist(
      title,
      description: description,
      initialTracks: initialTracks,
    );
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
    return p;
  }

  Future<bool> addTrackToPlaylist(String playlistId, Track track) async {
    final success =
        await _playlistService.addTrackToPlaylist(playlistId, track);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
    return success;
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    await _playlistService.removeTrackFromPlaylist(playlistId, trackId);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _playlistService.deletePlaylist(playlistId);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
  }

  Future<void> renamePlaylist(String playlistId, String newTitle) async {
    await _playlistService.renamePlaylist(playlistId, newTitle);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
  }

  Future<void> reorderPlaylistTracks(
      String playlistId, int oldIndex, int newIndex) async {
    await _playlistService.reorderTracksInPlaylist(
        playlistId, oldIndex, newIndex);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
  }

  void playPlaylist(Playlist playlist, [int startIndex = 0]) {
    if (playlist.tracks.isEmpty) return;
    _queue = List.from(playlist.tracks);
    final idx = startIndex.clamp(0, _queue.length - 1);
    _currentIndex = idx;
    playTrack(_queue[idx]);
  }

  void playTrackList(List<Track> tracks, [int startIndex = 0]) {
    if (tracks.isEmpty) return;
    _queue = List.from(tracks);
    final idx = startIndex.clamp(0, _queue.length - 1);
    _currentIndex = idx;
    playTrack(_queue[idx]);
  }

  void shuffleTrackList(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks)..shuffle();
    playTrackList(shuffled, 0);
  }

  void playNext(Track track) {
    if (_queue.isEmpty) {
      _queue.add(track);
      _currentIndex = 0;
      playTrack(track);
      return;
    }
    final nextIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(nextIdx, track);
    notifyListeners();
  }

  /// Condition 1: When a track is going to be played (at all states)
  Future<void> playTrack(Track track) async {
    _currentTrack = track;
    _addToRecentlyPlayed(track);
    _tasteProfile.recordPlay(track);
    _playbackError = null;
    _currentIndex = _queue.indexOf(track);
    if (_currentIndex == -1) {
      // New song selected from outside queue: seed a fresh queue around this track
      _queue = [track];
      _currentIndex = 0;
    }
    _persistPlayerState();
    _duration = Duration(seconds: track.durationSeconds);
    _position = Duration.zero;
    _isBuffering = true;

    // Check connectivity before network resolution
    if (!isOnline && (track.flacStreamUrl == null || track.flacStreamUrl!.isEmpty)) {
      _playbackError = 'No internet connection. Reconnect to stream "${track.title}".';
      _isBuffering = false;
      notifyListeners();
      return;
    }

    // Resolve missing artwork in background
    if (track.thumbnailUrl.isEmpty) {
      _artworkService.getArtwork(track.artist, track.title).then((art) {
        if (art != null && art.isNotEmpty) {
          final withArt = track.copyWith(thumbnailUrl: art);
          if (_currentTrack?.id == track.id) {
            _currentTrack = _currentTrack!.copyWith(thumbnailUrl: art);
          }
          _updateTrackInQueue(withArt);
          _updateAllMatchingTrackArtworks(track.artist, track.title, art);
        }
      });
    }

    // Check lyrics immediately the moment song is played
    _hasSyncedLyrics = false;
    _currentLyrics = [];
    _isLoadingLyrics = true;
    notifyListeners();
    _checkLyricsForTrack(track);

    // 1. If Hi-Fi is disabled, stream strictly via YouTube
    if (!_isHifiEnabled) {
      final vId = track.youtubeVideoId ?? track.id;
      final ytStreamUrl = await _ytResolver.getAudioStreamUrl(vId);

      if (ytStreamUrl != null && ytStreamUrl.isNotEmpty) {
        final ytTrack = track.copyWith(
          flacStreamUrl: ytStreamUrl,
          audioSource: 'youtube',
          isLossless: false,
          audioFormat: 'YouTube Audio (160kbps)',
        );
        _currentTrack = ytTrack;
        _updateTrackInQueue(ytTrack);
        notifyListeners();
        await _playStream(ytStreamUrl);
      } else {
        _playbackError = !isOnline
            ? 'No internet connection. Reconnect to stream.'
            : 'Unable to stream "${track.title}". Tap to retry.';
        _isBuffering = false;
        notifyListeners();
      }
      _triggerEndlessPlayIfNeeded();
      return;
    }

    // 2. If already elevated to Hi-Fi with a direct stream URL
    if (track.flacStreamUrl != null && track.flacStreamUrl!.isNotEmpty && track.isLossless) {
      await _playStream(track.flacStreamUrl!);
      _triggerEndlessPlayIfNeeded();
      return;
    }

    // 3. Trigger Hi-Fi Checker
    _isHifiResolving = true;
    notifyListeners();

    // Check Hi-Fi: Kuwo (Top Priority) -> Monochrome (Fallback) -> YouTube (Final Fallback)
    final hifiTrack = await _hifiMatcher.matchToHifi(track);
    _isHifiResolving = false;

    if (hifiTrack != null && hifiTrack.flacStreamUrl != null) {
      // Elevated to Hi-Fi FLAC
      _currentTrack = hifiTrack;
      _updateTrackInQueue(hifiTrack);
      notifyListeners();
      await _playStream(hifiTrack.flacStreamUrl!);
    } else {
      // Fallback: YouTube direct audio extraction
      final vId = track.youtubeVideoId ?? track.id;
      final ytStreamUrl = await _ytResolver.getAudioStreamUrl(vId);

      if (ytStreamUrl != null && ytStreamUrl.isNotEmpty) {
        final ytTrack = track.copyWith(
          flacStreamUrl: ytStreamUrl,
          audioSource: 'youtube',
          isLossless: false,
          audioFormat: 'YouTube Audio (160kbps)',
        );
        _currentTrack = ytTrack;
        _updateTrackInQueue(ytTrack);
        notifyListeners();
        await _playStream(ytStreamUrl);
      } else {
        _playbackError = !isOnline
            ? 'No internet connection. Reconnect to stream.'
            : 'Unable to stream "${track.title}". Tap to retry.';
        _isBuffering = false;
        notifyListeners();
      }
    }

    _triggerEndlessPlayIfNeeded();
  }

  Future<void> _playStream(String url) async {
    try {
      await _audioPlayer.setUrl(url);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play();
    } catch (e) {
      _playbackError = !isOnline
          ? 'Connection lost while streaming. Tap to retry.'
          : 'Playback error: audio unavailable. Tap to retry.';
      _isBuffering = false;
      notifyListeners();
    }
  }

  void _updateTrackInQueue(Track updated) {
    final idx = _queue.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      _queue[idx] = updated;
    }
  }

  /// Condition 2: When songs are added to the queue
  void addToQueue(Track track) {
    _queue.add(track);
    _persistPlayerState();
    notifyListeners();
    _resolveTrackHiFiInBackground(track);
  }

  void addTracksToQueue(List<Track> tracks) {
    _queue.addAll(tracks);
    _persistPlayerState();
    notifyListeners();
    _resolveQueueHiFiInBackground();
  }

  void _resolveQueueHiFiInBackground() {
    if (!_isHifiEnabled) return;
    for (final track in _queue) {
      if (track.flacStreamUrl == null || !track.isLossless) {
        _resolveTrackHiFiInBackground(track);
      }
    }
  }

  void _resolveTrackHiFiInBackground(Track track) {
    if (!_isHifiEnabled) return;
    _hifiMatcher.matchToHifi(track).then((hifi) {
      if (hifi != null) {
        _updateTrackInQueue(hifi);
        if (_currentTrack?.id == track.id) {
          _currentTrack = hifi;
        }
        notifyListeners();
      }
    });
  }

  /// Endless Play (Radio Mode) using nadanada Vibe & Genre algorithm
  Future<void> _fetchAndQueueVibeTracks() async {
    if (_isFetchingEndless || _queue.isEmpty) return;
    _isFetchingEndless = true;
    notifyListeners();
    try {
      final nextTrack = await _vibeService.getNextVibeTrack(
        queue: _queue,
        currentIndex: _currentIndex,
      );
      if (nextTrack != null &&
          !_queue.any((q) =>
              (q.youtubeVideoId ?? q.id) ==
              (nextTrack.youtubeVideoId ?? nextTrack.id))) {
        _queue.add(nextTrack);
        notifyListeners();
        _resolveTrackHiFiInBackground(nextTrack);

        // Pre-fetch a second vibe track so there is always a buffer
        final secondTrack = await _vibeService.getNextVibeTrack(
          queue: _queue,
          currentIndex: _currentIndex,
        );
        if (secondTrack != null &&
            !_queue.any((q) =>
                (q.youtubeVideoId ?? q.id) ==
                (secondTrack.youtubeVideoId ?? secondTrack.id))) {
          _queue.add(secondTrack);
          notifyListeners();
          _resolveTrackHiFiInBackground(secondTrack);
        }
      }
    } catch (_) {
    } finally {
      _isFetchingEndless = false;
      notifyListeners();
    }
  }

  void _triggerEndlessPlayIfNeeded() {
    if (!_isEndlessPlay || _isFetchingEndless || _queue.isEmpty) return;
    if (_queue.length - 1 - _currentIndex <= 2) {
      _fetchAndQueueVibeTracks();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_audioPlayer.audioSource != null) {
        await _audioPlayer.play();
      } else if (_currentTrack != null) {
        playTrack(_currentTrack!);
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    _position = position;
    notifyListeners();
    try {
      await _audioPlayer.seek(position);
    } catch (_) {}
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_repeatMode == 2) {
      seekTo(Duration.zero);
      return;
    }
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await playTrack(_queue[_currentIndex]);
      return;
    }

    // Reached the end of the queue
    if (_isEndlessPlay) {
      if (!_isFetchingEndless) {
        await _fetchAndQueueVibeTracks();
      } else {
        int waitCount = 0;
        while (_isFetchingEndless && waitCount < 30) {
          await Future.delayed(const Duration(milliseconds: 150));
          waitCount++;
        }
      }

      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        await playTrack(_queue[_currentIndex]);
        return;
      }
    }

    if (_repeatMode == 1 && _queue.isNotEmpty) {
      _currentIndex = 0;
      await playTrack(_queue[_currentIndex]);
    } else {
      await _audioPlayer.stop();
      _isPlaying = false;
      notifyListeners();
    }
  }

  void previous() {
    if (_queue.isEmpty) return;
    if (_position.inSeconds > 4) {
      seekTo(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex - 1 + _queue.length) % _queue.length;
    playTrack(_queue[_currentIndex]);
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    notifyListeners();
  }

  void toggleRepeat() {
    _repeatMode = (_repeatMode + 1) % 3;
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = 0;
      }
      _persistPlayerState();
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _persistPlayerState();
    notifyListeners();
  }

  void clearQueue() {
    if (_currentTrack != null) {
      _queue = [_currentTrack!];
      _currentIndex = 0;
      _persistPlayerState();
      notifyListeners();
    }
  }

  Future<void> retryLyrics() async {
    if (_currentTrack != null) {
      _isLoadingLyrics = true;
      _currentLyrics = [];
      _hasSyncedLyrics = false;
      notifyListeners();
      await _checkLyricsForTrack(_currentTrack!);
    }
  }

  Future<void> _checkLyricsForTrack(Track track) async {
    try {
      final lyrics = await _lyricsService.fetchLyrics(
        trackName: track.title,
        artistName: track.artist,
        durationSeconds: track.durationSeconds,
        youtubeVideoId: track.youtubeVideoId,
      );
      if (_currentTrack?.id == track.id) {
        _currentLyrics = lyrics;
        _hasSyncedLyrics = lyrics.isNotEmpty;
        _isLoadingLyrics = false;
        notifyListeners();
      }
    } catch (_) {
      if (_currentTrack?.id == track.id) {
        _currentLyrics = [];
        _hasSyncedLyrics = false;
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryCurrentTrack() async {
    _playbackError = null;
    notifyListeners();
    await ConnectivityService().checkConnectivity();
    if (_currentTrack != null) {
      await playTrack(_currentTrack!);
    }
  }

  void clearPlaybackError() {
    _playbackError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _connectivitySub?.cancel();
    ConnectivityService().stopMonitoring();
    _audioPlayer.dispose();
    _ytResolver.dispose();
    super.dispose();
  }
}
