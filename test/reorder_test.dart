import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';
import 'package:pulse_audio/services/playlist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Queue & Playlist Reordering Tests', () {
    late PlayerProvider player;
    late PlaylistService playlistService;

    final trackA = Track(
      id: 'track_a',
      title: 'Song Alpha',
      artist: 'Artist A',
      thumbnailUrl: 'https://example.com/a.jpg',
      durationSeconds: 180,
    );

    final trackB = Track(
      id: 'track_b',
      title: 'Song Beta',
      artist: 'Artist B',
      thumbnailUrl: 'https://example.com/b.jpg',
      durationSeconds: 200,
    );

    final trackC = Track(
      id: 'track_c',
      title: 'Song Gamma',
      artist: 'Artist C',
      thumbnailUrl: 'https://example.com/c.jpg',
      durationSeconds: 220,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      player = PlayerProvider();
      playlistService = PlaylistService();
    });

    tearDown(() {
      player.dispose();
    });

    test('reorderQueue moves item downward accurately without jumping back', () async {
      player.playTrackList([trackA, trackB, trackC], 0);

      expect(player.queue.map((t) => t.id).toList(), ['track_a', 'track_b', 'track_c']);
      expect(player.currentIndex, 0);

      // In modern Flutter onReorderItem, moving track 0 to position 1 calls (0, 1)
      player.reorderQueue(0, 1);

      expect(player.queue.map((t) => t.id).toList(), ['track_b', 'track_a', 'track_c']);
      // Playing track was trackA; it is now at index 1, so currentIndex should follow it
      expect(player.currentIndex, 1);
      expect(player.currentTrack?.id, 'track_a');
    });

    test('reorderQueue moves item upward accurately and tracks currentIndex', () async {
      player.playTrackList([trackA, trackB, trackC], 1); // trackB is playing at index 1

      expect(player.currentIndex, 1);
      expect(player.currentTrack?.id, 'track_b');

      // Move trackC (index 2) to the very top (index 0)
      player.reorderQueue(2, 0);

      expect(player.queue.map((t) => t.id).toList(), ['track_c', 'track_a', 'track_b']);
      // trackB shifted from index 1 to index 2; currentIndex should update to 2
      expect(player.currentIndex, 2);
      expect(player.currentTrack?.id, 'track_b');
    });

    test('reorderQueue ignores out of bounds or identical indices safely', () async {
      player.playTrackList([trackA, trackB, trackC], 0);

      player.reorderQueue(0, 0);
      expect(player.queue.map((t) => t.id).toList(), ['track_a', 'track_b', 'track_c']);

      player.reorderQueue(-1, 2);
      expect(player.queue.map((t) => t.id).toList(), ['track_a', 'track_b', 'track_c']);

      player.reorderQueue(10, 0);
      expect(player.queue.map((t) => t.id).toList(), ['track_a', 'track_b', 'track_c']);
    });

    test('removeFromQueue correctly adjusts currentIndex when earlier track is removed', () async {
      player.playTrackList([trackA, trackB, trackC], 2); // trackC is playing at index 2

      expect(player.currentIndex, 2);
      expect(player.currentTrack?.id, 'track_c');

      // Remove trackA at index 0
      player.removeFromQueue(0);

      expect(player.queue.map((t) => t.id).toList(), ['track_b', 'track_c']);
      // trackC is now at index 1; currentIndex must update to 1
      expect(player.currentIndex, 1);
      expect(player.currentTrack?.id, 'track_c');
    });

    test('PlaylistService reorderTracksInPlaylist moves tracks accurately', () async {
      final playlist = await playlistService.createPlaylist('My Reorder Playlist');
      await playlistService.addTrackToPlaylist(playlist.id, trackA);
      await playlistService.addTrackToPlaylist(playlist.id, trackB);
      await playlistService.addTrackToPlaylist(playlist.id, trackC);

      var loaded = (await playlistService.loadPlaylists()).firstWhere((p) => p.id == playlist.id);
      expect(loaded.tracks.map((t) => t.id).toList(), ['track_a', 'track_b', 'track_c']);

      // onReorderItem moving index 0 to 1
      await playlistService.reorderTracksInPlaylist(playlist.id, 0, 1);

      loaded = (await playlistService.loadPlaylists()).firstWhere((p) => p.id == playlist.id);
      expect(loaded.tracks.map((t) => t.id).toList(), ['track_b', 'track_a', 'track_c']);

      // onReorderItem moving index 2 to 0
      await playlistService.reorderTracksInPlaylist(playlist.id, 2, 0);

      loaded = (await playlistService.loadPlaylists()).firstWhere((p) => p.id == playlist.id);
      expect(loaded.tracks.map((t) => t.id).toList(), ['track_c', 'track_b', 'track_a']);
    });
  });
}
