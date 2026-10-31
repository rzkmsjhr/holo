import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/player_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/search_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/widgets/mini_player.dart';
import 'ui/widgets/bottom_nav_bar.dart';
import 'ui/widgets/network_status_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ],
      child: const PulseAudioApp(),
    ),
  );
}

class PulseAudioApp extends StatelessWidget {
  const PulseAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return MaterialApp(
      title: 'Holo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: player.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentTabIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  static const MethodChannel _appChannel = MethodChannel('com.example.holo/app');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentTabIndex != 0) {
          // If on Search or Library tab, return to Home tab first
          setState(() => _currentTabIndex = 0);
        } else {
          // If at Home tab, minimize the app to the background without stopping music
          try {
            await _appChannel.invokeMethod('minimize');
          } catch (_) {
            // Fallback for non-Android platforms
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Screen Stack with adaptive Network Status Header
            Column(
              children: [
                const NetworkStatusBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _currentTabIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),

            // Floating Mini Player (Positioned directly above the bottom nav bar)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 78,
              child: MiniPlayer(),
            ),

            // Standard Bottom Navigation Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavBar(
                currentIndex: _currentTabIndex,
                onTabSelected: (index) {
                  setState(() => _currentTabIndex = index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
