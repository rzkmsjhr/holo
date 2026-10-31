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
  });
}
