import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pulse_audio/main.dart';
import 'package:pulse_audio/providers/player_provider.dart';

void main() {
  testWidgets('Pulse Audio smoke test', (WidgetTester tester) async {
    final player = PlayerProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const PulseAudioApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(PulseAudioApp), findsOneWidget);
    player.dispose();
  });
}
