import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/playlist.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/playlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testTrack1 = Track(
    id: 't1',
    title: 'Test Song 1',
    artist: 'Test Artist 1',
    album: 'Album 1',
    durationSeconds: 180,
    thumbnailUrl: 'https://example.com/1.jpg',
  );

  final testTrack2 = Track(
    id: 't2',
    title: 'Test Song 2',
    artist: 'Test Artist 2',
    album: 'Album 2',
    durationSeconds: 240,
    thumbnailUrl: 'https://example.com/2.jpg',
  );

  test('Playlist model formats duration and track count correctly', () {
    final playlist = Playlist(
      id: 'p1',
      title: 'My Vibes',
      tracks: [testTrack1, testTrack2],
    );

    expect(playlist.formattedTrackCount, '2 songs');
    // 180 + 240 = 420 seconds = 7 min
    expect(playlist.formattedDuration, '7 min');
  });

  test('PlaylistService CRUD operations work correctly', () async {
    final service = PlaylistService();

    // 1. Create Playlist
    final created = await service.createPlaylist(
      'Chill Nights',
      description: 'Late night tunes',
      initialTracks: [testTrack1],
    );

    expect(created.title, 'Chill Nights');
    expect(created.tracks.length, 1);
    expect(created.tracks.first.id, 't1');

    // 2. Add track
    final added = await service.addTrackToPlaylist(created.id, testTrack2);
    expect(added, isTrue);

    // Adding duplicate track should return false
    final duplicate = await service.addTrackToPlaylist(created.id, testTrack2);
    expect(duplicate, isFalse);

    // Check loaded playlists
    var playlists = await service.loadPlaylists();
    var loaded = playlists.firstWhere((p) => p.id == created.id);
    expect(loaded.tracks.length, 2);

    // 3. Rename Playlist
    await service.renamePlaylist(created.id, 'Super Chill Nights');
    playlists = await service.loadPlaylists();
    loaded = playlists.firstWhere((p) => p.id == created.id);
    expect(loaded.title, 'Super Chill Nights');

    // 4. Reorder tracks
    await service.reorderTracksInPlaylist(created.id, 0, 2);
    playlists = await service.loadPlaylists();
    loaded = playlists.firstWhere((p) => p.id == created.id);
    expect(loaded.tracks[0].id, 't2');
    expect(loaded.tracks[1].id, 't1');

    // 5. Remove track
    await service.removeTrackFromPlaylist(created.id, 't1');
    playlists = await service.loadPlaylists();
    loaded = playlists.firstWhere((p) => p.id == created.id);
    expect(loaded.tracks.length, 1);
    expect(loaded.tracks.first.id, 't2');

    // 6. Delete Playlist
    await service.deletePlaylist(created.id);
    playlists = await service.loadPlaylists();
    expect(playlists.any((p) => p.id == created.id), isFalse);
  });
}
