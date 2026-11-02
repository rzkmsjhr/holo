import '../widgets/holo_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/daily_mix.dart';
import '../../models/track.dart';
import '../../models/trending_track.dart';
import '../../providers/player_provider.dart';
import '../widgets/add_to_sheet.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _trendingPageController = PageController();
  int _selectedTrendingTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final player = context.read<PlayerProvider>();
        player.loadTrending();
      }
    });
  }

  @override
  void dispose() {
    _trendingPageController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }

  String _getSubtitle(PlayerProvider player) {
    if (player.currentTrack != null) {
      return player.isPlaying
          ? 'Now playing • ${player.currentTrack!.title}'
          : 'Paused • ${player.currentTrack!.title}';
    }
    return player.isEndlessPlay
        ? 'Endless Vibe Radio • Ready to play'
        : 'Your sound sanctuary';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getGreeting(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _getSubtitle(player),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: player.isPlaying
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode : Icons.dark_mode,
                        size: 22,
                      ),
                      onPressed: () => player.toggleTheme(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 22),
                      onPressed: () => SettingsSheet.show(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Section: Jump Back In (Quick 6-Grid of Recently Played)
        if (player.recentlyPlayed.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Jump Back In',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final recents = player.recentlyPlayed;
                  if (index >= recents.length) return const SizedBox.shrink();
                  final track = recents[index];
                  return _buildQuickCard(context, track, player);
                },
                childCount: player.recentlyPlayed.length.clamp(0, 6),
              ),
            ),
          ),
        ],

        // Section: Made For You Carousel (Personalized Daily Mixes)
        if (player.dailyMixes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Made For You',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  GestureDetector(
                    onTap: () => _showAllMixesModal(context, player),
                    child: const Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 224,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: player.dailyMixes.length,
                itemBuilder: (context, index) {
                  final mix = player.dailyMixes[index];
                  return _buildDailyMixCard(context, mix, player);
                },
              ),
            ),
          ),
        ],

        // Section: Trending Charts Header & Tabs
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Trending',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'Spotify Daily via Kworb',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Tabbed Pills (Swipe left / right or tap)
                Row(
                  children: [
                    _buildTrendingTabPill(
                      label: 'Top 50 Global',
                      index: 0,
                      count: player.globalTrending.length,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildTrendingTabPill(
                      label: 'Top 50 Indonesia',
                      index: 1,
                      count: player.indonesiaTrending.length,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Tabbed Swipeable PageView of Charts
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50 * 66.0 + 130.0,
            child: PageView(
              controller: _trendingPageController,
              onPageChanged: (idx) {
                setState(() {
                  _selectedTrendingTab = idx;
                });
              },
              children: [
                // Page 0: Global Top 50
                _buildTrendingList(
                  context,
                  player.globalTrending,
                  player,
                  isDark,
                ),
                // Page 1: Indonesia Top 50
                _buildTrendingList(
                  context,
                  player.indonesiaTrending,
                  player,
                  isDark,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildQuickCard(
      BuildContext context, Track track, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCurrent =
        (player.currentTrack?.youtubeVideoId ?? player.currentTrack?.id) ==
            (track.youtubeVideoId ?? track.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => player.playTrack(track),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              width: isCurrent ? 1.2 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Flush-docked left album art
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(9),
                ),
                child: SizedBox(
                  width: 52,
                  height: double.infinity,
                  child: Builder(builder: (context) {
                    final cachedArt = player.getArtwork(track.artist, track.title);
                    final art = (cachedArt != null && cachedArt.isNotEmpty)
                        ? cachedArt
                        : (track.highResThumbnailUrl.isNotEmpty
                            ? track.highResThumbnailUrl
                            : (track.thumbnailUrl.isNotEmpty
                                ? track.thumbnailUrl
                                : null));

                    if (cachedArt == null || cachedArt.isEmpty) {
                      player.resolveArtworkFor(track.artist, track.title);
                    }

                    final vid = track.youtubeVideoId ?? track.id;

                    Widget placeholderIcon() => Container(
                          color: AppColors.secondary,
                          child: const Icon(Icons.music_note,
                              color: Colors.white, size: 20),
                        );

                    Widget buildYtFallback() {
                      if (vid.length == 11) {
                        return HoloImage(
                          'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => placeholderIcon(),
                        );
                      }
                      return placeholderIcon();
                    }

                    Widget buildThumbFallback() {
                      if (track.thumbnailUrl.isNotEmpty &&
                          track.thumbnailUrl != art) {
                        return HoloImage(
                          track.thumbnailUrl,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => buildYtFallback(),
                        );
                      }
                      return buildYtFallback();
                    }

                    if (art != null && art.isNotEmpty) {
                      return HoloImage(
                        art,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => buildThumbFallback(),
                      );
                    }

                    return buildThumbFallback();
                  }),
                ),
              ),

              // Title, Artist & Live Equalizer
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: isCurrent
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Playing indicator
              if (isCurrent && player.isPlaying) ...[
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.equalizer_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyMixCard(
      BuildContext context, DailyMix mix, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showDailyMixModal(context, mix, player),
      child: Container(
        width: 156,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 156,
                    height: 156,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: mix.gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: mix.coverUrl.isNotEmpty
                        ? HoloImage(
                            mix.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.album,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 44,
                            ),
                          )
                        : Icon(
                            Icons.album,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 44,
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      mix.badge,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      player.playDailyMix(mix);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Playing ${mix.title}'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mix.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              mix.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDailyMixModal(
      BuildContext context, DailyMix mix, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? const Color(0xFF0F1218) : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: mix.gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: mix.coverUrl.isNotEmpty
                              ? HoloImage(
                                  mix.coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.album,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                )
                              : const Icon(
                                  Icons.album,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                mix.badge,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mix.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${mix.tracks.length} tracks • ${mix.subtitle}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        iconSize: 28,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: () {
                          player.playDailyMix(mix);
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: mix.tracks.length,
                    itemBuilder: (context, idx) {
                      final track = mix.tracks[idx];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 44,
                            height: 44,
                            color: AppColors.secondary,
                            child: Builder(builder: (context) {
                              final cachedArt = player.getArtwork(
                                  track.artist, track.title);
                              final art = (cachedArt != null && cachedArt.isNotEmpty)
                                  ? cachedArt
                                  : (track.highResThumbnailUrl.isNotEmpty
                                      ? track.highResThumbnailUrl
                                      : (track.thumbnailUrl.isNotEmpty
                                          ? track.thumbnailUrl
                                          : null));

                              if (cachedArt == null || cachedArt.isEmpty) {
                                player.resolveArtworkFor(
                                    track.artist, track.title);
                              }

                              final vid = track.youtubeVideoId ?? track.id;

                              Widget placeholder() => const Icon(
                                    Icons.music_note,
                                    color: Colors.white,
                                  );

                              Widget buildYtFallback() {
                                if (vid.length == 11) {
                                  return HoloImage(
                                    'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, __, ___) => placeholder(),
                                  );
                                }
                                return placeholder();
                              }

                              Widget buildThumbFallback() {
                                if (track.thumbnailUrl.isNotEmpty &&
                                    track.thumbnailUrl != art) {
                                  return HoloImage(
                                    track.thumbnailUrl,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, __, ___) =>
                                        buildYtFallback(),
                                  );
                                }
                                return buildYtFallback();
                              }

                              if (art != null && art.isNotEmpty) {
                                return HoloImage(
                                  art,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) =>
                                      buildThumbFallback(),
                                );
                              }

                              return buildThumbFallback();
                            }),
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (track.isLossless) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
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
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              icon: const Icon(Icons.add_rounded, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                              onPressed: () =>
                                  showAddToSheet(context, track: track),
                            ),
                          ],
                        ),
                        onTap: () {
                          player.playDailyMix(mix, idx);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAllMixesModal(BuildContext context, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isDark ? const Color(0xFF0F1218) : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    'Made For You',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: player.dailyMixes.length,
                    itemBuilder: (context, i) {
                      final mix = player.dailyMixes[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: mix.gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: mix.coverUrl.isNotEmpty
                                ? HoloImage(
                                    mix.coverUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.album,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.album,
                                    color: Colors.white),
                          ),
                        ),
                        title: Text(
                          mix.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          mix.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_circle_fill_rounded,
                              color: AppColors.primary, size: 32),
                          onPressed: () {
                            player.playDailyMix(mix);
                            Navigator.pop(ctx);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showDailyMixModal(context, mix, player);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTrendingTabPill({
    required String label,
    required int index,
    required int count,
    required bool isDark,
  }) {
    final isSelected = _selectedTrendingTab == index;

    return GestureDetector(
      onTap: () {
        _trendingPageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (isDark
                          ? const Color(0xFF232733)
                          : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingList(
    BuildContext context,
    List<TrendingTrack> items,
    PlayerProvider player,
    bool isDark,
  ) {
    if (items.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading chart...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 130),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final key = '${item.artist} - ${item.title}'.toLowerCase();
        final currentT = player.currentTrack;
        final isCurrent = currentT != null &&
            (currentT.title.toLowerCase() == item.title.toLowerCase() ||
                (currentT.artist
                        .toLowerCase()
                        .contains(item.artist.toLowerCase()) &&
                    currentT.title
                        .toLowerCase()
                        .contains(item.title.toLowerCase())));
        final isResolving = player.resolvingTrendingKey == key && !isCurrent;

        return _buildTrendingTile(
          context: context,
          item: item,
          isCurrent: isCurrent,
          isResolving: isResolving,
          player: player,
          isDark: isDark,
        );
      },
    );
  }

  Widget _buildTrendingTile({
    required BuildContext context,
    required TrendingTrack item,
    required bool isCurrent,
    required bool isResolving,
    required PlayerProvider player,
    required bool isDark,
  }) {
    Color rankColor;
    if (item.rank == 1) {
      rankColor = AppColors.primary;
    } else if (item.rank == 2) {
      rankColor =
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    } else if (item.rank == 3) {
      rankColor = isDark ? AppColors.accent : const Color(0xFF4D7C0F);
    } else {
      rankColor =
          isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => player.playTrendingTrack(item),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isCurrent
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1.0,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Leaderboard Rank & Trend
              SizedBox(
                width: 38,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${item.rank}',
                      style: TextStyle(
                        fontSize: item.rank <= 3 ? 15 : 13.5,
                        fontWeight: item.rank <= 3
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: rankColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    _buildTrendIndicator(item.trend),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // Track Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 46,
                  height: 46,
                  color: AppColors.secondary,
                  child: Builder(builder: (context) {
                    final cachedArt = player.getArtwork(item.artist, item.title);
                    final rawThumb = item.thumbnailUrl;
                    final validThumb = rawThumb != null &&
                            rawThumb.isNotEmpty &&
                            !rawThumb.contains('unsplash.com');
                    final art = (cachedArt != null && cachedArt.isNotEmpty)
                        ? cachedArt
                        : (validThumb ? rawThumb : null);

                    if (cachedArt == null || cachedArt.isEmpty) {
                      player.resolveArtworkFor(
                          item.artist, item.title, item.rank > 50);
                    }

                    final vid = item.youtubeVideoId;

                    Widget placeholder() => const Icon(
                          Icons.music_note,
                          color: Colors.white,
                          size: 22,
                        );

                    Widget buildYtFallback() {
                      if (vid != null && vid.length == 11) {
                        return HoloImage(
                          'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder(),
                        );
                      }
                      return placeholder();
                    }

                    Widget buildThumbFallback() {
                      if (validThumb && rawThumb != art) {
                        return HoloImage(
                          rawThumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => buildYtFallback(),
                        );
                      }
                      return buildYtFallback();
                    }

                    if (art != null && art.isNotEmpty) {
                      return HoloImage(
                        art,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => buildThumbFallback(),
                      );
                    }

                    return buildThumbFallback();
                  }),
                ),
              ),

              const SizedBox(width: 12),

              // Title and Artist
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isCurrent
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Resolving spinner or equalizer
              if (isResolving) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (isCurrent && player.isPlaying) ...[
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.equalizer_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],

              // Plays Counter (2 rows: [headphones icon + number] over [plays])
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: (isDark
                          ? const Color(0xFF1B1F2A)
                          : const Color(0xFFE8ECF2))
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.headphones_rounded,
                          size: 10,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.formattedPlaysNumber,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'plays',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),

              // Plus button to add to queue or playlist
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                padding: const EdgeInsets.all(4),
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => showAddToSheetForTrending(
                  context,
                  trendingTrack: item,
                  player: player,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendIndicator(String trend) {
    if (trend.startsWith('+')) {
      final change = trend.replaceAll('+', '').trim();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.arrow_drop_up_rounded,
            color: Color(0xFF10B981),
            size: 14,
          ),
          if (change.isNotEmpty)
            Text(
              change,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF10B981),
              ),
            ),
        ],
      );
    } else if (trend.startsWith('-')) {
      final change = trend.replaceAll('-', '').trim();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.arrow_drop_down_rounded,
            color: Color(0xFFEF4444),
            size: 14,
          ),
          if (change.isNotEmpty)
            Text(
              change,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
              ),
            ),
        ],
      );
    }

    return Text(
      '=',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.grey.withValues(alpha: 0.6),
      ),
    );
  }
}
