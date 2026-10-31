import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/services/trending_service.dart';

void main() {
  test('TrendingService loads Global and Indonesia top 50 with plays', () async {
    final service = TrendingService();

    final global = await service.getTrending('global');
    expect(global.length, 50);
    expect(global.first.rank, 1);
    expect(global.first.plays.isNotEmpty, isTrue);
    expect(global.first.formattedPlays, contains('plays'));

    final indonesia = await service.getTrending('indonesia');
    expect(indonesia.length, 50);
    expect(indonesia.first.rank, 1);
    expect(indonesia.first.plays.isNotEmpty, isTrue);
    expect(indonesia.first.formattedPlays, contains('plays'));
  });
}
