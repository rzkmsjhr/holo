import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Liked Songs Tests', () {
    test('Toggling favorite adds and removes track from likedTracks', () async {
      final player = PlayerProvider();

      final testTrack = Track(
        id: 'test_track_1',
        title: 'hate that i made you love me',
        artist: 'Ariana Grande',
        thumbnailUrl: 'https://example.com/cover.jpg',
        durationSeconds: 210,
        youtubeVideoId: 'test_track_1',
      );

      // Initially not favorite
      expect(player.isFavorite('test_track_1'), isFalse);
      expect(player.likedTracks.isEmpty, isTrue);

      // 1. Like track
      player.toggleFavorite(testTrack);
      expect(player.isFavorite('test_track_1'), isTrue);
      expect(player.likedTracks.length, 1);
      expect(player.likedTracks.first.title, 'hate that i made you love me');
      expect(player.likedTracks.first.artist, 'Ariana Grande');

      // 2. Unlike track
      player.toggleFavorite(testTrack);
      expect(player.isFavorite('test_track_1'), isFalse);
      expect(player.likedTracks.isEmpty, isTrue);

      // 3. Like again and remove by id
      player.toggleFavorite(testTrack);
      expect(player.likedTracks.length, 1);
      player.removeLikedTrack('test_track_1');
      expect(player.isFavorite('test_track_1'), isFalse);
      expect(player.likedTracks.isEmpty, isTrue);
    });

    test('Liked tracks persist correctly to local storage', () async {
      final player1 = PlayerProvider();
      final track = Track(
        id: 'song_99',
        title: 'Nicole Kidman',
        artist: 'ADÉLA',
        thumbnailUrl: 'https://example.com/adela.jpg',
        durationSeconds: 195,
        youtubeVideoId: 'song_99',
      );

      player1.toggleFavorite(track);
      expect(player1.likedTracks.length, 1);

      // Re-initialize a new PlayerProvider instance
      final player2 = PlayerProvider();
      // Allow async init to load SharedPreferences
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(player2.isFavorite('song_99'), isTrue);
      expect(player2.likedTracks.length, 1);
      expect(player2.likedTracks.first.title, 'Nicole Kidman');
    });
  });
}
