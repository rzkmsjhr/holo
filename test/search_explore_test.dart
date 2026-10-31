import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/genre_explore_service.dart';

void main() {
  test('GenreExploreService returns default genres with candidates', () {
    final genres = GenreExploreService.getDefaultGenres();
    expect(genres.isNotEmpty, isTrue);
    expect(genres.any((g) => g.title == 'Electronic'), isTrue);
    expect(genres.any((g) => g.title == 'Synthwave'), isTrue);
    expect(genres.any((g) => g.title == 'Acoustic'), isTrue);
    expect(genres.any((g) => g.title == 'R&B Soul'), isTrue);

    for (final g in genres) {
      expect(g.candidates.isNotEmpty, isTrue);
      expect(g.currentCandidate.coverUrl.isNotEmpty, isTrue);
    }
  });

  test('GenreExploreService personalizes genres based on user taste', () {
    final newAcousticTrack = Track(
      id: 'f1',
      title: 'Runtuh',
      artist: 'Feby Putri',
      album: 'Riuh',
      durationSeconds: 220,
      thumbnailUrl: 'https://example.com/feby.jpg',
    );

    // Personalize with newly played artist
    final personalized = GenreExploreService.personalizeGenres(
      topArtists: ['Feby Putri'],
      recentTracks: [newAcousticTrack],
    );

    // Acoustic genre should be prioritized to top
    final acousticGenre = personalized.firstWhere((g) => g.id == 'acoustic');
    expect(acousticGenre.candidates.first.artist, equals('Feby Putri'));
    expect(acousticGenre.candidates.first.coverUrl,
        equals('https://example.com/feby.jpg'));
    expect(personalized.first.id, equals('acoustic'));

    // Genre advances candidate correctly
    final initialArtist = acousticGenre.currentCandidate.artist;
    acousticGenre.advance();
    expect(acousticGenre.currentCandidate.artist, isNot(equals(initialArtist)));
  });
}
