import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/services/artwork_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'artwork_cache_v5_clean': jsonEncode({
        'tate mcrae - housewife':
            'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/2b/96/2b/2b962b77-3a04-5650-aefd-37ecfce04b03/196874840146.jpg/600x600bb.jpg',
      }),
    });
  });

  test('ArtworkService loads cached artworks and retrieves them', () async {
    final service = ArtworkService();
    await service.init();

    final cached = service.getCached('Tate McRae', 'Housewife');
    expect(cached, isNotNull);
    expect(cached!.contains('mzstatic.com'), isTrue);

    // Case-insensitive query
    final cachedLower = service.getCached('tate mcrae', 'housewife');
    expect(cachedLower, equals(cached));
  });
}
