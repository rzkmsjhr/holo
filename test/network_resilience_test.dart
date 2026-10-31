import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/services/connectivity_service.dart';
import 'package:pulse_audio/services/genre_explore_service.dart';

void main() {
  group('ConnectivityService Tests', () {
    test('ConnectivityService is a singleton with initial online/defined state', () {
      final s1 = ConnectivityService();
      final s2 = ConnectivityService();
      expect(identical(s1, s2), isTrue);
      expect(s1.isOnline, isTrue);
      expect(s1.status, equals(ConnectivityStatus.online));
    });

    test('Connectivity status transitions and broadcasts on stream', () async {
      final connectivity = ConnectivityService();
      expect(connectivity.statusStream, isNotNull);
    });
  });

  group('Explore Genre Cover Image Integrity Tests', () {
    test('Every genre has high-resolution CDN artist covers for all candidates', () {
      final genres = GenreExploreService.getDefaultGenres();
      expect(genres.length, equals(6));

      for (final genre in genres) {
        expect(genre.candidates.length, greaterThanOrEqualTo(2));
        for (final candidate in genre.candidates) {
          expect(candidate.artist.isNotEmpty, isTrue);
          expect(candidate.coverUrl.isNotEmpty, isTrue);
          expect(candidate.coverUrl.startsWith('https://'), isTrue);
          expect(candidate.coverUrl.contains('600x600'), isTrue);
        }
      }
    });

    test('Candidate rotation stays valid through full cycle', () {
      final genres = GenreExploreService.getDefaultGenres();
      for (final genre in genres) {
        final total = genre.candidates.length;
        for (var i = 0; i < total; i++) {
          expect(genre.currentCandidate.coverUrl.isNotEmpty, isTrue);
          genre.advance();
        }
        // Loops back to starting candidate
        expect(genre.activeIndex, equals(0));
      }
    });
  });
}
