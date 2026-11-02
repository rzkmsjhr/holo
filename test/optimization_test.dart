import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/audio_handler.dart';
import 'package:pulse_audio/services/lyrics_service.dart';
import 'package:pulse_audio/ui/widgets/holo_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LyricsService Persistent Disk Cache Tests', () {
    test('LyricLine serializes to and from JSON accurately', () {
      final line = LyricLine(
        timestamp: const Duration(minutes: 1, seconds: 23, milliseconds: 450),
        text: 'One more time, we are gonna celebrate',
      );
      final json = line.toJson();
      final restored = LyricLine.fromJson(json);
      expect(restored.timestamp.inMilliseconds, equals(83450));
      expect(restored.text, equals('One more time, we are gonna celebrate'));
    });

    test('LyricsService loads cached lyrics from SharedPreferences without network', () async {
      final cachedLines = [
        LyricLine(timestamp: const Duration(seconds: 10), text: 'First line of song').toJson(),
        LyricLine(timestamp: const Duration(seconds: 15), text: 'Second line of song').toJson(),
        LyricLine(timestamp: const Duration(seconds: 20), text: 'Third line of song').toJson(),
      ];

      SharedPreferences.setMockInitialValues({
        'lyrics_cache_v1_digital love|daft punk': jsonEncode(cachedLines),
      });

      final service = LyricsService();
      final result = await service.fetchLyrics(
        trackName: 'Digital Love',
        artistName: 'Daft Punk',
      );

      expect(result.length, equals(3));
      expect(result.first.text, equals('First line of song'));
      expect(result.last.timestamp.inSeconds, equals(20));

      // Verify synchronous memory cache is now populated as well
      final syncResult = service.getCachedSync('Digital Love', 'Daft Punk');
      expect(syncResult, isNotNull);
      expect(syncResult!.length, equals(3));
    });
  });

  group('HoloAudioHandler Notification MediaSession Tests', () {
    test('HoloAudioHandler updates MediaItem and PlaybackState accurately', () async {
      final handler = HoloAudioServiceManager.handler;
      bool playCalled = false;
      bool nextCalled = false;

      handler.onPlay = () => playCalled = true;
      handler.onSkipToNext = () => nextCalled = true;

      final track = Track(
        id: 'FGBhQbmPwH8',
        title: 'One More Time',
        artist: 'Daft Punk',
        album: 'Discovery',
        thumbnailUrl: 'https://i.ytimg.com/vi/FGBhQbmPwH8/hqdefault.jpg',
        durationSeconds: 320,
      );

      await handler.updateTrackMediaItem(track);
      expect(handler.mediaItem.value?.title, equals('One More Time'));
      expect(handler.mediaItem.value?.artist, equals('Daft Punk'));
      expect(handler.mediaItem.value?.album, equals('Discovery'));

      handler.syncPlaybackState(
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 42),
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.position.inSeconds, equals(42));

      await handler.play();
      await handler.skipToNext();
      expect(playCalled, isTrue);
      expect(nextCalled, isTrue);
    });

    test('HoloAudioHandler onTaskRemoved dismisses notification, stops playback, and transitions to idle', () async {
      final handler = HoloAudioServiceManager.handler;
      bool stopCalled = false;
      handler.onStop = () => stopCalled = true;

      // Simulate active playback
      handler.syncPlaybackState(
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 15),
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isStopped, isFalse);

      // App is closed / swiped away in task manager
      await handler.onTaskRemoved();

      expect(stopCalled, isTrue);
      expect(handler.isStopped, isTrue);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState.name, equals('idle'));

      // Lingering player position / state stream events while stopped must not revive ready state
      handler.syncPlaybackState(
        isPlaying: false,
        isBuffering: false,
        position: const Duration(seconds: 15),
      );
      expect(handler.playbackState.value.processingState.name, equals('idle'));
      expect(handler.playbackState.value.playing, isFalse);
    });
  });

  group('HoloImage Widget Tests', () {
    testWidgets('HoloImage renders errorBuilder cleanly when URL is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HoloImage(
              '',
              errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });
}
