import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';
import 'package:pulse_audio/services/trending_service.dart';
import 'package:pulse_audio/services/vibe_recommendation_service.dart';
import 'package:pulse_audio/services/youtube_music_service.dart';

void main() {
  group('Step 4 Parity: High-Res Cover Art Optimization', () {
    test('transforms googleusercontent and ggpht to 800x800 with l90-rj', () {
      const url1 =
          'https://lh3.googleusercontent.com/somerandomstring=w120-h120-l90-rj';
      expect(Track.toHighResUrl(url1),
          'https://lh3.googleusercontent.com/somerandomstring=w800-h800-l90-rj');

      const url2 = 'https://lh3.googleusercontent.com/somerandomstring=s120';
      expect(Track.toHighResUrl(url2),
          'https://lh3.googleusercontent.com/somerandomstring=s800');

      const url3 = 'https://yt3.ggpht.com/channelart=w544-h544-p-l90-rj';
      expect(Track.toHighResUrl(url3),
          'https://yt3.ggpht.com/channelart=w800-h800-l90-rj');
    });

    test('normalizes ytimg URLs to guaranteed hqdefault.jpg', () {
      const url = 'https://i.ytimg.com/vi/abc123xyz89/maxresdefault.jpg';
      expect(Track.toHighResUrl(url),
          'https://i.ytimg.com/vi/abc123xyz89/hqdefault.jpg');

      const url2 = 'https://i.ytimg.com/vi/abc123xyz89/mqdefault.jpg';
      expect(Track.toHighResUrl(url2),
          'https://i.ytimg.com/vi/abc123xyz89/hqdefault.jpg');
    });
  });

  group('Step 1 Parity: Video & Derivative Detection', () {
    test('isVideoRecord accurately detects music videos and visualizers', () {
      expect(
          YouTubeMusicService.isVideoRecord(
              'Plastic Love (Official Music Video)', 'Warner Music Japan'),
          isTrue);
      expect(
          YouTubeMusicService.isVideoRecord(
              'Stay With Me [MV]', 'Pony Canyon'),
          isTrue);
      expect(
          YouTubeMusicService.isVideoRecord(
              'Saujana (Lyric Video)', 'Bilal Indrajaya'),
          isTrue);
      expect(
          YouTubeMusicService.isVideoRecord(
              'Daylight', 'David Kushner VEVO'),
          isTrue);
      expect(
          YouTubeMusicService.isVideoRecord(
              'Fly-Day Chinatown', 'Yasuha - Topic'),
          isFalse);
    });

    test('isKaraokeOrDerivative flags karaoke, covers, key shifts and megamixes', () {
      final badCandidate = Track(
        id: '1',
        title: 'Plastic Love [Bass Cover] +4Key',
        artist: 'GuitaristKen',
        thumbnailUrl: '',
        durationSeconds: 240,
        extraData: {'itemType': 'song'},
      );
      final qWords = ['plastic', 'love'];
      final score = YouTubeMusicService.scoreSearchCandidate(
          badCandidate, qWords, 'Plastic Love');
      // Should receive heavy karaoke/derivative penalty (+1000)
      expect(score, greaterThanOrEqualTo(1000));
    });

    test('katakanaToRomaji transliterates Katakana loanwords', () {
      expect(YouTubeMusicService.katakanaToRomaji('シングル'), 'shinguru');
      expect(YouTubeMusicService.katakanaToRomaji('アゲイン'), 'agein');
      expect(YouTubeMusicService.katakanaToRomaji('プラスティック'), 'purasutiku');
      expect(YouTubeMusicService.katakanaToRomaji('サンセット'), 'sanseto');
      expect(YouTubeMusicService.katakanaToRomaji('ロード'), 'rodo');
    });

    test('titleMatchesTerm handles cross-script Japanese/English matching', () {
      expect(
          YouTubeMusicService.titleMatchesTerm(
              'single again', 'シングル'),
          isTrue);
      expect(
          YouTubeMusicService.titleMatchesTerm(
              'plastic love', 'プラスティック'),
          isTrue);
      expect(
          YouTubeMusicService.titleMatchesTerm(
              'sunset road', 'サンセット'),
          isTrue);
    });
  });

  group('Step 1 Parity: 7-Track Artist Spacing Algorithm', () {
    test('spaceOutArtistTracks keeps same-artist tracks >= 7 tracks apart', () {
      final tracks = [
        Track(id: '1', title: 'Song 1', artist: 'Artist A - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '2', title: 'Song 2', artist: 'Artist A - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '3', title: 'Song 3', artist: 'Artist B - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '4', title: 'Song 4', artist: 'Artist C - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '5', title: 'Song 5', artist: 'Artist D - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '6', title: 'Song 6', artist: 'Artist E - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '7', title: 'Song 7', artist: 'Artist F - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '8', title: 'Song 8', artist: 'Artist G - Topic', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '9', title: 'Song 9', artist: 'Artist H - Topic', thumbnailUrl: '', durationSeconds: 200),
      ];

      final spaced = YouTubeMusicService.spaceOutArtistTracks(tracks);
      expect(spaced.length, 9);
      expect(spaced[0].artist, contains('Artist A'));
      // Artist A's second song must NOT be at index 1! It should be spaced at least 7 tracks apart
      expect(spaced[1].artist, isNot(contains('Artist A')));
      final firstIdx = spaced.indexWhere((t) => t.id == '1');
      final secondIdx = spaced.indexWhere((t) => t.id == '2');
      expect((secondIdx - firstIdx).abs(), greaterThanOrEqualTo(7));
    });
  });

  group('Step 2 Parity: Strict Anti-Back-to-Back Artist Guarantee', () {
    test('isSameArtist identifies identical, cross-script, and collaborating artists', () {
      final vibe = VibeRecommendationService();

      final trackA1 = Track(id: '1', title: 'Plastic Love', artist: '竹内まりや', thumbnailUrl: '', durationSeconds: 200);
      final trackA2 = Track(id: '2', title: 'Single Again', artist: 'Mariya Takeuchi - Topic', thumbnailUrl: '', durationSeconds: 200);
      expect(vibe.isSameArtist(trackA1, trackA2), isTrue,
          reason: 'Japanese / Latin artist pairs must match');

      final trackCollab1 = Track(id: '3', title: 'Baby I\'m Yours', artist: 'Breakbot feat. Irfane', thumbnailUrl: '', durationSeconds: 200);
      final trackCollab2 = Track(id: '4', title: 'Fantasy', artist: 'Breakbot', thumbnailUrl: '', durationSeconds: 200);
      expect(vibe.isSameArtist(trackCollab1, trackCollab2), isTrue,
          reason: 'Lead artist in collaboration must match solo track');

      final trackDiff = Track(id: '5', title: 'Stay With Me', artist: 'Miki Matsubara', thumbnailUrl: '', durationSeconds: 200);
      expect(vibe.isSameArtist(trackA1, trackDiff), isFalse,
          reason: 'Distinct artists must not match');
    });
  });

  group('Fixes & Features Parity Verification', () {
    test('OMV penalty vs Topic boost in scoreSearchCandidate', () {
      final omvCandidate = Track(
        id: 'vid1',
        title: 'Dear God (Official Music Video)',
        artist: 'Avenged Sevenfold',
        thumbnailUrl: '',
        durationSeconds: 333,
        extraData: {
          'itemType': 'video',
          'musicVideoType': 'MUSIC_VIDEO_TYPE_OMV',
        },
      );

      final topicCandidate = Track(
        id: 'song1',
        title: 'Dear God',
        artist: 'Avenged Sevenfold - Topic',
        thumbnailUrl: '',
        durationSeconds: 333,
        extraData: {
          'itemType': 'song',
          'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
        },
      );

      final qWords = ['dear', 'god'];
      final omvScore = YouTubeMusicService.scoreSearchCandidate(
          omvCandidate, qWords, 'Dear God');
      final topicScore = YouTubeMusicService.scoreSearchCandidate(
          topicCandidate, qWords, 'Dear God');

      expect(omvScore, greaterThanOrEqualTo(1000),
          reason: 'OMV music videos must receive at least +1000 penalty');
      expect(topicScore, lessThan(omvScore),
          reason: 'Studio - Topic / ATV song must rank significantly ahead of OMV');
    });

    test('PlayerProvider.spaceOutArtistTracks eliminates back-to-back artist conflicts', () {
      final tracks = [
        Track(id: '1', title: 'Song A1', artist: 'Artist A', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '2', title: 'Song A2', artist: 'Artist A', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '3', title: 'Song B1', artist: 'Artist B', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '4', title: 'Song C1', artist: 'Artist C', thumbnailUrl: '', durationSeconds: 200),
        Track(id: '5', title: 'Song A3', artist: 'Artist A', thumbnailUrl: '', durationSeconds: 200),
      ];

      final spaced = PlayerProvider.spaceOutArtistTracks(tracks);
      expect(spaced.length, 5);
      for (int i = 0; i < spaced.length - 1; i++) {
        expect(spaced[i].artist, isNot(equals(spaced[i + 1].artist)),
            reason: 'Consecutive tracks in queue must not be by the same artist');
      }
    });

    test('Trending countries catalog contains supported regions without requesting permissions', () {
      expect(kSupportedTrendingCountries.length, 18);
      expect(kSupportedTrendingCountries.any((c) => c.code == 'id'), isTrue);
      expect(kSupportedTrendingCountries.any((c) => c.code == 'us'), isTrue);
    });
  });
}
