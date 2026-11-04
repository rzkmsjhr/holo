import 'dart:async';
import 'dart:convert';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_mix.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/trending_track.dart';
import '../services/artwork_service.dart';
import '../services/audio_handler.dart';
import '../services/connectivity_service.dart';
import '../services/flac_cache_service.dart';
import '../services/hifi_matcher.dart';
import '../services/kworb_data_snapshot.dart';
import '../services/lyrics_service.dart';
import '../services/playlist_service.dart';
import '../services/taste_profile_service.dart';
import '../services/trending_service.dart';
import '../services/vibe_recommendation_service.dart';
import '../services/youtube_music_service.dart';
import '../services/youtube_stream_resolver.dart';
import '../services/yt_iframe_bridge.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final YouTubeIframeBridge _ytIframeBridge = YouTubeIframeBridge();
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
  bool _isUsingYtIframe = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<int> debugLogsVersion = ValueNotifier(0);
  List<Track> _queue = [];
  int _queueEntrySeq = 0;

  Track _tagQueueEntry(Track track) {
    if (track.extraData?['queue_entry_id'] != null) {
      return track;
    }
    final token =
        'q_${track.id}_${DateTime.now().microsecondsSinceEpoch}_${++_queueEntrySeq}';
    return track.copyWith(
      extraData: {
        ...?track.extraData,
        'queue_entry_id': token,
      },
    );
  }
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
  String? _recentPlaylistId;
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
  bool _hasTrackCompleted = false;
  bool _isTransitioningTrack = false;
  String? _activePlaybackTrackKey;
  DateTime? _lastTrackChangeTime;

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
  StreamSubscription? _ytPosSub;
  StreamSubscription? _ytDurSub;
  StreamSubscription? _ytStateSub;
  StreamSubscription? _ytErrSub;

  // Candidate fallback recovery state
  bool _isAttemptingCandidateFallback = false;
  final Set<String> _failedCandidateIdsForTrack = {};
  String? _failedTrackKey;

  // Real-time debugger and diagnostic logs
  final List<String> _debugLogs = [];
  List<String> get debugLogs => List.unmodifiable(_debugLogs);

  void logDebug(String message) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$time] $message';
    _debugLogs.add(entry);
    if (_debugLogs.length > 250) {
      _debugLogs.removeAt(0);
    }
    debugPrint(entry);
    debugLogsVersion.value++;
  }

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
  String? get recentPlaylistId => _recentPlaylistId;
  Playlist? get recentPlaylist {
    if (_playlists == null || _playlists!.isEmpty) return null;
    if (_recentPlaylistId != null) {
      final found =
          _playlists!.where((p) => p.id == _recentPlaylistId).firstOrNull;
      if (found != null) return found;
    }
    final sorted = List<Playlist>.from(_playlists!)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.first;
  }

  static const String _recentPlaylistKey = 'holo_recent_playlist_id';
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
    _ytResolver.onLog = logDebug;
    _ytIframeBridge.onLog = logDebug;
    logDebug('Pulse Audio Player initialized. Diagnostic logging active.');
    _initMediaNotificationHandler();
    _initConnectivity();
    _initAudioListeners();
    _initHifiMatcher();
    _initFlacCache();
    _initSavedPlayerState();
    _initPlaylists();
    _initLikedTracks();

    // Stagger background network & heavy indexing tasks after initial frame render
    _startupTimer = Timer(const Duration(milliseconds: 350), () {
      _initTasteAndMixes();
      _initTrending();
      _initArtworkService();
    });
  }

  Timer? _startupTimer;
  final Set<String> _preResolvingIds = {};
  int _lastNotifiedSec = -1;

  void _initMediaNotificationHandler() {
    final handler = HoloAudioServiceManager.handler;
    handler.onPlay = () {
      if (!_isPlaying) togglePlayPause();
    };
    handler.onPause = () {
      if (_isPlaying) togglePlayPause();
    };
    handler.onSkipToNext = () => next();
    handler.onSkipToPrevious = () => previous();
    handler.onSeek = (pos) => seekTo(pos);
    handler.onStop = () async {
      await stopPlayback();
    };
  }

  void _initHifiMatcher() async {
    await _hifiMatcher.init();
    if (_currentTrack != null && !_currentTrack!.isLossless) {
      final hifi = _hifiMatcher.getCachedHiFi(_currentTrack!);
      if (hifi != null) {
        _currentTrack = hifi;
        notifyListeners();
      }
    }
  }

  void _initFlacCache() async {
    await FlacCacheService().init();
  }

  void _syncNotificationMediaItem([Track? track]) {
    final t = track ?? _currentTrack;
    if (t == null) return;
    final cachedArt = getArtwork(t.artist, t.title);
    HoloAudioServiceManager.handler.updateTrackMediaItem(
      t,
      resolvedArtworkUrl: cachedArt,
      duration: _duration.inSeconds > 0 ? _duration : null,
    );
  }

  void _syncNotificationPlaybackState() {
    final effectivePlaying = _isPlaying || _isTransitioningTrack;
    final effectiveBuffering = _isBuffering || _isTransitioningTrack;
    HoloAudioServiceManager.handler.syncPlaybackState(
      isPlaying: effectivePlaying,
      isBuffering: effectiveBuffering,
      position: _position,
      bufferedPosition: _audioPlayer.bufferedPosition,
    );
  }

  void _initConnectivity() {
    final connectivity = ConnectivityService();
    connectivity.startMonitoring();
    _connectivitySub = connectivity.statusStream.listen((status) {
      if (status == ConnectivityStatus.online && _playbackError != null) {
        if (_playbackError!.contains('connection') ||
            _playbackError!.contains('internet') ||
            _playbackError!.contains('timed out')) {
          _playbackError = null;
          if (_currentTrack != null && !_isPlaying) {
            playTrack(_currentTrack!);
          }
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
            .map(_sanitizeTrack)
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
    try {
      final prefs = await SharedPreferences.getInstance();
      _recentPlaylistId = prefs.getString(_recentPlaylistKey);
    } catch (_) {}
    await loadPlaylists();
  }

  void _initAudioListeners() async {
    try {
      await _audioPlayer.setVolume(1.0);
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    _posSub = _audioPlayer.positionStream.listen((pos) {
      if (_isUsingYtIframe) return;
      _position = pos;
      positionNotifier.value = pos;
      if (pos.inSeconds != _lastNotifiedSec) {
        _lastNotifiedSec = pos.inSeconds;
        _syncNotificationPlaybackState();
        notifyListeners();
      }
    });

    _durSub = _audioPlayer.durationStream.listen((dur) {
      if (_isUsingYtIframe) return;
      if (dur != null) {
        _duration = dur;
        _syncNotificationMediaItem();
        notifyListeners();
      }
    });

    _stateSub = _audioPlayer.playerStateStream.listen((state) {
      if (_isUsingYtIframe) return;
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompletion();
        return;
      }
      _isPlaying = state.playing;
      _isBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      if (_isPlaying) {
        ConnectivityService().markOnline();
      }
      _syncNotificationPlaybackState();
      notifyListeners();
    });

    _eventSub = _audioPlayer.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        if (_isUsingYtIframe) return;
        logDebug('playbackEventStream onError: $e');
        _handlePlaybackFailure(e);
      },
    );

    // Cloudflare Worker YouTube IFrame Bridge listeners (Web)
    _ytPosSub = _ytIframeBridge.positionStream.listen((pos) {
      if (!_isUsingYtIframe) return;
      _position = pos;
      positionNotifier.value = pos;
      if (pos.inSeconds != _lastNotifiedSec) {
        _lastNotifiedSec = pos.inSeconds;
        notifyListeners();
      }
    });

    _ytDurSub = _ytIframeBridge.durationStream.listen((dur) {
      if (!_isUsingYtIframe) return;
      if (dur.inSeconds > 0) {
        _duration = dur;
        notifyListeners();
      }
    });

    _ytStateSub = _ytIframeBridge.stateStream.listen((stateCode) {
      if (!_isUsingYtIframe) return;
      if (stateCode == 1) {
        // Playing
        _isPlaying = true;
        _isBuffering = false;
        _playbackError = null;
        notifyListeners();
      } else if (stateCode == 2) {
        // Paused
        _isPlaying = false;
        _isBuffering = false;
        notifyListeners();
      } else if (stateCode == 3) {
        // Buffering
        _isBuffering = true;
        notifyListeners();
      } else if (stateCode == 0) {
        // Ended
        _isPlaying = false;
        _isBuffering = false;
        _handleTrackCompletion();
        notifyListeners();
      }
    });

    _ytErrSub = _ytIframeBridge.errorStream.listen((errCode) {
      if (!_isUsingYtIframe) return;
      logDebug('YouTubeIframeBridge error code: $errCode');
      _handlePlaybackFailure('YouTube IFrame error $errCode');
    });
  }

  void _handleTrackCompletion() {
    if (_hasTrackCompleted || _isTransitioningTrack) {
      logDebug('_handleTrackCompletion: duplicate or in-transition completion event ignored.');
      return;
    }
    final currentKey = _currentTrack != null
        ? '${_currentTrack!.id}_${_currentTrack!.title}'
        : null;
    if (currentKey == null || _activePlaybackTrackKey != currentKey) {
      logDebug('_handleTrackCompletion: ignoring stale completion event for non-active track key');
      return;
    }
    _hasTrackCompleted = true;
    _isTransitioningTrack = true;
    _syncNotificationPlaybackState();
    logDebug('_handleTrackCompletion: current track finished. Advancing to next track...');
    next(isAutoAdvance: true);
  }

  Track _sanitizeTrack(Track t) {
    if (!HifiMatcher.isEligibleTrack(t)) {
      return t.copyWith(
        flacStreamUrl: null,
        audioSource: 'youtube',
        isLossless: false,
        audioFormat: 'YouTube Audio (160kbps)',
      );
    }
    final v = t.extraData?['hifiVersion'];
    if (t.isLossless && (v == null || v != HifiMatcher.matcherVersion)) {
      return t.copyWith(
        flacStreamUrl: null,
        audioSource: 'youtube',
        isLossless: false,
        audioFormat: 'YouTube Audio (160kbps)',
      );
    }
    return t;
  }

  void _initSavedPlayerState() async {
    _queue = [];
    _currentTrack = null;
    _recentlyPlayed = [];

    Track restoreTrack(Track raw) {
      return _hifiMatcher.prepareTrackThroughGateSync(
        raw,
        isHifiEnabled: _isHifiEnabled,
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Restore recently played
      final savedRecent = prefs.getString(_recentlyPlayedKey);
      if (savedRecent != null && savedRecent.isNotEmpty) {
        final List<dynamic> list = jsonDecode(savedRecent);
        _recentlyPlayed = list
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .map(restoreTrack)
            .toList();
      }

      // 2. Restore playing queue & index
      final savedQueue = prefs.getString(_lastQueueKey);
      if (savedQueue != null && savedQueue.isNotEmpty) {
        final List<dynamic> list = jsonDecode(savedQueue);
        _queue = list
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .map(restoreTrack)
            .map(_tagQueueEntry)
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
        final track = restoreTrack(Track.fromJson(trackJson));
        _currentTrack = track;
        _duration = Duration(seconds: track.durationSeconds);
        _position = Duration.zero;
        positionNotifier.value = Duration.zero;
        _isPlaying = false;
      } else if (_queue.isNotEmpty && _currentIndex < _queue.length) {
        _currentTrack = _queue[_currentIndex];
        _duration = Duration(seconds: _currentTrack!.durationSeconds);
        _position = Duration.zero;
        positionNotifier.value = Duration.zero;
        _isPlaying = false;
      }

      notifyListeners();
    } catch (_) {}
  }

  Timer? _persistDebounce;
  void _persistPlayerState() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () async {
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
    });
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

  void _updateRecentlyPlayed(Track updated) {
    if (_recentlyPlayed == null) return;
    final idx = _recentlyPlayed!.indexWhere((t) =>
        (t.youtubeVideoId ?? t.id) == (updated.youtubeVideoId ?? updated.id) ||
        (t.title.toLowerCase().trim() == updated.title.toLowerCase().trim() &&
            t.artist.toLowerCase().trim() == updated.artist.toLowerCase().trim()));
    if (idx != -1) {
      _recentlyPlayed![idx] = updated;
      _persistPlayerState();
      notifyListeners();
    }
  }

  void _updateAllMatchingTrackArtworks(
      String artist, String title, String art) {
    if (art.isEmpty) return;
    final matchA = ArtworkService.cleanForMatching(artist);
    final matchT = ArtworkService.cleanForMatching(title);
    final cleanA = artist.toLowerCase().trim();
    final cleanT = title.toLowerCase().trim();

    bool isMatch(String a, String t) {
      final aLower = a.toLowerCase().trim();
      final tLower = t.toLowerCase().trim();
      if (aLower == cleanA && tLower == cleanT) return true;
      return ArtworkService.cleanForMatching(a) == matchA &&
          ArtworkService.cleanForMatching(t) == matchT;
    }

    bool changed = false;

    if (_currentTrack != null &&
        isMatch(_currentTrack!.artist, _currentTrack!.title) &&
        (_currentTrack!.thumbnailUrl.isEmpty ||
            _currentTrack!.thumbnailUrl.contains('unsplash.com') ||
            _currentTrack!.thumbnailUrl.contains('maxresdefault.jpg'))) {
      _currentTrack = _currentTrack!.copyWith(thumbnailUrl: art);
      _syncNotificationMediaItem(_currentTrack);
      changed = true;
    }

    if (_recentlyPlayed != null) {
      for (var i = 0; i < _recentlyPlayed!.length; i++) {
        final t = _recentlyPlayed![i];
        if (isMatch(t.artist, t.title) &&
            (t.thumbnailUrl.isEmpty ||
                t.thumbnailUrl.contains('unsplash.com') ||
                t.thumbnailUrl.contains('maxresdefault.jpg'))) {
          _recentlyPlayed![i] = t.copyWith(thumbnailUrl: art);
          changed = true;
        }
      }
    }

    for (var i = 0; i < _queue.length; i++) {
      final t = _queue[i];
      if (isMatch(t.artist, t.title) &&
          (t.thumbnailUrl.isEmpty ||
              t.thumbnailUrl.contains('unsplash.com') ||
              t.thumbnailUrl.contains('maxresdefault.jpg'))) {
        _queue[i] = t.copyWith(thumbnailUrl: art);
        changed = true;
      }
    }

    for (var i = 0; i < _likedTracks.length; i++) {
      final t = _likedTracks[i];
      if (isMatch(t.artist, t.title) &&
          (t.thumbnailUrl.isEmpty ||
              t.thumbnailUrl.contains('unsplash.com') ||
              t.thumbnailUrl.contains('maxresdefault.jpg'))) {
        _likedTracks[i] = t.copyWith(thumbnailUrl: art);
        changed = true;
      }
    }

    if (_globalTrending != null) {
      for (var i = 0; i < _globalTrending!.length; i++) {
        final t = _globalTrending![i];
        if (isMatch(t.artist, t.title) &&
            (t.thumbnailUrl == null ||
                t.thumbnailUrl!.isEmpty ||
                t.thumbnailUrl!.contains('unsplash.com') ||
                t.thumbnailUrl!.contains('maxresdefault.jpg'))) {
          _globalTrending![i] = t.copyWith(thumbnailUrl: art);
          changed = true;
        }
      }
    }

    if (_indonesiaTrending != null) {
      for (var i = 0; i < _indonesiaTrending!.length; i++) {
        final t = _indonesiaTrending![i];
        if (isMatch(t.artist, t.title) &&
            (t.thumbnailUrl == null ||
                t.thumbnailUrl!.isEmpty ||
                t.thumbnailUrl!.contains('unsplash.com') ||
                t.thumbnailUrl!.contains('maxresdefault.jpg'))) {
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
    final gated = _hifiMatcher.prepareTrackThroughGateSync(
      track,
      isHifiEnabled: _isHifiEnabled,
    );
    final tId = gated.youtubeVideoId ?? gated.id;
    final isAlreadyFav = isFavorite(tId);
    final nowFav = !isAlreadyFav;

    if (nowFav) {
      if (!_likedTracks.any((t) => (t.youtubeVideoId ?? t.id) == tId)) {
        _likedTracks.insert(0, gated);
      }
    } else {
      _likedTracks.removeWhere((t) => (t.youtubeVideoId ?? t.id) == tId);
    }

    _tasteProfile.recordFavorite(gated, nowFav);
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

  Track? getCachedHiFi(Track track) => _hifiMatcher.getCachedHiFi(track);

  int _queueLoadGeneration = 0;

  /// Unified Pre-Queue FLAC Resolution Gate
  /// Ensures any track is verified and elevated to FLAC before being queued.
  Future<Track> _resolveTrackForQueue(Track rawTrack) async {
    final gated = _hifiMatcher.prepareTrackThroughGateSync(
      rawTrack,
      isHifiEnabled: _isHifiEnabled,
    );
    if (gated.isLossless &&
        gated.flacStreamUrl != null &&
        gated.flacStreamUrl!.isNotEmpty) {
      return gated;
    }
    if (_isHifiEnabled && HifiMatcher.isEligibleTrack(gated)) {
      try {
        final matched = await _hifiMatcher.matchToHifi(gated).timeout(
          const Duration(milliseconds: 3500),
          onTimeout: () => null,
        );
        if (matched != null &&
            matched.flacStreamUrl != null &&
            matched.flacStreamUrl!.isNotEmpty) {
          return matched;
        }
      } catch (_) {}
    }
    return gated;
  }

  /// Loads and plays a list of tracks (Daily Mix, Playlist, or Track list),
  /// gating all tracks synchronously so the full queue is immediately visible in UI,
  /// eagerly resolving the starting track for FLAC, and progressively draining FLAC
  /// for the remainder of the queue in priority tiers without blocking UI.
  Future<void> _loadAndPlayTrackList(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    final generation = ++_queueLoadGeneration;
    final idx = startIndex.clamp(0, tracks.length - 1);

    // 1. Synchronously gate all tracks upfront: sanitizes titles, version check, attaches cached FLAC
    final gatedTracks = tracks
        .map((t) => _hifiMatcher.prepareTrackThroughGateSync(
              t,
              isHifiEnabled: _isHifiEnabled,
            ))
        .map(_tagQueueEntry)
        .toList();

    _queue = gatedTracks;
    _currentIndex = idx;
    _currentTrack = gatedTracks[idx];
    _isBuffering = true;
    _isHifiResolving = true;
    notifyListeners();

    // 2. Eagerly resolve selected starting track for FLAC if not already cached
    final startTrack = gatedTracks[idx];
    final resolvedStart = await _resolveTrackForQueue(startTrack);
    if (generation != _queueLoadGeneration) return;

    final existingKey = _queue[idx].queueEntryId;
    final resolvedWithKey = resolvedStart.copyWith(
      extraData: {
        ...?resolvedStart.extraData,
        'queue_entry_id': existingKey,
      },
    );
    _queue[idx] = resolvedWithKey;
    _currentTrack = resolvedWithKey;
    _persistPlayerState();
    notifyListeners();
    unawaited(playTrack(resolvedStart));

    // 3. Trigger 3-Tier Progressive Queue Drain for remaining tracks
    _scheduleProgressiveQueueDrain(generation);
  }

  void playDailyMix(DailyMix mix, [int startIndex = 0]) {
    _loadAndPlayTrackList(mix.tracks, startIndex);
  }

  Future<void> refreshDailyMixes() async {
    if (_isLoadingMixes == true) return;
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
    if (_isLoadingTrending == true) return;
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
    final gated = _hifiMatcher.prepareTrackThroughGateSync(
      track,
      isHifiEnabled: _isHifiEnabled,
    );
    final success =
        await _playlistService.addTrackToPlaylist(playlistId, gated);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
    return success;
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    await _playlistService.removeTrackFromPlaylist(playlistId, trackId);
    _playlists = await _playlistService.loadPlaylists(sampleCatalog: _queue);
    notifyListeners();
    return;
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (_recentPlaylistId == playlistId) {
      _recentPlaylistId = null;
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(_recentPlaylistKey);
      }).catchError((_) {});
    }
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
    _recentPlaylistId = playlist.id;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_recentPlaylistKey, playlist.id);
    }).catchError((_) {});
    _loadAndPlayTrackList(playlist.tracks, startIndex);
  }

  void playTrackList(List<Track> tracks, [int startIndex = 0]) {
    _loadAndPlayTrackList(tracks, startIndex);
  }

  void shuffleTrackList(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks)..shuffle();
    _loadAndPlayTrackList(shuffled, 0);
  }

  Future<void> playNext(Track track) async {
    final resolved = _tagQueueEntry(await _resolveTrackForQueue(track));
    if (_queue.isEmpty) {
      _queue.add(resolved);
      _currentIndex = 0;
      await playTrack(resolved);
      return;
    }
    final nextIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(nextIdx, resolved);
    _persistPlayerState();
    notifyListeners();
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
  }

  /// Condition 1: When a track is going to be played (at all states)
  Future<void> playTrack(Track track) async {
    _isAttemptingCandidateFallback = false;
    _failedCandidateIdsForTrack.clear();
    _failedTrackKey = null;
    _hasTrackCompleted = true;
    _isTransitioningTrack = true;

    if (!_isUsingYtIframe && _audioPlayer.processingState == ProcessingState.completed) {
      try {
        await _audioPlayer.stop();
      } catch (_) {}
    }

    var sanitizedTrack = _hifiMatcher.prepareTrackThroughGateSync(
      track,
      isHifiEnabled: _isHifiEnabled,
    );
    logDebug('playTrack: "${sanitizedTrack.title}" by "${sanitizedTrack.artist}" (id: ${sanitizedTrack.id}, ytVideoId: ${sanitizedTrack.youtubeVideoId})');
    _currentTrack = sanitizedTrack;
    _addToRecentlyPlayed(sanitizedTrack);
    _tasteProfile.recordPlay(sanitizedTrack);
    _playbackError = null;
    final trackId = sanitizedTrack.youtubeVideoId ?? sanitizedTrack.id;
    final foundIndex = _queue.indexWhere((t) =>
        t.id == sanitizedTrack.id ||
        (t.youtubeVideoId != null && t.youtubeVideoId == trackId));
    if (foundIndex != -1) {
      _currentIndex = foundIndex;
      _currentTrack = _queue[foundIndex];
    } else {
      // New song selected from outside queue: seed a fresh queue around this track
      final tagged = _tagQueueEntry(sanitizedTrack);
      _queue = [tagged];
      _currentIndex = 0;
      _currentTrack = tagged;
    }
    _persistPlayerState();
    _triggerEndlessPlayIfNeeded();
    _duration = Duration(seconds: sanitizedTrack.durationSeconds);
    _position = Duration.zero;
    positionNotifier.value = Duration.zero;
    _isBuffering = true;

    _syncNotificationMediaItem(sanitizedTrack);
    _syncNotificationPlaybackState();

    // Resolve missing artwork in background
    if (sanitizedTrack.thumbnailUrl.isEmpty) {
      _artworkService.getArtwork(sanitizedTrack.artist, sanitizedTrack.title).then((art) {
        if (art != null && art.isNotEmpty) {
          final withArt = sanitizedTrack.copyWith(thumbnailUrl: art);
          if (_currentTrack?.id == sanitizedTrack.id) {
            _currentTrack = _currentTrack!.copyWith(thumbnailUrl: art);
            _syncNotificationMediaItem(_currentTrack);
          }
          _updateTrackInQueue(withArt);
          _updateRecentlyPlayed(withArt);
          _updateAllMatchingTrackArtworks(sanitizedTrack.artist, sanitizedTrack.title, art);
        }
      });
    } else {
      resolveArtworkFor(sanitizedTrack.artist, sanitizedTrack.title);
    }

    // Check lyrics: load instantly from memory/disk cache if available
    final cachedLyrics =
        _lyricsService.getCachedSync(sanitizedTrack.title, sanitizedTrack.artist);
    if (cachedLyrics != null && cachedLyrics.isNotEmpty) {
      _currentLyrics = cachedLyrics;
      _hasSyncedLyrics = true;
      _isLoadingLyrics = false;
      notifyListeners();
    } else {
      _hasSyncedLyrics = false;
      _currentLyrics = [];
      _isLoadingLyrics = true;
      notifyListeners();
      _checkLyricsForTrack(sanitizedTrack);
    }

    // 1. Instant 0ms playback if track already has a resolved stream URL
    if (sanitizedTrack.flacStreamUrl != null &&
        sanitizedTrack.flacStreamUrl!.isNotEmpty &&
        (_isHifiEnabled ? sanitizedTrack.isLossless || sanitizedTrack.audioSource == 'youtube' : !sanitizedTrack.isLossless)) {
      await _playStream(sanitizedTrack.flacStreamUrl!, fallbackYtTrack: sanitizedTrack);
      _triggerEndlessPlayIfNeeded();
      _preResolveUpcomingQueue();
      return;
    }

    final vId = sanitizedTrack.youtubeVideoId ?? sanitizedTrack.id;

    // 2. If Hi-Fi is disabled, stream strictly via YouTube
    if (!_isHifiEnabled) {
      final ytRes = await _ytResolver.resolveStreamForTrack(
        title: sanitizedTrack.title,
        artist: sanitizedTrack.artist,
        primaryVideoId: vId,
      );

      if (ytRes.isSuccess && ytRes.url != null) {
        final ytTrack = sanitizedTrack.copyWith(
          youtubeVideoId: ytRes.videoId ?? vId,
          flacStreamUrl: ytRes.url,
          audioSource: 'youtube',
          isLossless: false,
          audioFormat: 'YouTube Audio (160kbps)',
        );
        _currentTrack = ytTrack;
        _updateTrackInQueue(ytTrack);
        _updateRecentlyPlayed(ytTrack);
        notifyListeners();
        await _playStream(ytRes.url!, fallbackYtTrack: ytTrack);
      } else {
        final online = await ConnectivityService().checkConnectivity();
        _playbackError = !online
            ? 'No internet connection. Reconnect to stream.'
            : (ytRes.errorMessage ?? 'Unable to find a playable stream for "${sanitizedTrack.title}". Tap to retry.');
        _isBuffering = false;
        _syncNotificationPlaybackState();
        notifyListeners();
      }
      _triggerEndlessPlayIfNeeded();
      _preResolveUpcomingQueue();
      return;
    }

    // 3. Concurrent Parallel Resolution: resolve Hi-Fi FLAC and YouTube fallback simultaneously
    _isHifiResolving = true;
    notifyListeners();

    final hifiFuture = _hifiMatcher.matchToHifi(sanitizedTrack);
    final ytFuture = _ytResolver.resolveStreamForTrack(
      title: sanitizedTrack.title,
      artist: sanitizedTrack.artist,
      primaryVideoId: vId,
    );

    final hifiTrack = await hifiFuture.timeout(
      const Duration(milliseconds: 7000),
      onTimeout: () => null,
    );
    _isHifiResolving = false;

    if (hifiTrack != null && hifiTrack.flacStreamUrl != null) {
      // Elevated to Hi-Fi FLAC
      _currentTrack = hifiTrack;
      _updateTrackInQueue(hifiTrack);
      _updateRecentlyPlayed(hifiTrack);
      _persistPlayerState();
      _syncNotificationMediaItem(hifiTrack);
      notifyListeners();
      await _playStream(hifiTrack.flacStreamUrl!, fallbackYtTrack: sanitizedTrack);
    } else {
      // If Hi-Fi finished later, cache it for replay
      hifiFuture.then((lateHifi) {
        if (lateHifi != null && lateHifi.flacStreamUrl != null) {
          _updateTrackInQueue(lateHifi);
          _updateRecentlyPlayed(lateHifi);
          _persistPlayerState();
        }
      }).catchError((_) {});

      // Immediate fallback: YouTube stream was already resolving in parallel!
      final ytRes = await ytFuture;

      if (ytRes.isSuccess && ytRes.url != null) {
        final ytTrack = sanitizedTrack.copyWith(
          youtubeVideoId: ytRes.videoId ?? vId,
          flacStreamUrl: ytRes.url,
          audioSource: 'youtube',
          isLossless: false,
          audioFormat: 'YouTube Audio (160kbps)',
        );
        _currentTrack = ytTrack;
        _updateTrackInQueue(ytTrack);
        _updateRecentlyPlayed(ytTrack);
        _syncNotificationMediaItem(ytTrack);
        notifyListeners();
        await _playStream(ytRes.url!, fallbackYtTrack: ytTrack);
      } else {
        final online = await ConnectivityService().checkConnectivity();
        _playbackError = !online
            ? 'No internet connection. Reconnect to stream.'
            : (ytRes.errorMessage ?? 'Unable to find a playable stream for "${sanitizedTrack.title}". Tap to retry.');
        _isBuffering = false;
        _syncNotificationPlaybackState();
        notifyListeners();
      }
    }

    _triggerEndlessPlayIfNeeded();
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
  }

  bool _needsHifiResolution(Track track) {
    if (!_isHifiEnabled) return false;
    if (!HifiMatcher.isEligibleTrack(track)) return false;
    if (track.isLossless &&
        track.flacStreamUrl != null &&
        track.flacStreamUrl!.isNotEmpty) {
      return false;
    }
    if (_hifiMatcher.isUnmatched(track)) return false;
    return true;
  }

  Future<void> _drainSingleTrack(Track track, int generation) async {
    if (generation != _queueLoadGeneration) return;
    final key = track.youtubeVideoId ?? track.id;
    if (_preResolvingIds.contains(key)) return;
    _preResolvingIds.add(key);

    try {
      if (_needsHifiResolution(track)) {
        final hifi = await _hifiMatcher.matchToHifi(track);
        if (generation != _queueLoadGeneration) return;
        if (hifi != null && hifi.flacStreamUrl != null) {
          _updateTrackInQueue(hifi);
          _updateRecentlyPlayed(hifi);
          if (_currentTrack?.id == track.id) {
            _currentTrack = hifi;
          }
          notifyListeners();
          return;
        }
      }

      // Pre-resolve stream URL for instant offline / screen-off transition if needed
      if (track.flacStreamUrl == null || track.flacStreamUrl!.isEmpty) {
        final ytRes = await _ytResolver.resolveStreamForTrack(
          title: track.title,
          artist: track.artist,
          primaryVideoId: key,
        );
        if (generation != _queueLoadGeneration) return;
        if (ytRes.isSuccess && ytRes.url != null) {
          final ytTrack = track.copyWith(
            youtubeVideoId: ytRes.videoId ?? key,
            flacStreamUrl: ytRes.url,
            audioSource: 'youtube',
            isLossless: false,
            audioFormat: 'YouTube Audio (160kbps)',
          );
          _updateTrackInQueue(ytTrack);
        }
      }
    } catch (_) {
    } finally {
      _preResolvingIds.remove(key);
    }
  }

  /// 3-Tier Progressive Queue Drain
  /// Tier 1: Current track and immediate next track (+1)
  /// Tier 2: Near Lookahead (+2, +3) with 200ms delay
  /// Tier 3: Full-queue sweep (+4..end, 0..current-1) with 300ms delay
  void _scheduleProgressiveQueueDrain([int? generation]) {
    final gen = generation ?? _queueLoadGeneration;
    if (_queue.isEmpty) return;

    Future.microtask(() async {
      if (gen != _queueLoadGeneration) return;

      // Tier 1: Current track and immediate next track (+1)
      final immediateIndices = [_currentIndex, _currentIndex + 1];
      for (final idx in immediateIndices) {
        if (gen != _queueLoadGeneration) return;
        if (idx >= 0 && idx < _queue.length) {
          final t = _queue[idx];
          if (idx == _currentIndex + 1) {
            resolveArtworkFor(t.artist, t.title);
            _lyricsService
                .fetchLyrics(
                  trackName: t.title,
                  artistName: t.artist,
                  durationSeconds: t.durationSeconds,
                  youtubeVideoId: t.youtubeVideoId,
                )
                .catchError((_) => <LyricLine>[]);
          }
          await _drainSingleTrack(t, gen);
        }
      }

      // Tier 2: Near Lookahead (+2, +3) with 200ms delay
      await Future.delayed(const Duration(milliseconds: 200));
      if (gen != _queueLoadGeneration) return;

      final nearLookaheadIndices = [_currentIndex + 2, _currentIndex + 3];
      for (final idx in nearLookaheadIndices) {
        if (gen != _queueLoadGeneration) return;
        if (idx >= 0 && idx < _queue.length) {
          final t = _queue[idx];
          resolveArtworkFor(t.artist, t.title);
          _lyricsService
              .fetchLyrics(
                trackName: t.title,
                artistName: t.artist,
                durationSeconds: t.durationSeconds,
                youtubeVideoId: t.youtubeVideoId,
              )
              .catchError((_) => <LyricLine>[]);
          await _drainSingleTrack(t, gen);
        }
      }

      // Tier 3: Full-queue sweep (+4..end, then 0..current-1) with 300ms delay
      await Future.delayed(const Duration(milliseconds: 300));
      if (gen != _queueLoadGeneration) return;

      // Forward pass: +4 to end
      for (int idx = _currentIndex + 4; idx < _queue.length; idx++) {
        if (gen != _queueLoadGeneration) return;
        final t = _queue[idx];
        if (_needsHifiResolution(t)) {
          await _drainSingleTrack(t, gen);
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // Backward pass: 0 to _currentIndex - 1
      for (int idx = 0; idx < _currentIndex; idx++) {
        if (gen != _queueLoadGeneration) return;
        final t = _queue[idx];
        if (_needsHifiResolution(t)) {
          await _drainSingleTrack(t, gen);
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }

  /// Pre-resolves stream URLs, album art, and lyrics for upcoming tracks in queue
  /// so track transitions (including when screen is off) are instant 0ms.
  void _preResolveUpcomingQueue() {
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
  }

  Future<void> _playStream(String url, {Track? fallbackYtTrack}) async {
    ConnectivityService().markOnline();
    if (url.startsWith('yt-iframe://')) {
      final videoId = url.substring('yt-iframe://'.length).trim();
      logDebug('_playStream: playing YouTube videoId "$videoId" via Cloudflare Worker IFrame Bridge');
      _isUsingYtIframe = true;
      _isBuffering = true;
      _playbackError = null;
      _activePlaybackTrackKey =
          _currentTrack != null ? '${_currentTrack!.id}_${_currentTrack!.title}' : null;
      _hasTrackCompleted = false;
      _isTransitioningTrack = false;
      _syncNotificationPlaybackState();
      notifyListeners();
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      _ytIframeBridge.loadVideo(videoId, startSeconds: 0, volume: _volume);
      return;
    }

    try {
      _isUsingYtIframe = false;
      _ytIframeBridge.stop();

      final cleanUrl = url.contains('?') ? '${url.substring(0, url.indexOf('?'))}?...' : url;
      logDebug('_playStream: attempting setUrl with $cleanUrl');
      await _audioPlayer.stop();
      if (!kIsWeb && !url.startsWith('http://') && !url.startsWith('https://')) {
        await _audioPlayer.setFilePath(url);
      } else {
        await _audioPlayer.setUrl(url);
      }
      logDebug('_playStream: audio source set. Setting volume and playing...');
      await _audioPlayer.setVolume(_volume);
      _isPlaying = true;
      _isBuffering = false;
      _playbackError = null;
      _activePlaybackTrackKey =
          _currentTrack != null ? '${_currentTrack!.id}_${_currentTrack!.title}' : null;
      _hasTrackCompleted = false;
      _isTransitioningTrack = false;
      _syncNotificationPlaybackState();
      unawaited(_audioPlayer.play());
      logDebug('_playStream: play() invoked successfully.');
    } catch (e) {
      logDebug('_playStream: caught exception: $e');
      // On Web, if direct audio stream fails (e.g. CORS or media element restriction)
      // and we have a valid YouTube videoId, immediately switch to the Cloudflare Worker IFrame Bridge!
      final track = fallbackYtTrack ?? _currentTrack;
      final vid = (track?.youtubeVideoId ?? track?.id ?? '').trim();
      final isRealVid = vid.isNotEmpty &&
          !vid.startsWith('trending_') &&
          !vid.startsWith('track_');
      if (kIsWeb && isRealVid && !(track?.isLossless ?? false)) {
        logDebug('_playStream: falling back to Cloudflare Worker IFrame Bridge for "$vid" on Web');
        _isUsingYtIframe = true;
        _isBuffering = true;
        _playbackError = null;
        notifyListeners();
        _ytIframeBridge.loadVideo(vid, startSeconds: 0, volume: _volume);
        return;
      }
      await _handlePlaybackFailure(e);
    }
  }

  Future<void> _handlePlaybackFailure(Object error) async {
    logDebug('_handlePlaybackFailure: entered with error: $error');
    if (_isAttemptingCandidateFallback) {
      logDebug('_handlePlaybackFailure: already attempting candidate fallback, ignoring re-entrant call.');
      return;
    }

    final track = _currentTrack;
    if (track == null) {
      logDebug('_handlePlaybackFailure: currentTrack is null.');
      _isBuffering = false;
      notifyListeners();
      return;
    }

    if (!isOnline && ConnectivityService().isInForeground) {
      logDebug('_handlePlaybackFailure: offline status detected.');
      _isBuffering = false;
      _playbackError = 'No internet connection. Reconnect to stream.';
      notifyListeners();
      return;
    }

    final trackKey = '${track.id}_${track.title}_${track.artist}'.toLowerCase();
    if (_failedTrackKey != trackKey) {
      _failedTrackKey = trackKey;
      _failedCandidateIdsForTrack.clear();
      logDebug('_handlePlaybackFailure: reset failed candidate IDs for new trackKey: "$trackKey"');
    }

    final currentVid = (track.youtubeVideoId ?? track.id).trim();
    if (currentVid.isNotEmpty &&
        !currentVid.startsWith('track_') &&
        !currentVid.startsWith('trending_')) {
      _failedCandidateIdsForTrack.add(currentVid);
      logDebug('_handlePlaybackFailure: added currentVid "$currentVid" to failedCandidateIds: $_failedCandidateIdsForTrack');
    }

    // 1. If current track was Hi-Fi FLAC that failed, attempt refresh first before YouTube fallback
    if (track.isLossless) {
      logDebug('_handlePlaybackFailure: track was Hi-Fi FLAC. Attempting FLAC refresh before YouTube fallback...');
      _isAttemptingCandidateFallback = true;
      _isBuffering = true;
      _playbackError = null;
      notifyListeners();

      try {
        final refreshed = await _hifiMatcher.refreshFlacUrl(track);
        if (refreshed != null &&
            refreshed.flacStreamUrl != null &&
            refreshed.flacStreamUrl != track.flacStreamUrl) {
          logDebug('_handlePlaybackFailure: FLAC refresh succeeded with fresh stream URL. Playing...');
          _currentTrack = refreshed;
          _updateTrackInQueue(refreshed);
          _updateRecentlyPlayed(refreshed);
          _persistPlayerState();
          _isAttemptingCandidateFallback = false;
          notifyListeners();
          await _playStream(refreshed.flacStreamUrl!, fallbackYtTrack: refreshed);
          return;
        }
      } catch (refErr) {
        logDebug('_handlePlaybackFailure: FLAC refresh threw error: $refErr');
      }

      logDebug('_handlePlaybackFailure: FLAC refresh unsuccessful. Downgrading to YouTube audio stream...');
      try {
        final ytRes = await _ytResolver.resolveStreamForTrack(
          title: track.title,
          artist: track.artist,
          primaryVideoId: currentVid,
          excludedVideoIds: _failedCandidateIdsForTrack,
        );

        if (ytRes.isSuccess && ytRes.url != null) {
          logDebug('_handlePlaybackFailure: FLAC downgrade successfully resolved YouTube stream for "$currentVid"');
          final downgraded = track.copyWith(
            youtubeVideoId: ytRes.videoId ?? currentVid,
            flacStreamUrl: ytRes.url,
            audioSource: 'youtube',
            isLossless: false,
            audioFormat: 'YouTube Audio (160kbps)',
          );
          _currentTrack = downgraded;
          _updateTrackInQueue(downgraded);
          _updateRecentlyPlayed(downgraded);
          _isAttemptingCandidateFallback = false;
          notifyListeners();

          await _playStream(ytRes.url!, fallbackYtTrack: downgraded);
          return;
        } else {
          logDebug('_handlePlaybackFailure: FLAC downgrade to YouTube failed: ${ytRes.errorMessage}');
        }
      } catch (downgradeErr) {
        logDebug('_handlePlaybackFailure: FLAC downgrade caught error: $downgradeErr');
      } finally {
        _isAttemptingCandidateFallback = false;
      }
    }

    // 2. Try alternative YouTube candidate streams (up to 4 candidates)
    if (_failedCandidateIdsForTrack.length <= 4) {
      logDebug('_handlePlaybackFailure: searching candidate stream for "${track.title}" (failed IDs: $_failedCandidateIdsForTrack)...');
      _isAttemptingCandidateFallback = true;
      _isBuffering = true;
      _playbackError = null;
      notifyListeners();

      try {
        final altRes = await _ytResolver.resolveAlternativeStream(
          title: track.title,
          artist: track.artist,
          excludedVideoIds: _failedCandidateIdsForTrack,
        );

        if (altRes.isSuccess && altRes.url != null && altRes.videoId != null) {
          logDebug('_handlePlaybackFailure: SUCCESS: Candidate [${altRes.videoId}] resolved! Applying and playing...');
          _failedCandidateIdsForTrack.add(altRes.videoId!);

          final altTrack = track.copyWith(
            youtubeVideoId: altRes.videoId,
            flacStreamUrl: altRes.url,
            audioSource: 'youtube',
            isLossless: false,
            audioFormat: 'YouTube Audio (160kbps)',
          );
          _currentTrack = altTrack;
          _updateTrackInQueue(altTrack);
          _updateRecentlyPlayed(altTrack);
          _isAttemptingCandidateFallback = false;
          notifyListeners();

          await _playStream(altRes.url!, fallbackYtTrack: altTrack);
          return;
        } else {
          logDebug('_handlePlaybackFailure: Candidate search returned failure: ${altRes.errorMessage}');
        }
      } catch (candidateErr) {
        logDebug('_handlePlaybackFailure: Candidate attempt threw error: $candidateErr');
      } finally {
        _isAttemptingCandidateFallback = false;
      }
    }

    // 3. All candidates exhausted: present a human-friendly error message
    logDebug('_handlePlaybackFailure: All candidates exhausted or failed. Setting playback error.');
    _isBuffering = false;
    _isTransitioningTrack = false;
    _playbackError = _formatPlaybackError(error, track);
    notifyListeners();
  }

  String _formatPlaybackError(Object error, Track? track) {
    if (!isOnline) {
      return 'No internet connection. Reconnect to stream.';
    }
    final trackName = track?.title ?? 'track';
    final errStr = error.toString().toLowerCase();

    if (errStr.contains('403') || errStr.contains('forbidden')) {
      return 'Playback restricted for "$trackName". Tap to retry.';
    }
    if (errStr.contains('unsupported') || errStr.contains('decode')) {
      return 'Audio format unsupported by device. Tap to retry.';
    }
    if (errStr.contains('timeout')) {
      return 'Stream connection timed out for "$trackName". Tap to retry.';
    }
    return 'Unable to stream "$trackName". Tap to retry.';
  }

  void _updateTrackInQueue(Track updated) {
    final upVid = updated.youtubeVideoId ?? updated.id;
    final idx = _queue.indexWhere((t) =>
        t.id == updated.id ||
        (t.youtubeVideoId != null && t.youtubeVideoId == upVid) ||
        (t.id == upVid));
    if (idx != -1) {
      final existingKey = _queue[idx].queueEntryId;
      _queue[idx] = updated.copyWith(
        extraData: {
          ...?updated.extraData,
          'queue_entry_id': existingKey,
        },
      );
    }
  }

  /// Condition 2: When songs are added to the queue
  Future<void> addToQueue(Track track) async {
    final resolved = _tagQueueEntry(await _resolveTrackForQueue(track));
    _queue.add(resolved);
    _persistPlayerState();
    notifyListeners();
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
  }

  Future<void> addTracksToQueue(List<Track> tracks) async {
    final gated = tracks
        .map((t) => _hifiMatcher.prepareTrackThroughGateSync(
              t,
              isHifiEnabled: _isHifiEnabled,
            ))
        .map(_tagQueueEntry)
        .toList();
    _queue.addAll(gated);
    _persistPlayerState();
    notifyListeners();
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
  }

  void _resolveQueueHiFiInBackground() {
    if (!_isHifiEnabled) return;
    _scheduleProgressiveQueueDrain(_queueLoadGeneration);
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
              (nextTrack.youtubeVideoId ?? nextTrack.id)) &&
          !_vibeService.isSameArtist(nextTrack, _queue.last)) {
        final resolvedNext = _tagQueueEntry(await _resolveTrackForQueue(nextTrack));
        _queue.add(resolvedNext);
        notifyListeners();
        _preResolveUpcomingQueue();

        // Pre-fetch a second vibe track so there is always a buffer
        final secondTrack = await _vibeService.getNextVibeTrack(
          queue: _queue,
          currentIndex: _currentIndex,
        );
        if (secondTrack != null &&
            !_queue.any((q) =>
                (q.youtubeVideoId ?? q.id) ==
                (secondTrack.youtubeVideoId ?? secondTrack.id)) &&
            !_vibeService.isSameArtist(secondTrack, _queue.last)) {
          final resolvedSecond = _tagQueueEntry(await _resolveTrackForQueue(secondTrack));
          _queue.add(resolvedSecond);
          notifyListeners();
          _preResolveUpcomingQueue();
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
    if (_isUsingYtIframe) {
      if (_isPlaying) {
        _ytIframeBridge.pause();
        _isPlaying = false;
      } else {
        _ytIframeBridge.play();
        _isPlaying = true;
      }
      notifyListeners();
      return;
    }

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

  Future<void> stopPlayback() async {
    _ytIframeBridge.stop();
    _isUsingYtIframe = false;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    _isPlaying = false;
    _isBuffering = false;
    _position = Duration.zero;
    positionNotifier.value = Duration.zero;
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    _position = position;
    positionNotifier.value = position;
    notifyListeners();
    if (_isUsingYtIframe) {
      _ytIframeBridge.seekTo(position);
      return;
    }
    try {
      await _audioPlayer.seek(position);
    } catch (_) {}
  }

  Future<void> next({bool isAutoAdvance = false}) async {
    if (_queue.isEmpty) {
      _isTransitioningTrack = false;
      return;
    }
    final now = DateTime.now();
    if (!isAutoAdvance &&
        _lastTrackChangeTime != null &&
        now.difference(_lastTrackChangeTime!) < const Duration(milliseconds: 1000)) {
      logDebug('next() debounced: ignoring rapid duplicate invocation');
      return;
    }
    _lastTrackChangeTime = now;

    if (_repeatMode == 2) {
      _hasTrackCompleted = false;
      _isTransitioningTrack = false;
      seekTo(Duration.zero);
      if (!_isPlaying) {
        if (_isUsingYtIframe) {
          _ytIframeBridge.play();
        } else {
          _audioPlayer.play();
        }
      }
      return;
    }
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      _lastTrackChangeTime = DateTime.now();
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
        _lastTrackChangeTime = DateTime.now();
        await playTrack(_queue[_currentIndex]);
        return;
      }
    }

    _isTransitioningTrack = false;
    if (_repeatMode == 1 && _queue.isNotEmpty) {
      _currentIndex = 0;
      _lastTrackChangeTime = DateTime.now();
      await playTrack(_queue[_currentIndex]);
    } else {
      _ytIframeBridge.stop();
      _isUsingYtIframe = false;
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
    _ytIframeBridge.setVolume(_volume);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      final removed = _queue.removeAt(index);
      if (_currentTrack != null) {
        if (_currentTrack!.queueEntryId == removed.queueEntryId) {
          if (_currentIndex >= _queue.length) {
            _currentIndex = (_queue.length - 1).clamp(0, _queue.length);
          }
          if (_queue.isNotEmpty) {
            _currentTrack = _queue[_currentIndex];
          }
        } else {
          final found = _queue.indexWhere(
              (t) => t.queueEntryId == _currentTrack!.queueEntryId);
          if (found != -1) {
            _currentIndex = found;
          } else if (_currentIndex >= _queue.length) {
            _currentIndex = (_queue.length - 1).clamp(0, _queue.length);
          }
        }
      } else if (_currentIndex >= _queue.length) {
        _currentIndex = (_queue.length - 1).clamp(0, _queue.length);
      }
      _persistPlayerState();
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (_queue.isEmpty || oldIndex < 0 || oldIndex >= _queue.length) {
      return;
    }
    final targetIndex = newIndex.clamp(0, _queue.length - 1);
    if (oldIndex == targetIndex) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(targetIndex, item);

    // Keep _currentIndex pointing to the currently active track
    if (_currentTrack != null) {
      final curEntryId = _currentTrack!.queueEntryId;
      final found = _queue.indexWhere((t) => t.queueEntryId == curEntryId);
      if (found != -1) {
        _currentIndex = found;
      } else {
        final curId = _currentTrack!.youtubeVideoId ?? _currentTrack!.id;
        final fallbackFound =
            _queue.indexWhere((t) => (t.youtubeVideoId ?? t.id) == curId);
        if (fallbackFound != -1) {
          _currentIndex = fallbackFound;
        }
      }
    }

    _persistPlayerState();
    notifyListeners();
  }

  void clearQueue() {
    if (_currentTrack != null) {
      _queue = [_tagQueueEntry(_currentTrack!)];
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
      // Clear cached stream URL so retry resolves a fresh working stream
      final resetTrack = _currentTrack!.copyWith(
        flacStreamUrl: null,
        audioSource: 'youtube',
        isLossless: false,
      );
      await playTrack(resetTrack);
    }
  }

  void clearPlaybackError() {
    _playbackError = null;
    notifyListeners();
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _startupTimer?.cancel();
    _persistDebounce?.cancel();
    positionNotifier.dispose();
    debugLogsVersion.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _connectivitySub?.cancel();
    _ytPosSub?.cancel();
    _ytDurSub?.cancel();
    _ytStateSub?.cancel();
    _ytErrSub?.cancel();
    ConnectivityService().stopMonitoring();
    _ytIframeBridge.dispose();
    _audioPlayer.dispose();
    _ytResolver.dispose();
    super.dispose();
  }
}
