import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/artist_details.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/artist_service.dart';

void main() {
  group('ArtistDetails & ArtistRelease Model Tests', () {
    test('ArtistRelease correctly upgrades thumbnail and stores properties', () {
      const release = ArtistRelease(
        title: 'PRIMA',
        year: '2026',
        type: 'Album',
        browseId: 'MPREb_BtXfAQVI3yJ',
        thumbnailUrl: 'https://yt3.googleusercontent.com/test=w120-h120',
      );

      expect(release.title, 'PRIMA');
      expect(release.year, '2026');
      expect(release.type, 'Album');
      expect(release.browseId, 'MPREb_BtXfAQVI3yJ');
      expect(release.highResThumbnailUrl, contains('=w800-h800-l90-rj'));
    });

    test('ArtistDetails effectiveImage prioritizes banner over avatar', () {
      final details = ArtistDetails(
        name: 'ADÉLA',
        browseId: 'UC0tecxozlRzTMrqvShI8QWg',
        bannerUrl: 'https://yt3.googleusercontent.com/banner=w120-h120',
        avatarUrl: 'https://yt3.googleusercontent.com/avatar=w120-h120',
        topSongs: [
          Track(
            id: 'h-zuG75Ds-w',
            title: 'Nicole Kidman',
            artist: 'ADÉLA',
            thumbnailUrl: 'https://yt3.googleusercontent.com/thumb=w120-h120',
            durationSeconds: 180,
          ),
        ],
      );

      expect(details.effectiveImage, contains('banner'));
      expect(details.topSongs.length, 1);
      expect(details.topSongs.first.title, 'Nicole Kidman');
    });

    test('ArtistDetails effectiveImage falls back to avatar when banner is missing', () {
      const details = ArtistDetails(
        name: 'ADÉLA',
        browseId: 'UC0tecxozlRzTMrqvShI8QWg',
        bannerUrl: null,
        avatarUrl: 'https://yt3.googleusercontent.com/avatar=w120-h120',
        topSongs: [],
      );

      expect(details.effectiveImage, contains('avatar'));
    });
  });

  group('ArtistService Integration Tests', () {
    test('ArtistService resolves and retrieves artist details for ADÉLA', () async {
      final service = ArtistService();
      final details = await service.getArtistDetails('ADÉLA');

      expect(details.name, isNotEmpty);
      expect(details.topSongs, isNotEmpty);
      expect(details.topSongs.any((t) => t.title.toLowerCase().contains('nicole kidman') || t.title.toLowerCase().contains('la')), isTrue);
    });
  });
}
