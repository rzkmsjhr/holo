import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../models/track.dart';

/// Bridges Holo's audio playback with the native Android/iOS MediaSession
/// and persistent system notification controls.
class HoloAudioHandler extends BaseAudioHandler with SeekHandler {
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  ValueChanged<Duration>? onSeek;
  VoidCallback? onStop;
  bool _isStopped = false;

  bool get isStopped => _isStopped;

  HoloAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  /// Updates the notification metadata & cover art.
  Future<void> updateTrackMediaItem(
    Track track, {
    String? resolvedArtworkUrl,
    Duration? duration,
  }) async {
    _isStopped = false;
    final vid = track.youtubeVideoId ?? track.id;
    final rawArt = (resolvedArtworkUrl != null && resolvedArtworkUrl.isNotEmpty)
        ? resolvedArtworkUrl
        : (track.highResThumbnailUrl.isNotEmpty
            ? track.highResThumbnailUrl
            : (track.thumbnailUrl.isNotEmpty
                ? track.thumbnailUrl
                : (vid.length == 11
                    ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg'
                    : '')));

    final artUri = rawArt.isNotEmpty ? Uri.tryParse(rawArt) : null;

    final dur = (duration != null && duration.inSeconds > 0)
        ? duration
        : Duration(
            seconds: track.durationSeconds > 0 ? track.durationSeconds : 180);

    final item = MediaItem(
      id: track.id,
      album: track.album.isNotEmpty ? track.album : 'Holo Hi-Fi',
      title: track.title,
      artist: track.artist,
      duration: dur,
      artUri: artUri,
    );

    mediaItem.add(item);
  }

  void syncPlaybackState({
    required bool isPlaying,
    required bool isBuffering,
    required Duration position,
    Duration bufferedPosition = Duration.zero,
  }) {
    // If the handler is marked as stopped, do not re-emit active/ready states unless actively playing
    if (_isStopped && !isPlaying) {
      return;
    }
    _isStopped = false;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition:
            bufferedPosition > position ? bufferedPosition : position,
        speed: isPlaying ? 1.0 : 0.0,
      ),
    );
  }

  @override
  Future<void> play() async {
    _isStopped = false;
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    onPause?.call();
  }

  @override
  Future<void> skipToNext() async {
    _isStopped = false;
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    _isStopped = false;
    onSkipToPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    onSeek?.call(position);
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  @override
  Future<void> stop() async {
    _isStopped = true;
    onStop?.call();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }
}

class HoloAudioServiceManager {
  static HoloAudioHandler? _handler;
  static bool _initialized = false;

  static HoloAudioHandler get handler {
    _handler ??= HoloAudioHandler();
    return _handler!;
  }

  static Future<HoloAudioHandler> init() async {
    if (_initialized && _handler != null) return _handler!;
    _initialized = true;
    if (kIsWeb) {
      _handler = HoloAudioHandler();
      return _handler!;
    }
    try {
      _handler = await AudioService.init(
        builder: () => HoloAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.pulse_audio.channel.audio',
          androidNotificationChannelName: 'Holo Music Playback',
          androidNotificationChannelDescription:
              'Persistent media playback controls for Holo',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidShowNotificationBadge: false,
          androidNotificationClickStartsActivity: true,
          androidStopForegroundOnPause: false,
          androidResumeOnClick: false,
          androidNotificationOngoing: false,
          preloadArtwork: true,
        ),
      );
    } catch (_) {
      _handler ??= HoloAudioHandler();
    }
    return _handler!;
  }
}
