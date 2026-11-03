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

  test('GenreExploreService personalizes genres with likedTracks having high affinity', () {
    final likedIndieTrack = Track(
      id: 'indie_1',
      title: 'About You',
      artist: 'The 1975',
      album: 'Being Funny In A Foreign Language',
      durationSeconds: 326,
      thumbnailUrl: 'https://example.com/the1975.jpg',
    );

    final playedPopTrack = Track(
      id: 'pop_1',
      title: 'Cruel Summer',
      artist: 'Taylor Swift',
      album: 'Lover',
      durationSeconds: 178,
      thumbnailUrl: 'https://example.com/taylor.jpg',
    );

    final personalized = GenreExploreService.personalizeGenres(
      topArtists: [],
      recentTracks: [playedPopTrack],
      likedTracks: [likedIndieTrack],
    );

    // Liked track has weight 3, played track has weight 1
    // Therefore Indie & Alt should be ranked higher than Pop Hits
    final indieGenre = personalized.firstWhere((g) => g.id == 'indie_alt');
    final popGenre = personalized.firstWhere((g) => g.id == 'pop');

    expect(personalized.indexOf(indieGenre), lessThan(personalized.indexOf(popGenre)));
    expect(indieGenre.candidates.first.artist, equals('The 1975'));
    expect(popGenre.candidates.first.artist, equals('Taylor Swift'));
  });
}
