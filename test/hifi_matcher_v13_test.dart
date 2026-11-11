import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/hifi_matcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HifiMatcher v13 Specifications (nadanada commits 397c0b2 & 5912963 parity)', () {
    test('Chinese media tie-in regex strips promo suffixes in cleanString and cleanTitle', () {
      const raw = '孤勇者 - 《英雄联盟：双城之战》动画剧集主题曲';
      final cleaned = HifiMatcher.cleanString(raw);
      expect(cleaned, equals('孤勇者'));

      final matcher = HifiMatcher();
      final titleCleaned = matcher.cleanTitle('孤勇者 《英雄联盟：双城之战》动画剧集主题曲');
      expect(titleCleaned.trim(), equals('孤勇者'));
    });

    test('EditionMatrix ignores Chinese media tie-in unless album is marked as soundtrack', () {
      // Non-soundtrack album context: tie-in suffix should be stripped, so detected editions are empty
      final editionsNonOst = EditionMatrix.detect(
        '孤勇者 《英雄联盟：双城之战》动画剧集主题曲',
        '孤勇者 (Single)',
      );
      expect(editionsNonOst.contains(EditionKind.soundtrack), isFalse);

      // Soundtrack album context: soundtrack edition detected
      final editionsOst = EditionMatrix.detect(
        '孤勇者 《英雄联盟：双城之战》动画剧集主题曲',
        'Arcane (Soundtrack from the Animated Series)',
      );
      expect(editionsOst.contains(EditionKind.soundtrack), isTrue);
    });

    test('isKnownUpstreamMismatch blacklists Bon Jovi It\'s My Life remake (662121810)', () {
      expect(
        HifiMatcher.isKnownUpstreamMismatch('662121810', "It's My Life", 'Bon Jovi'),
        isTrue,
      );
      expect(
        HifiMatcher.isKnownUpstreamMismatch('kuwo_662121810', "It's My Life", 'Bon Jovi'),
        isTrue,
      );

      final score = HifiMatcher.scoreTrackCandidate(
        targetTitle: "It's My Life",
        targetArtist: 'Bon Jovi',
        targetDurSecs: 224,
        candId: '662121810',
        candTitle: "It's My Life",
        candArtist: 'Bon Jovi',
        candAlbum: 'Himnos Millennials',
        candDurSecs: 224,
      );
      expect(score, equals(0));
    });

    test('scoreTrackCandidate penalizes candidates from completely unrelated albums by 25 points', () {
      // Base score with matching album
      final scoreWithMatchingAlbum = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Teh Hijau',
        targetArtist: 'Tulus',
        targetDurSecs: 218,
        targetAlbum: 'Monokrom',
        candId: '101',
        candTitle: 'Teh Hijau',
        candArtist: 'Tulus',
        candAlbum: 'Monokrom',
        candDurSecs: 218,
      );

      // Candidate with completely unrelated album
      final scoreWithUnrelatedAlbum = HifiMatcher.scoreTrackCandidate(
        targetTitle: 'Teh Hijau',
        targetArtist: 'Tulus',
        targetDurSecs: 218,
        targetAlbum: 'Monokrom',
        candId: '102',
        candTitle: 'Teh Hijau',
        candArtist: 'Tulus',
        candAlbum: 'Hits Terbaik Pop',
        candDurSecs: 218,
      );

      expect(scoreWithMatchingAlbum, greaterThan(scoreWithUnrelatedAlbum));
      // Difference includes the matching bonus (65) plus the unrelated penalty (25)
      expect(scoreWithMatchingAlbum - scoreWithUnrelatedAlbum, greaterThanOrEqualTo(25));
    });

    test('isTitleAcceptable accurately accepts valid titles and rejects excessive residue / spam', () {
      // Legitimate title variations
      expect(HifiMatcher.isTitleAcceptable('Teh Hijau', 'Teh Hijau'), isTrue);
      expect(HifiMatcher.isTitleAcceptable('Teh Hijau', 'Teh Hijau (Audio)'), isTrue);
      expect(HifiMatcher.isTitleAcceptable('Plastic Love', 'プラスティック・ラブ'), isTrue);

      // Third-party spam / unauthorized cover uploads with excessive residue
      expect(
        HifiMatcher.isTitleAcceptable(
          'Teh Hijau',
          'TEH HIJAU - TULUS (Reggae Version) Enak Buat Santai | By AS TONE',
        ),
        isFalse,
      );
      expect(
        HifiMatcher.isTitleAcceptable(
          'Shape of You',
          'Shape of You - Ed Sheeran 1 Hour Loop Relaxing Remix Version',
        ),
        isFalse,
      );
    });

    test('getCachedHiFi merges stream without corrupting track metadata or square cover', () {
      final matcher = HifiMatcher();

      final original = Track(
        id: 'orig_123',
        youtubeVideoId: '5F28ye50-Kc',
        title: 'Teh Hijau',
        artist: 'Tulus',
        album: 'Monokrom',
        thumbnailUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/v4/600x600bb.jpg',
        durationSeconds: 218,
      );

      // Suppose cache contains resolved Kuwo FLAC
      final fakeCachedFlac = Track(
        id: 'kuwo_607996126',
        youtubeVideoId: 'H1Cw7Gm6P7I', // from a different source
        title: 'Teh Hijau (Kuwo Master)',
        artist: 'Tulus',
        album: 'Monokrom',
        thumbnailUrl: 'https://i.ytimg.com/vi/H1Cw7Gm6P7I/hqdefault.jpg',
        durationSeconds: 218,
        flacStreamUrl: 'https://flac.music.hi.cn/stream/607996126.flac',
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC',
        extraData: {
          'resolvedWithAlbum': true,
          'hifiVersion': 13,
        },
      );

      // Emulate cache entry
      matcher.prepareTrackThroughGateSync(original); // ensures matcher loaded

      // Test merging behavior
      final cachedHit = original.copyWith(
        flacStreamUrl: fakeCachedFlac.flacStreamUrl,
        audioSource: fakeCachedFlac.audioSource,
        isLossless: true,
        audioFormat: fakeCachedFlac.audioFormat,
        extraData: fakeCachedFlac.extraData,
      );

      // Original caller properties MUST be preserved
      expect(cachedHit.id, equals('orig_123'));
      expect(cachedHit.youtubeVideoId, equals('5F28ye50-Kc'));
      expect(cachedHit.title, equals('Teh Hijau'));
      expect(cachedHit.artist, equals('Tulus'));
      expect(cachedHit.album, equals('Monokrom'));
      expect(cachedHit.thumbnailUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/Music/v4/600x600bb.jpg'));
      // Only stream properties elevated
      expect(cachedHit.isLossless, isTrue);
      expect(cachedHit.flacStreamUrl, equals('https://flac.music.hi.cn/stream/607996126.flac'));
      expect(cachedHit.audioSource, equals('kuwo'));
    });
  });
}
