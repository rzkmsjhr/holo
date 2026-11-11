import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/trending_track.dart';
import 'package:pulse_audio/services/artwork_service.dart';
import 'package:pulse_audio/services/hifi_matcher.dart';
import 'package:pulse_audio/services/trending_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Track Identity and Artwork Sanitization Tests', () {
    test('ArtworkService.isSquareAlbumArtworkUrl recognizes genuine square CDN album art', () {
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg',
        ),
        isTrue,
      );
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(
          'https://lh3.googleusercontent.com/some_album_hash=w544-h544-l90-rj',
        ),
        isTrue,
      );
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(
          'https://i.scdn.co/image/ab67616d0000b273abc123',
        ),
        isTrue,
      );
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(
          'https://star.kuwo.cn/star/starheads/500/123.jpg',
        ),
        isTrue,
      );

      // 16:9 YouTube video thumbnail frames must NOT be treated as square album artwork
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(
          'https://i.ytimg.com/vi/H1Cw7Gm6P7I/hqdefault.jpg',
        ),
        isFalse,
      );
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(''),
        isFalse,
      );
      expect(
        ArtworkService.isSquareAlbumArtworkUrl(null),
        isFalse,
      );
    });

    test('HifiMatcher.doesArtistMatch strictly rejects third-party upload channels', () {
      // Channel "AS Tone" impersonating "Tulus"
      final isMatch = HifiMatcher.doesArtistMatch('Tulus', 'AS Tone', 'Teh Hijau');
      expect(isMatch, isFalse);

      // Legitimate artist match
      expect(HifiMatcher.doesArtistMatch('Tulus', 'Tulus', 'Teh Hijau'), isTrue);
      expect(HifiMatcher.doesArtistMatch('Tulus', 'Tulus - Topic', 'Teh Hijau'), isTrue);
    });

    test('TrendingService fast-paths snapshot tracks with existing youtubeVideoId and square art', () async {
      final trendingService = TrendingService();
      const item = TrendingTrack(
        rank: 1,
        trend: '=',
        plays: '1,000,000',
        query: 'Tulus Teh Hijau',
        title: 'Teh Hijau',
        artist: 'Tulus',
        youtubeVideoId: '5F28ye50-Kc',
        thumbnailUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/v4/600x600bb.jpg',
      );

      final track = await trendingService.resolveTrack(item);

      // Verified video ID and square thumbnail must be preserved exactly
      expect(track, isNotNull);
      expect(track!.youtubeVideoId, equals('5F28ye50-Kc'));
      expect(track.thumbnailUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/Music/v4/600x600bb.jpg'));
      expect(track.title, equals('Teh Hijau'));
      expect(track.artist, equals('Tulus'));
    });
  });
}
