import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/artwork_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Track Transition & Artwork Normalization Tests', () {
    test('Artwork matching matches canonical and radio edit variants', () {
      final key1 = ArtworkService.cleanForMatching('One More Time');
      final key2 = ArtworkService.cleanForMatching('One More Time (Radio Edit)');
      final key3 = ArtworkService.cleanForMatching('One More Time (Remastered 2021)');
      final key4 = ArtworkService.cleanForMatching('One More Time [Official Audio]');
      final key5 = ArtworkService.cleanForMatching('One More Time feat. Romanthony');

      expect(key1, 'one more time');
      expect(key2, 'one more time');
      expect(key3, 'one more time');
      expect(key4, 'one more time');
      expect(key5, 'one more time');
    });

    test('Artist cleanForMatching handles feat, topic, and whitespace', () {
      final a1 = ArtworkService.cleanForMatching('Daft Punk');
      final a2 = ArtworkService.cleanForMatching('Daft Punk - Topic');
      final a3 = ArtworkService.cleanForMatching('Daft Punk feat. Pharrell');

      expect(a1, 'daft punk');
      expect(a2, 'daft punk');
      expect(a3, 'daft punk');
    });

    test('ArtworkService caches under canonical key and retrieves for variants', () async {
      final service = ArtworkService();
      await service.init();

      // Simulate populating cache for canonical track
      SharedPreferences.setMockInitialValues({
        'artwork_cache_v5_clean': '{"daft punk - one more time":"https://is1-ssl.mzstatic.com/image/thumb/Music/daftpunk.jpg"}',
      });
      final service2 = ArtworkService();
      await service2.init();

      // Retrieve via canonical name
      final art1 = service2.getCached('Daft Punk', 'One More Time');
      expect(art1, equals('https://is1-ssl.mzstatic.com/image/thumb/Music/daftpunk.jpg'));

      // Retrieve via variant name (Radio Edit)
      final art2 = service2.getCached('Daft Punk', 'One More Time (Radio Edit)');
      expect(art2, equals('https://is1-ssl.mzstatic.com/image/thumb/Music/daftpunk.jpg'));

      // Retrieve via Topic channel variant
      final art3 = service2.getCached('Daft Punk - Topic', 'One More Time');
      expect(art3, equals('https://is1-ssl.mzstatic.com/image/thumb/Music/daftpunk.jpg'));
    });

    test('Track model holds highResThumbnailUrl and toHighResUrl correctly upgrades', () {
      final t = Track(
        id: 'wU26xVT_vBU',
        title: 'One More Time',
        artist: 'Daft Punk',
        thumbnailUrl: 'https://i.ytimg.com/vi/wU26xVT_vBU/default.jpg',
        durationSeconds: 321,
      );

      expect(t.highResThumbnailUrl, 'https://i.ytimg.com/vi/wU26xVT_vBU/hqdefault.jpg');
    });
  });
}
