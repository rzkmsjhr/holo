import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/services/taste_profile_service.dart';

void main() {
  test('TasteProfileService records plays and generates mixes', () async {
    SharedPreferences.setMockInitialValues({});

    final service = TasteProfileService();
    await service.init();

    final sampleTrack = Track(
      id: 'test_1',
      title: 'yesterday',
      artist: 'Tyler Lewis',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      durationSeconds: 210,
      audioSource: 'youtube',
    );

    await service.recordPlay(sampleTrack);
    await service.recordFavorite(sampleTrack, true);

    final top = service.getTopArtists();
    expect(top, contains('tyler lewis'));

    final catalog = [
      sampleTrack,
      Track(
        id: 'test_2',
        title: 'shoot',
        artist: 'no na',
        thumbnailUrl: 'https://example.com/thumb2.jpg',
        durationSeconds: 180,
        audioSource: 'youtube',
      ),
    ];

    final mixes = await service.generateDailyMixes(fallbackCatalog: catalog);
    expect(mixes.length, greaterThanOrEqualTo(3));
    expect(mixes[0].badge, 'MIX 1');
    expect(mixes[0].tracks.isNotEmpty, isTrue);

    final chillMix = mixes.firstWhere((m) => m.id == 'mix_chill');
    expect(chillMix.title, equals('Chill Lounge'));
    expect(chillMix.badge, equals('CHILL'));
    expect(chillMix.tracks.isNotEmpty, isTrue);
  });

  test('TasteProfileService.isSpamOrBotTrack correctly identifies and filters bot spam channels', () {
    final spamTrack1 = Track(
      id: 'sp1',
      title: 'Lofi with a guitar when nobody is watching',
      artist: 'lofi benny',
      thumbnailUrl: '',
      durationSeconds: 120,
    );
    final spamTrack2 = Track(
      id: 'sp2',
      title: 'Chill Study Music',
      artist: 'Lofi Chillhop & LO-FI BEATS',
      thumbnailUrl: '',
      durationSeconds: 180,
    );
    final spamTrack3 = Track(
      id: 'sp3',
      title: 'Lofi Acoustic Pulse',
      artist: 'Vibrations of Nature, Relaxing Rain',
      thumbnailUrl: '',
      durationSeconds: 150,
    );
    final validTrack1 = Track(
      id: 'val1',
      title: 'Nothing',
      artist: 'Bruno Major',
      thumbnailUrl: '',
      durationSeconds: 162,
    );
    final validTrack2 = Track(
      id: 'val2',
      title: 'To the Bone',
      artist: 'Pamungkas',
      thumbnailUrl: '',
      durationSeconds: 345,
    );

    expect(TasteProfileService.isSpamOrBotTrack(spamTrack1), isTrue);
    expect(TasteProfileService.isSpamOrBotTrack(spamTrack2), isTrue);
    expect(TasteProfileService.isSpamOrBotTrack(spamTrack3), isTrue);
    expect(TasteProfileService.isSpamOrBotTrack(validTrack1), isFalse);
    expect(TasteProfileService.isSpamOrBotTrack(validTrack2), isFalse);
  });
}
