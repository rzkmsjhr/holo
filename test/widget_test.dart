import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:holo_music_player/main.dart';
import 'package:holo_music_player/providers/player_provider.dart';

void main() {
  testWidgets('Holo smoke test', (WidgetTester tester) async {
    final player = PlayerProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const HoloMusicPlayerApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(HoloMusicPlayerApp), findsOneWidget);
    player.dispose();
  });
}
