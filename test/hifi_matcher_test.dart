import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/hifi_matcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HifiMatcher Eligibility & Noise Filtering', () {
    test('rejects video item types and vevo channels', () {
      final videoTrack = Track(
        id: 'vid1',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        thumbnailUrl: '',
        durationSeconds: 233,
        extraData: {'itemType': 'video'},
      );
      expect(HifiMatcher.isEligibleTrack(videoTrack), isFalse);

      final vevoTrack = Track(
        id: 'vevo1',
        title: 'Anti-Hero',
        artist: 'TaylorSwiftVEVO',
        thumbnailUrl: '',
        durationSeconds: 200,
      );
      expect(HifiMatcher.isEligibleTrack(vevoTrack), isFalse);
    });

    test('rejects live concerts, dance practices, and trailers while allowing official video/visualizer titles', () {
      final mvTrack = Track(
        id: '1',
        title: 'Hype Boy [Official MV]',
        artist: 'NewJeans',
        thumbnailUrl: '',
        durationSeconds: 180,
      );
      // Official music video uploads on YouTube are eligible to match studio FLAC
      expect(HifiMatcher.isEligibleTrack(mvTrack), isTrue);

      final visualizerTrack = Track(
        id: '3',
        title: 'Starboy (Official Visualizer)',
        artist: 'The Weeknd',
        thumbnailUrl: '',
        durationSeconds: 230,
      );
      expect(HifiMatcher.isEligibleTrack(visualizerTrack), isTrue);

      final liveTrack = Track(
        id: '2',
        title: 'Bohemian Rhapsody (Live at Wembley)',
        artist: 'Queen',
        thumbnailUrl: '',
        durationSeconds: 350,
      );
      expect(HifiMatcher.isEligibleTrack(liveTrack), isFalse);

      final dancePracticeTrack = Track(
        id: '4',
        title: 'Drama (Dance Practice)',
        artist: 'aespa',
        thumbnailUrl: '',
        durationSeconds: 210,
      );
      expect(HifiMatcher.isEligibleTrack(dancePracticeTrack), isFalse);
    });

    test('rejects karaoke, backing tracks, covers, and sped up / slowed derivatives', () {
      final karaokeTrack = Track(
        id: '4',
        title: 'Teman Bahagia (Karaoke Version)',
        artist: 'Jaz',
        thumbnailUrl: '',
        durationSeconds: 210,
      );
      expect(HifiMatcher.isEligibleTrack(karaokeTrack), isFalse);

      final spedUpTrack = Track(
        id: '5',
        title: 'Interaksi - Sped Up',
        artist: 'Tulus',
        thumbnailUrl: '',
        durationSeconds: 150,
      );
      expect(HifiMatcher.isEligibleTrack(spedUpTrack), isFalse);

      final coverTrack = Track(
        id: '6',
        title: 'Sialan (Acoustic Guitar Cover)',
        artist: 'Juicy Luicy',
        thumbnailUrl: '',
        durationSeconds: 240,
      );
      expect(HifiMatcher.isEligibleTrack(coverTrack), isFalse);
    });

    test('allows clean studio tracks', () {
      final studioTrack = Track(
        id: '7',
        title: 'Teman Bahagia',
        artist: 'Jaz',
        thumbnailUrl: '',
        durationSeconds: 220,
      );
      expect(HifiMatcher.isEligibleTrack(studioTrack), isTrue);
    });
  });

  group('HifiMatcher Artist Matching & Cross-Script Aliases', () {
    test('matches exact artist and normalized token variations', () {
      expect(HifiMatcher.doesArtistMatch('Tulus', 'Tulus', 'Interaksi'), isTrue);
      expect(HifiMatcher.doesArtistMatch('The Weeknd', 'Weeknd', 'Blinding Lights'), isTrue);
      expect(HifiMatcher.doesArtistMatch('Jaz - Topic', 'Jaz', 'Teman Bahagia'), isTrue);
    });

    test('matches cross-script aliases', () {
      expect(HifiMatcher.doesArtistMatch('Mariya Takeuchi', '竹内まりや', 'Single Again'), isTrue);
      expect(HifiMatcher.doesArtistMatch('IU', '아이유', 'Through the Night'), isTrue);
      expect(HifiMatcher.doesArtistMatch('Amr Diab', 'عمرو دياب', 'Tamally Maak'), isTrue);
      expect(HifiMatcher.doesArtistMatch('Nont Tanont', 'นนท์ ธนนท์', 'พิง'), isTrue);
    });

    test('rejects completely different artists sharing substring tokens', () {
      expect(HifiMatcher.doesArtistMatch('Taylor Swift', 'Tyler, The Creator', 'Song'), isFalse);
      expect(HifiMatcher.doesArtistMatch('Alan Walker', 'Al Green', 'Song'), isFalse);
    });

    test('rejects candidate with unwanted feat./ft.', () {
      expect(
        HifiMatcher.doesArtistMatch('Dewa 19', 'Dewa 19 feat. Virzha', 'Aku Milikmu'),
        isFalse,
      );
    });
  });

  group('HifiMatcher Version Flags & Conflict Resolution', () {
    test('detects version conflicts', () {
      final studioFlags = EditionMatrix.detect('Teman Bahagia');
      final acousticFlags = EditionMatrix.detect('Teman Bahagia (Acoustic)');
      final liveFlags = EditionMatrix.detect('Teman Bahagia (Live)');

      expect(EditionMatrix.hasConflict(studioFlags, acousticFlags), isTrue);
      expect(EditionMatrix.hasConflict(studioFlags, liveFlags), isTrue);
      expect(EditionMatrix.hasConflict(acousticFlags, liveFlags), isTrue);
      expect(EditionMatrix.hasConflict(studioFlags, studioFlags), isFalse);
    });
  });

  group('HifiMatcher Upstream Remake Blacklist', () {
    test('blocks known upstream 2021 remakes from matching classic originals', () {
      expect(
        HifiMatcher.isKnownUpstreamMismatch(
          '168395054749057024',
          'Aku Milikmu',
          'Dewa 19',
        ),
        isTrue,
      );
      expect(
        HifiMatcher.isKnownUpstreamMismatch(
          '168395069831774208',
          'Tak Kan Ada Cinta Yang Lain',
          'Dewa 19',
        ),
        isTrue,
      );
    });
  });

  group('HifiMatcher Candidate Scoring', () {
    test('awards high score for exact artist, title, and duration', () {
      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Interaksi',
        targetArtist: 'Tulus',
        targetDurSecs: 170,
        candId: 'kuwo_12345',
        candTitle: 'Interaksi',
        candArtist: 'Tulus',
        candDurSecs: 170,
      );
      expect(score, greaterThanOrEqualTo(150));
    });

    test('rejects candidate if artist does not match (returns 0)', () {
      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Interaksi',
        targetArtist: 'Tulus',
        targetDurSecs: 170,
        candId: 'kuwo_99999',
        candTitle: 'Interaksi',
        candArtist: 'Juicy Luicy',
        candDurSecs: 170,
      );
      expect(score, equals(0));
    });

    test('rejects candidate if title does not match (returns 0)', () {
      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Interaksi',
        targetArtist: 'Tulus',
        targetDurSecs: 170,
        candId: 'kuwo_55555',
        candTitle: 'Monokrom',
        candArtist: 'Tulus',
        candDurSecs: 170,
      );
      expect(score, equals(0));
    });

    test('rejects candidate if duration difference exceeds tolerance (returns 0)', () {
      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Interaksi',
        targetArtist: 'Tulus',
        targetDurSecs: 170,
        candId: 'kuwo_77777',
        candTitle: 'Interaksi',
        candArtist: 'Tulus',
        candDurSecs: 260, // 90 seconds difference
      );
      expect(score, equals(0));
    });

    test('rejects candidate if version flags conflict (returns 0)', () {
      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Teman Bahagia',
        targetArtist: 'Jaz',
        targetDurSecs: 220,
        candId: 'kuwo_88888',
        candTitle: 'Teman Bahagia (Acoustic Version)',
        candArtist: 'Jaz',
        candDurSecs: 220,
      );
      expect(score, equals(0));
    });

    test('awards bonus points for matching album metadata', () {
      final scoreWithoutAlbum = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'To the Bone',
        targetArtist: 'Pamungkas',
        targetDurSecs: 345,
        candId: 'kuwo_99999',
        candTitle: 'To the Bone',
        candArtist: 'Pamungkas',
        candDurSecs: 345,
      );

      final scoreWithMatchingAlbum = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'To the Bone',
        targetArtist: 'Pamungkas',
        targetDurSecs: 345,
        targetAlbum: 'Flying Solo',
        candId: 'kuwo_99999',
        candTitle: 'To the Bone',
        candArtist: 'Pamungkas',
        candAlbum: 'Flying Solo',
        candDurSecs: 345,
      );

      expect(scoreWithMatchingAlbum, greaterThan(scoreWithoutAlbum));
      expect(scoreWithMatchingAlbum - scoreWithoutAlbum, equals(65));
    });
  });

  group('HifiMatcher Persistent Caching & Freshness', () {
    test('HifiMatcher resolves cached FLAC synchronously via getCachedHiFi', () async {
      final matcher = HifiMatcher();
      final track = Track(
        id: 'pamungkas_bone',
        title: 'To the Bone',
        artist: 'Pamungkas',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        durationSeconds: 345,
      );

      final elevated = track.copyWith(
        flacStreamUrl: 'https://cdn.kuwo.cn/flac/test.flac',
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC',
      );

      SharedPreferences.setMockInitialValues({
        'holo_hifi_cache_v12': jsonEncode({
          'pamungkas_bone': elevated.toJson(),
        }),
      });

      await matcher.init();
      final retrieved = matcher.getCachedHiFi(track);
      expect(retrieved, isNotNull);
      expect(retrieved!.isLossless, isTrue);
      expect(retrieved.audioSource, equals('kuwo'));
      expect(retrieved.flacStreamUrl, equals('https://cdn.kuwo.cn/flac/test.flac'));
    });

    test('cleans up legacy cache keys including v11', () async {
      final matcher = HifiMatcher();
      SharedPreferences.setMockInitialValues({
        'holo_hifi_cache_v11': '{"old":"data"}',
        'holo_hifi_cache_v2': '{"old2":"data"}',
      });

      await matcher.init();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('holo_hifi_cache_v11'), isFalse);
      expect(prefs.containsKey('holo_hifi_cache_v2'), isFalse);
    });
  });

  group('HifiMatcher Minus-One & Instrumental Exclusions', () {
    test('detects all minus-one, backing track, and karaoke variants as instrumental edition', () {
      final variants = [
        'Alamak - Minus One',
        'Alamak (Minus-One)',
        'Alamak - Minus 1',
        'Alamak (Instrumen)',
        'Alamak (Inst.)',
        'Alamak - Karaoke',
        'Alamak (Karoke)',
        'Alamak (Tanpa Vokal)',
        'Alamak (No Vocal)',
        'Alamak (伴奏)',
        'Alamak (原版伴奏)',
        'Alamak (纯音乐)',
        'Alamak (伴唱)',
        'Alamak (消音)',
      ];

      for (final title in variants) {
        final editions = EditionMatrix.detect(title);
        expect(
          editions.contains(EditionKind.instrumental),
          isTrue,
          reason: 'Failed to flag "$title" as instrumental/minus-one',
        );
      }
    });

    test('strictly rejects minus-one and backing track candidates for vocal targets (returns 0)', () {
      final minusOneVariants = [
        'Alamak - Minus One',
        'Alamak (Minus-One)',
        'Alamak - Minus 1',
        'Alamak (Instrumen)',
        'Alamak (Inst.)',
        'Alamak (Karaoke Version)',
        'Alamak (Karoke)',
        'Alamak (Tanpa Vokal)',
        'Alamak (No Vocal)',
        'Alamak (伴奏)',
        'Alamak (原版伴奏)',
        'Alamak (纯音乐)',
        'Alamak (伴唱)',
        'Alamak (消音)',
      ];

      for (final candTitle in minusOneVariants) {
        final score = HifiMatcher.scoreTrackCandidate(
          targetTitle: 'Alamak',
          targetArtist: 'Rizky Febian',
          targetDurSecs: 209,
          candId: 'kuwo_123',
          candTitle: candTitle,
          candArtist: 'Rizky Febian',
          candDurSecs: 209,
        );
        expect(
          score,
          equals(0),
          reason: 'Expected 0 score for minus-one candidate "$candTitle", got $score',
        );
      }
    });
  });
}
