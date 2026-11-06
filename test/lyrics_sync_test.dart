import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Lyrics Sync Adjuster Tests', () {
    test('Default sync offset is 0.0 and effective position equals playback position', () {
      final player = PlayerProvider();
      expect(player.lyricsSyncOffset, 0.0);
      expect(player.effectiveLyricsPosition, Duration.zero);
    });

    test('Positive sync offset advances effective lyrics position', () async {
      final player = PlayerProvider();

      await player.setLyricsSyncOffset(0.5);
      expect(player.lyricsSyncOffset, 0.5);

      // When player.position is 1000ms, effective position is 1000ms + 500ms = 1500ms
      player.seekTo(const Duration(milliseconds: 1000));
      expect(player.effectiveLyricsPosition, const Duration(milliseconds: 1500));
    });

    test('Negative sync offset delays effective lyrics position and clamps to zero', () async {
      final player = PlayerProvider();

      await player.setLyricsSyncOffset(-0.5);
      expect(player.lyricsSyncOffset, -0.5);

      // At position 1000ms, effective position is 1000ms - 500ms = 500ms
      player.seekTo(const Duration(milliseconds: 1000));
      expect(player.effectiveLyricsPosition, const Duration(milliseconds: 500));

      // At position 200ms, effective position 200ms - 500ms = -300ms -> clamped to 0
      player.seekTo(const Duration(milliseconds: 200));
      expect(player.effectiveLyricsPosition, Duration.zero);
    });

    test('adjustLyricsSyncOffset steps by 0.25 and clamps to [-30.0, 30.0]', () async {
      final player = PlayerProvider();

      await player.adjustLyricsSyncOffset(0.25);
      expect(player.lyricsSyncOffset, 0.25);

      await player.adjustLyricsSyncOffset(0.25);
      expect(player.lyricsSyncOffset, 0.50);

      await player.adjustLyricsSyncOffset(-0.25);
      expect(player.lyricsSyncOffset, 0.25);

      // Test extreme clamping
      await player.setLyricsSyncOffset(29.9);
      await player.adjustLyricsSyncOffset(0.25);
      expect(player.lyricsSyncOffset, 30.0);

      await player.setLyricsSyncOffset(-29.9);
      await player.adjustLyricsSyncOffset(-0.25);
      expect(player.lyricsSyncOffset, -30.0);
    });

    test('resetLyricsSyncOffset sets offset back to 0.0', () async {
      final player = PlayerProvider();

      await player.setLyricsSyncOffset(1.25);
      expect(player.lyricsSyncOffset, 1.25);

      await player.resetLyricsSyncOffset();
      expect(player.lyricsSyncOffset, 0.0);
    });

    test('Sync offset persists per track in SharedPreferences and cleans up on 0.0', () async {
      final prefs = await SharedPreferences.getInstance();
      final player = PlayerProvider();

      final trackA = Track(
        id: 'track_a_123',
        title: 'Stay With Me',
        artist: 'Miki Matsubara',
        thumbnailUrl: 'https://example.com/art.jpg',
        durationSeconds: 300,
        youtubeVideoId: 'video_a_123',
      );

      final key = PlayerProvider.lyricsSyncKeyForTrack(trackA);
      expect(key, 'lyrics_sync_miki_matsubara_stay_with_me');

      // Set sync offset explicitly for track A
      await player.setLyricsSyncOffset(0.75, forTrack: trackA);
      expect(player.lyricsSyncOffset, 0.75);

      // Key should be saved in SharedPreferences
      expect(prefs.getDouble(key), 0.75);

      // Resetting removes key from storage
      await player.setLyricsSyncOffset(0.0, forTrack: trackA);
      expect(player.lyricsSyncOffset, 0.0);
      expect(prefs.containsKey(key), isFalse);
    });

    test('Loading track restores saved sync offset', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('lyrics_sync_tatsuro_yamashita_ride_on_time', -1.25);

      final player = PlayerProvider();

      final trackWithSavedSync = Track(
        id: 'ride_on_time_id',
        title: 'Ride on Time',
        artist: 'Tatsuro Yamashita',
        thumbnailUrl: 'https://example.com/art2.jpg',
        durationSeconds: 260,
      );

      final trackWithoutSync = Track(
        id: 'plastic_love_id',
        title: 'Plastic Love',
        artist: 'Mariya Takeuchi',
        thumbnailUrl: 'https://example.com/art3.jpg',
        durationSeconds: 290,
      );

      await player.loadLyricsSyncForTrack(trackWithSavedSync);
      expect(player.lyricsSyncOffset, -1.25);

      await player.loadLyricsSyncForTrack(trackWithoutSync);
      expect(player.lyricsSyncOffset, 0.0);
    });
  });
}
