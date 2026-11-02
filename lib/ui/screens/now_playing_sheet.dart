import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../widgets/live_equalizer_bars.dart';
import 'artist_screen.dart';
import 'queue_screen.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet>
    with SingleTickerProviderStateMixin {
  AnimationController? _animController;
  Animation<double>? _curvedAnim;

  Animation<double> get _anim =>
      _curvedAnim ?? const AlwaysStoppedAnimation(0.0);

  bool _isLyricsView = false;
  int _lastScrolledIndex = -1;
  String? _lastTrackId;
  final Map<int, GlobalKey> _lyricKeys = {};

  final ScrollController _playerScrollController = ScrollController();
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _playerScrollController.addListener(_onPlayerScroll);
  }

  void _initAnimation() {
    if (_animController == null) {
      _animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      );
      _curvedAnim = CurvedAnimation(
        parent: _animController!,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
    }
  }

  void _onPlayerScroll() {
    if (_playerScrollController.hasClients &&
        _playerScrollController.position.pixels > 35 &&
        !_isLyricsView) {
      _openLyrics();
    }
  }

  void _openLyrics() {
    if (_isLyricsView) return;

    _initAnimation();
    _lyricKeys.clear();
    _lastScrolledIndex = -1;
    setState(() => _isLyricsView = true);
    _animController?.forward();
  }

  void _showDebuggerLogsModal(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1117),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Stream Diagnostic Logs',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: player.debugLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs recorded yet. Play a song to record stream events.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: player.debugLogs.length,
                        itemBuilder: (context, i) {
                          final log = player.debugLogs[i];
                          final isErr = log.contains('error') ||
                              log.contains('failed') ||
                              log.contains('FAILURE') ||
                              log.contains('403') ||
                              log.contains('Exception');
                          final isSuccess = log.contains('SUCCESS') || log.contains('succeeded');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            child: Text(
                              log,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.3,
                                color: isErr
                                    ? const Color(0xFFF87171)
                                    : (isSuccess
                                        ? const Color(0xFF4ADE80)
                                        : Colors.white70),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToCenter(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _lyricKeys[index];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.48, // Locks active lyric directly in the vertical center
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      } else {
        // Retry on next frame if context was being rendered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final retryKey = _lyricKeys[index];
          if (retryKey?.currentContext != null) {
            Scrollable.ensureVisible(
              retryKey!.currentContext!,
              alignment: 0.48,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    });
  }

  void _closeLyrics() {
    if (!_isLyricsView) return;
    _animController?.reverse().then((_) {
      if (mounted) {
        setState(() => _isLyricsView = false);
      }
    });
  }

  void _openQueue(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const QueueScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  void _navigateToArtist(BuildContext context, String artistName) {
    final cleanName = artistName
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .trim();
    if (cleanName.isEmpty || cleanName.toLowerCase() == 'unknown artist') {
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistScreen(artistName: cleanName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  void _showAlbumArtPopup(BuildContext context, Track track) {
    final player = context.read<PlayerProvider>();
    final imgUrl = track.highResThumbnailUrl.isNotEmpty
        ? track.highResThumbnailUrl
        : (track.thumbnailUrl.isNotEmpty
            ? track.thumbnailUrl
            : (player.getArtwork(track.artist, track.title) ?? ''));
    if (imgUrl.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          elevation: 0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Dismiss on background tap
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),

              // Content Card
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Full Uncut Album Art with Pinch-to-zoom & Pan
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.70,
                        maxWidth: MediaQuery.of(ctx).size.width * 0.94,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black87,
                            blurRadius: 36,
                            spreadRadius: 4,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Image.network(
                            imgUrl,
                            fit: BoxFit.contain, // Shows entire content uncut
                            filterQuality: FilterQuality.high,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Image.network(
                              track.thumbnailUrl,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Track & Album Info Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171F).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (track.artist.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                _navigateToArtist(context, track.artist),
                            child: Text(
                              track.artist,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Close button
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(10),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 24),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _playerScrollController.removeListener(_onPlayerScroll);
    _playerScrollController.dispose();
    _lyricsScrollController.dispose();
    _animController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _initAnimation();
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (track == null) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0D0F14) : AppColors.lightSurface,
        body: const Center(child: Text('No track playing')),
      );
    }

    final lyrics = player.currentLyrics;

    // Detect track change to reset scroll tracking
    if (track.id != _lastTrackId) {
      _lastTrackId = track.id;
      _lastScrolledIndex = -1;
      _lyricKeys.clear();
    }

    // Determine current active lyric line based on playback position
    int activeLyricIndex = -1;
    if (lyrics.isNotEmpty) {
      final currentMs = player.position.inMilliseconds;
      activeLyricIndex = lyrics.lastIndexWhere(
          (l) => l.timestamp.inMilliseconds <= currentMs);

      if (_isLyricsView &&
          activeLyricIndex != _lastScrolledIndex &&
          activeLyricIndex >= 0) {
        _lastScrolledIndex = activeLyricIndex;
        _scrollToCenter(activeLyricIndex);
      }
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0F14) : AppColors.lightSurface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double screenHeight = constraints.maxHeight;

            return AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final t = _anim.value;

                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! < -250) {
                      _navigateToArtist(context, track.artist);
                    }
                  },
                  child: Stack(
                    children: [
                    // 1. Full Player View (Fades out and translates slightly up)
                    Opacity(
                      opacity: (1.0 - t).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, -50 * t),
                        child: IgnorePointer(
                          ignoring: t > 0.5,
                          child: _buildFullPlayer(
                              context, player, track, isDark),
                        ),
                      ),
                    ),

                    // 2. Full Scrollable Lyrics View (Fades in and slides up from bottom)
                    if (t > 0.01)
                      Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 40 * (1.0 - t)),
                          child: IgnorePointer(
                            ignoring: t < 0.5,
                            child: _buildLyricsView(player, isDark,
                                activeLyricIndex, screenHeight),
                          ),
                        ),
                      ),

                    // 3. Compact Frosted Glass Top Bar Container (Slides down smoothly into place)
                    if (t > 0.01)
                      Positioned(
                        top: 10,
                        left: 14,
                        right: 14,
                        child: Transform.translate(
                          offset: Offset(0, -20 * (1.0 - t)),
                          child: _buildFrostedGlassTopBar(
                              player, track, isDark, t),
                        ),
                      ),
                  ],
                ),
              );
              },
            );
          },
        ),
      ),
    );
  }

  // --- FULL PLAYER VIEW ---
  Widget _buildFullPlayer(
      BuildContext context, PlayerProvider player, Track track, bool isDark) {
    final remaining = (player.duration - player.position);
    final remainingStr =
        '-${_formatDuration(remaining.isNegative ? Duration.zero : remaining)}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -250) {
          _navigateToArtist(context, track.artist);
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          // Swipe up to open lyrics
          if (details.primaryVelocity! < -180) {
            _openLyrics();
          }
          // Swipe down to dismiss Now Playing entirely
          else if (details.primaryVelocity! > 240) {
            Navigator.of(context).pop();
          }
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double screenHeight = constraints.maxHeight;

          // Hero artwork height: fills the upper viewport down to right above the song title
          final double artHeight =
              (screenHeight - 305.0).clamp(340.0, 720.0);

          return SingleChildScrollView(
            controller: _playerScrollController,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: screenHeight),
              child: Column(
                children: [
                  // --- TOP HERO ALBUM ART SECTION (EDGE TO EDGE) ---
                  SizedBox(
                    height: artHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        // High Definition Hero Album Art Card (Edge-to-edge full width)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showAlbumArtPopup(context, track),
                          child: Container(
                            height: artHeight,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: isDark ? 0.35 : 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              child: Builder(builder: (context) {
                                final player = context.read<PlayerProvider>();
                                final art = track.highResThumbnailUrl.isNotEmpty
                                    ? track.highResThumbnailUrl
                                    : (track.thumbnailUrl.isNotEmpty
                                        ? track.thumbnailUrl
                                        : player.getArtwork(track.artist, track.title));

                                if (art == null || art.isEmpty) {
                                  player.resolveArtworkFor(track.artist, track.title);
                                }

                                return art != null && art.isNotEmpty
                                    ? Image.network(
                                        art,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.high,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.secondary,
                                          child: const Icon(
                                            Icons.album,
                                            size: 80,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.secondary,
                                        child: const Icon(
                                          Icons.album,
                                          size: 80,
                                          color: Colors.white,
                                        ),
                                      );
                              }),
                            ),
                          ),
                        ),

                        // Subtle Fullscreen / View Full Art Indicator
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: () => _showAlbumArtPopup(context, track),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fullscreen_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Full Art',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Top Header Controls over the artwork
                        Positioned(
                          top: 10,
                          left: 12,
                          right: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Indicator drag handle pill
                              Container(
                                width: 42,
                                height: 4.5,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.35),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),

                              // See-through translucent frosted glass bar on top area
                              ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black
                                          .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        width: 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.12),
                                          blurRadius: 14,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 32,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black45,
                                                blurRadius: 6,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'PLAYING FROM PLAYLIST',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.0,
                                                color: Colors.white
                                                    .withValues(alpha: 0.88),
                                                shadows: const [
                                                  Shadow(
                                                    color: Colors.black54,
                                                    blurRadius: 6,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              track.album.isNotEmpty
                                                  ? track.album
                                                  : 'YouTube Music Mix',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black54,
                                                    blurRadius: 8,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.queue_music_rounded,
                                            size: 24,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black45,
                                                blurRadius: 6,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          tooltip: 'Playing Queue',
                                          onPressed: () => _openQueue(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tightly positioned right above the song title
                  const SizedBox(height: 12),

                  // Title, Controls, Scrubber, Badges
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Track Title, Artist, Favorite Heart & FLAC Pill
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _navigateToArtist(
                                        context, track.artist),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            track.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors.lightTextSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                                  .withValues(alpha: 0.6)
                                              : AppColors.lightTextSecondary
                                                  .withValues(alpha: 0.6),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final isFav = player.isFavorite(
                                        track.youtubeVideoId ?? track.id);
                                    return IconButton(
                                      icon: Icon(
                                        isFav
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 26,
                                        color: isFav
                                            ? AppColors.primary
                                            : (isDark
                                                ? AppColors.darkTextPrimary
                                                : AppColors.lightTextPrimary),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      onPressed: () {
                                        final willBeFav = !player.isFavorite(
                                            track.youtubeVideoId ?? track.id);
                                        player.toggleFavorite(track);
                                        ScaffoldMessenger.of(context)
                                            .hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              willBeFav
                                                  ? 'Added to Liked Songs'
                                                  : 'Removed from Liked Songs',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            duration: const Duration(seconds: 2),
                                            backgroundColor: willBeFav
                                                ? AppColors.primary
                                                : const Color(0xFF1B1E28),
                                            behavior:
                                                SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                                // Format / FLAC Pill directly below love icon
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurface
                                        : AppColors.lightSurfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (track.isLossless) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'FLAC',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF0A0C10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(
                                        track.isLossless
                                            ? ((track.audioFormat ??
                                                    '16-bit • 44.1kHz')
                                                .replaceAll(
                                                    RegExp(
                                                        r'\s*Lossless(?:\s*FLAC)?',
                                                        caseSensitive: false),
                                                    '')
                                                .trim())
                                            : 'YouTube Audio',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // 24-Bar Live Equalizer Visualizer
                        LiveEqualizerBars(
                          isPlaying: player.isPlaying,
                          barCount: 24,
                        ),
                        const SizedBox(height: 6),

                        // Draggable Scrubber Timeline
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 5,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: player.position.inSeconds
                                .toDouble()
                                .clamp(
                                    0.0,
                                    player.duration.inSeconds.toDouble()),
                            max: player.duration.inSeconds.toDouble() > 0
                                ? player.duration.inSeconds.toDouble()
                                : 1.0,
                            onChanged: (val) {
                              player.seekTo(Duration(seconds: val.toInt()));
                            },
                          ),
                        ),

                        // Elapsed & Remaining Timestamps
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(player.position),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.lightTextTertiary,
                                ),
                              ),
                              Text(
                                remainingStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.lightTextTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Transport Controls
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: player.isShuffled
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary),
                              ),
                              onPressed: () => player.toggleShuffle(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous,
                                  size: 36),
                              onPressed: () => player.previous(),
                            ),

                            // 72dp Primary Play/Pause Circle
                            GestureDetector(
                              onTap: () => player.togglePlayPause(),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: player.isBuffering
                                    ? const Center(
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Color(0xFF0A0C10)),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        player.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: const Color(0xFF0A0C10),
                                        size: 38,
                                      ),
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.skip_next, size: 36),
                              onPressed: () => player.next(),
                            ),
                            IconButton(
                              icon: Icon(
                                player.repeatMode == 2
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: player.repeatMode > 0
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary),
                              ),
                              onPressed: () => player.toggleRepeat(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Playback Error / Network Warning Banner
                        if (player.playbackError != null) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF991B1B).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 16, color: Color(0xFFEF4444)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    player.playbackError!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showDebuggerLogsModal(context, player),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Logs',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => player.retryCurrentTrack(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Retry',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A0C10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Lyrics pill - always visible, adapts smoothly to loading/synced states
                        GestureDetector(
                          onTap: _openLyrics,
                          child: Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isDark
                                      ? AppColors.darkSurface
                                      : AppColors.lightSurfaceElevated)
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (player.isLoadingLyrics) ...[
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'LOADING LYRICS...',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ] else if (player.hasSyncedLyrics) ...[
                                  const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SWIPE UP FOR LYRICS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ] else ...[
                                  const Icon(
                                    Icons.lyrics_outlined,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'LYRICS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- FROSTED GLASS TOP BAR CONTAINER ---
  Widget _buildFrostedGlassTopBar(
      PlayerProvider player, Track track, bool isDark, double t) {
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! > 180) {
          _closeLyrics();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: (isDark ? 0.35 : 0.08) * t),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141722).withValues(alpha: 0.58 * t)
                    : Colors.white.withValues(alpha: 0.58 * t),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16 * t)
                      : Colors.white.withValues(alpha: 0.85 * t),
                  width: 1.2,
                ),
              ),
              child: Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          // Down chevron to dismiss or collapse back
                          IconButton(
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 30,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: _closeLyrics,
                          ),
                          const SizedBox(width: 4),

                          // Artwork thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 42,
                              height: 42,
                              color: AppColors.secondary,
                              child: track.thumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      track.highResThumbnailUrl.isNotEmpty
                                          ? track.highResThumbnailUrl
                                          : track.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(
                                        Icons.music_note,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    )
                                  : const Icon(Icons.music_note,
                                      color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Title & Artist with FLAC pill
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _navigateToArtist(
                                            context, track.artist),
                                        child: Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? AppColors.darkTextSecondary
                                                : AppColors.lightTextSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (track.isLossless) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'FLAC',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0A0C10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Mini Play/Pause circular button
                          GestureDetector(
                            onTap: () => player.togglePlayPause(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                player.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: const Color(0xFF0A0C10),
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Next button
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded,
                                size: 26),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: () => player.next(),
                          ),
                        ],
                      ),
                    ),

                    // Bottom 2dp progress rail
                    Container(
                      height: 2.5,
                      width: double.infinity,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- SCROLLABLE SYNCED LYRICS VIEW ---
  Widget _buildLyricsView(PlayerProvider player, bool isDark, int activeIndex,
      double screenHeight) {
    if (player.isLoadingLyrics) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Fetching synced lyrics...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
            ),
          ],
        ),
      );
    }

    final lyrics = player.currentLyrics;
    if (lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No synced lyrics found for this track',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => player.retryLyrics(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _closeLyrics,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  label: const Text('Back to Player'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Ample vertical padding so line 0 and line N can both lock right in the middle
    final double verticalPadding = (screenHeight * 0.46).clamp(180.0, 520.0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // If user pulls down past the top of the lyrics, smoothly return to player
        if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels <= -15 &&
            notification.scrollDelta != null &&
            notification.scrollDelta! < -12) {
          _closeLyrics();
          return true;
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _lyricsScrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: verticalPadding,
          bottom: verticalPadding,
          left: 24,
          right: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(lyrics.length, (index) {
            final line = lyrics[index];
            final isCurrent = index == activeIndex;
            final itemKey = _lyricKeys.putIfAbsent(index, () => GlobalKey());

            return GestureDetector(
              key: itemKey,
              behavior: HitTestBehavior.opaque,
              onTap: () {
                player.seekTo(line.timestamp);
                _lastScrolledIndex = index;
                _scrollToCenter(index);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: isCurrent ? 26 : 21,
                      fontWeight:
                          isCurrent ? FontWeight.w900 : FontWeight.w700,
                      height: 1.28,
                      letterSpacing: isCurrent ? -0.5 : -0.3,
                      color: isCurrent
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.32)
                              : Colors.black.withValues(alpha: 0.28)),
                    ),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
