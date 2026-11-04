import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';
import 'package:pulse_audio/services/playlist_import_service.dart';
import 'package:pulse_audio/services/playlist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playlist Import URL & Share-Text Parser Tests', () {
    test('parses standard YouTube and YouTube Music playlist URLs', () {
      final ytm = PlaylistImportService.parsePlaylistUrl(
          'https://music.youtube.com/playlist?list=OLAK5uy_nw7jqj_0l7BJ1s1b1pmlyGsWcNE1W2QK0');
      expect(ytm, isNotNull);
      expect(ytm!.platform, PlaylistPlatform.youtube);
      expect(ytm.playlistId, 'OLAK5uy_nw7jqj_0l7BJ1s1b1pmlyGsWcNE1W2QK0');

      final yt = PlaylistImportService.parsePlaylistUrl(
          'https://www.youtube.com/playlist?list=PLrAlq0K7Zf3W_vH6f4s1');
      expect(yt, isNotNull);
      expect(yt!.platform, PlaylistPlatform.youtube);
      expect(yt.playlistId, 'PLrAlq0K7Zf3W_vH6f4s1');

      final watchWithList = PlaylistImportService.parsePlaylistUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1234567890');
      expect(watchWithList, isNotNull);
      expect(watchWithList!.platform, PlaylistPlatform.youtube);
      expect(watchWithList.playlistId, 'PL1234567890');
    });

    test('extracts YouTube URLs from mobile share text containing prose', () {
      const shareText =
          'Check out this mix on YouTube Music! https://music.youtube.com/playlist?list=PLabc12345&si=xyz789 - amazing songs!';
      final parsed = PlaylistImportService.parsePlaylistUrl(shareText);
      expect(parsed, isNotNull);
      expect(parsed!.platform, PlaylistPlatform.youtube);
      expect(parsed.playlistId, 'PLabc12345');
    });

    test('parses Spotify playlist URLs, URIs, and share links', () {
      final spotWeb = PlaylistImportService.parsePlaylistUrl(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M');
      expect(spotWeb, isNotNull);
      expect(spotWeb!.platform, PlaylistPlatform.spotify);
      expect(spotWeb.playlistId, '37i9dQZF1DXcBWIGoYBM5M');

      final spotWithTracking = PlaylistImportService.parsePlaylistUrl(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=8a7c6b5e4d3c2b1a&pt=987');
      expect(spotWithTracking, isNotNull);
      expect(spotWithTracking!.platform, PlaylistPlatform.spotify);
      expect(spotWithTracking.playlistId, '37i9dQZF1DXcBWIGoYBM5M');

      final spotUri = PlaylistImportService.parsePlaylistUrl(
          'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M');
      expect(spotUri, isNotNull);
      expect(spotUri!.platform, PlaylistPlatform.spotify);
      expect(spotUri.playlistId, '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('extracts Spotify URLs from mobile share sheet text', () {
      const mobileShareText =
          'Hey check out this playlist on Spotify: https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=12345';
      final parsed = PlaylistImportService.parsePlaylistUrl(mobileShareText);
      expect(parsed, isNotNull);
      expect(parsed!.platform, PlaylistPlatform.spotify);
      expect(parsed.playlistId, '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('returns null for unrelated URLs or invalid inputs', () {
      expect(PlaylistImportService.parsePlaylistUrl(''), isNull);
      expect(PlaylistImportService.parsePlaylistUrl('https://google.com'), isNull);
      expect(PlaylistImportService.parsePlaylistUrl('https://youtube.com/watch?v=12345'), isNull);
    });
  });

  group('Spotify Title Sanitization Tests', () {
    test('cleanSpotifyTitle strips remasters, versions, and editions for clean matching', () {
      expect(
        PlaylistImportService.cleanSpotifyTitle('Single Again - 2022 Remaster'),
        'single again',
      );
      expect(
        PlaylistImportService.cleanSpotifyTitle('Bohemian Rhapsody - Remastered 2011'),
        'bohemian rhapsody',
      );
      expect(
        PlaylistImportService.cleanSpotifyTitle('Hotel California - Live On MTV, 1994'),
        'hotel california',
      );
      expect(
        PlaylistImportService.cleanSpotifyTitle('Plastic Love (Extended Club Mix)'),
        'plastic love',
      );
      expect(
        PlaylistImportService.cleanSpotifyTitle('About You - Radio Edit'),
        'about you',
      );
    });
  });

  group('4-Pass Matching & Karaoke Rejection Tests', () {
    final candidateTrack = Track(
      id: 'yt_1',
      title: 'Plastic Love',
      artist: 'Mariya Takeuchi',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      durationSeconds: 295,
      extraData: const {'itemType': 'song'},
    );

    final japaneseCandidate = Track(
      id: 'yt_2',
      title: 'プラスティック・ラブ',
      artist: '竹内まりや',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      durationSeconds: 295,
      extraData: const {'itemType': 'song'},
    );

    final karaokeTrack = Track(
      id: 'yt_karaoke',
      title: 'Plastic Love (Karaoke Version)',
      artist: 'Sing King Karaoke',
      thumbnailUrl: '',
      durationSeconds: 295,
    );

    test('doesCandidateMatchArtist matches Latin and cross-script Japanese artists', () {
      final words = ['mariya', 'takeuchi'];
      expect(
        PlaylistImportService.doesCandidateMatchArtist(
            candidateTrack, words, 'Mariya Takeuchi'),
        isTrue,
      );
      expect(
        PlaylistImportService.doesCandidateMatchArtist(
            japaneseCandidate, words, 'Mariya Takeuchi'),
        isTrue,
      );
    });

    test('doesCandidateMatchTitle matches cross-script loanword titles', () {
      expect(
        PlaylistImportService.doesCandidateMatchTitle(
            candidateTrack, 'Plastic Love'),
        isTrue,
      );
      expect(
        PlaylistImportService.doesCandidateMatchTitle(
            japaneseCandidate, 'Plastic Love'),
        isTrue,
      );
    });

    test('rejects karaoke and derivative channels from matching as authentic artist', () {
      final words = ['mariya', 'takeuchi'];
      expect(
        PlaylistImportService.doesCandidateMatchArtist(
            karaokeTrack, words, 'Mariya Takeuchi'),
        isFalse,
      );
    });
  });

  group('PlaylistService & Provider Custom Cover & Import Integration Tests', () {
    late PlaylistService playlistService;
    late PlayerProvider player;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      playlistService = PlaylistService();
      player = PlayerProvider();
    });

    tearDown(() {
      player.dispose();
    });

    test('PlaylistService.createPlaylist respects explicit coverUrl from imported playlist', () async {
      final track1 = Track(
        id: 't_1',
        title: 'Song 1',
        artist: 'Artist 1',
        thumbnailUrl: 'https://example.com/thumb1.jpg',
        durationSeconds: 200,
      );

      const customCover = 'https://example.com/spotify_cover.jpg';
      final playlist = await playlistService.createPlaylist(
        'Chill Vibes',
        description: 'Imported from Spotify',
        initialTracks: [track1],
        coverUrl: customCover,
      );

      expect(playlist.title, 'Chill Vibes');
      expect(playlist.description, 'Imported from Spotify');
      expect(playlist.coverUrl, customCover);
      expect(playlist.tracks.length, 1);
    });
  });
}
