import '../widgets/holo_image.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/artist_details.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../services/artist_service.dart';
import '../widgets/add_to_sheet.dart';
import '../widgets/live_equalizer_bars.dart';

class ArtistScreen extends StatefulWidget {
  final String artistName;
  final String? browseId;

  const ArtistScreen({
    super.key,
    required this.artistName,
    this.browseId,
  });

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final ArtistService _artistService = ArtistService();
  final ScrollController _scrollController = ScrollController();

  ArtistDetails? _artistDetails;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showAllSongs = false;
  bool _isLoadingAllSongs = false;
  bool _isBioExpanded = false;
  bool _isScrolled = false;
  double _horizontalDragDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadArtist();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final scrolled = _scrollController.offset > 180;
      if (scrolled != _isScrolled) {
        setState(() => _isScrolled = scrolled);
      }
    }
  }

  Future<void> _loadArtist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final details = await _artistService.getArtistDetails(
        widget.artistName,
        browseId: widget.browseId,
      );
      if (mounted) {
        setState(() {
          _artistDetails = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreTopSongs() async {
    final details = _artistDetails;
    if (details == null ||
        details.topSongsPlaylistId == null ||
        details.hasLoadedAllSongs ||
        _isLoadingAllSongs) {
      setState(() => _showAllSongs = true);
      return;
    }

    setState(() => _isLoadingAllSongs = true);
    try {
      final allSongs = await _artistService.getArtistTopSongs(
        details.topSongsPlaylistId!,
        artistName: details.name,
      );

      if (mounted) {
        setState(() {
          _isLoadingAllSongs = false;
          _showAllSongs = true;
          if (allSongs.isNotEmpty) {
            _artistDetails = details.copyWith(
              topSongs: allSongs,
              hasLoadedAllSongs: true,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingAllSongs = false;
          _showAllSongs = true;
        });
      }
    }
  }

  void _onAlbumTap(ArtistRelease release) async {
    final player = context.read<PlayerProvider>();
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Loading "${release.title}" tracks...'),
        duration: const Duration(seconds: 1),
      ),
    );

    final albumSongs = await _artistService.getAlbumTracks(
      release.browseId,
      artistName: _artistDetails?.name ?? widget.artistName,
      albumName: release.title,
    );

    if (albumSongs.isNotEmpty && mounted) {
      player.playTrackList(albumSongs, 0);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Playing album "${release.title}"',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF0A0C10) : AppColors.lightCanvas;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _horizontalDragDistance = 0.0;
        },
        onHorizontalDragUpdate: (details) {
          _horizontalDragDistance += details.primaryDelta ?? 0.0;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0.0;
          // Swipe right (left-to-right gesture) returns to Now Playing screen
          if (velocity > 220 || _horizontalDragDistance > 90) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        },
        child: Stack(
          children: [
            // Main Scrollable Content
            if (_isLoading)
              _buildLoadingState(isDark)
            else if (_errorMessage != null && _artistDetails == null)
              _buildErrorState(isDark)
            else
              _buildContent(context, isDark),

            // Floating Glass Top Navigation Bar
            _buildTopBar(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(
          top: topPadding + 6,
          bottom: 10,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          color: _isScrolled
              ? (isDark ? const Color(0xEE0A0C10) : Colors.white.withValues(alpha: 0.92))
              : Colors.transparent,
          border: _isScrolled
              ? Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            // Back Button
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.6),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Collapsed Artist Title
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isScrolled ? 1.0 : 0.0,
                child: Text(
                  _artistDetails?.name ?? widget.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    final details = _artistDetails!;
    final player = context.watch<PlayerProvider>();
    final topSongs = details.topSongs;
    final displayedSongs =
        _showAllSongs ? topSongs : topSongs.take(5).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: isDark ? const Color(0xFF14171F) : Colors.white,
      onRefresh: _loadArtist,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Header
            _buildHeroHeader(context, details, isDark),

            const SizedBox(height: 18),

            // 2. Play All and Action Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildActionRow(context, player, details, isDark),
            ),

            const SizedBox(height: 28),

            // 3. Top Songs Section
            if (topSongs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Top Songs',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${topSongs.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (topSongs.length > 5 ||
                        (details.topSongsPlaylistId != null &&
                            !details.hasLoadedAllSongs))
                      TextButton(
                        onPressed: () {
                          if (!_showAllSongs &&
                              details.topSongsPlaylistId != null &&
                              !details.hasLoadedAllSongs) {
                            _loadMoreTopSongs();
                          } else {
                            setState(() => _showAllSongs = !_showAllSongs);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: _isLoadingAllSongs
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : Text(
                                _showAllSongs ? 'Show less' : 'Show all',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Song List
              ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayedSongs.length,
                itemBuilder: (context, index) {
                  final song = displayedSongs[index];
                  final isCurrentTrack =
                      player.currentTrack?.youtubeVideoId ==
                              song.youtubeVideoId ||
                          player.currentTrack?.id == song.id;
                  final isPlaying = isCurrentTrack && player.isPlaying;

                  return _buildSongItem(
                    context,
                    song: song,
                    index: index,
                    isCurrentTrack: isCurrentTrack,
                    isPlaying: isPlaying,
                    isDark: isDark,
                    onTap: () {
                      player.playTrackList(topSongs, index);
                    },
                  );
                },
              ),
            ],

            const SizedBox(height: 28),

            // 4. Albums Section
            if (details.albums.isNotEmpty) ...[
              _buildReleaseSection(
                context,
                title: 'Albums',
                releases: details.albums,
                isDark: isDark,
              ),
              const SizedBox(height: 28),
            ],

            // 5. Singles & EPs Section
            if (details.singles.isNotEmpty) ...[
              _buildReleaseSection(
                context,
                title: 'Singles & EPs',
                releases: details.singles,
                isDark: isDark,
              ),
              const SizedBox(height: 28),
            ],

            // 6. About the Artist / Bio Section
            if (details.bio != null && details.bio!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildBioSection(context, details, isDark),
              ),
              const SizedBox(height: 36),
            ],

            // Bottom Spacing for mini player
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
      BuildContext context, ArtistDetails details, bool isDark) {
    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = (screenHeight * 0.42).clamp(280.0, 420.0);
    final imageUrl = details.effectiveImage;

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          if (imageUrl.isNotEmpty)
            HoloImage(
              imageUrl,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.2),
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF14171F),
                child: const Icon(
                  Icons.person_rounded,
                  size: 96,
                  color: Color(0xFF2C3242),
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF14171F),
              child: const Icon(
                Icons.person_rounded,
                size: 96,
                color: Color(0xFF2C3242),
              ),
            ),

          // Gradient Vignette Overlays
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    isDark ? const Color(0xDD0A0C10) : Colors.white.withValues(alpha: 0.8),
                    isDark ? const Color(0xFF0A0C10) : Colors.white,
                  ],
                  stops: const [0.0, 0.3, 0.82, 1.0],
                ),
              ),
            ),
          ),

          // Artist Info Floating at bottom of hero
          Positioned(
            left: 20,
            right: 20,
            bottom: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Verified Artist Badge
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'VERIFIED ARTIST',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Artist Name
                Text(
                  details.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 8),

                // Audience and Subscribers Stat Pills
                Row(
                  children: [
                    if (details.monthlyAudience != null &&
                        details.monthlyAudience!.isNotEmpty) ...[
                      Text(
                        details.monthlyAudience!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                    if (details.monthlyAudience != null &&
                        details.subscribers != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '•',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    if (details.subscribers != null &&
                        details.subscribers!.isNotEmpty) ...[
                      Text(
                        '${details.subscribers} subscribers',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, PlayerProvider player,
      ArtistDetails details, bool isDark) {
    return Row(
      children: [
        // Play All Button
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: details.topSongs.isEmpty
                  ? null
                  : () {
                      player.playTrackList(details.topSongs, 0);
                    },
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text(
                'Play',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Shuffle Button
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: details.topSongs.isEmpty
                  ? null
                  : () {
                      player.shuffleTrackList(details.topSongs);
                    },
              icon: Icon(
                Icons.shuffle_rounded,
                size: 20,
                color: isDark ? Colors.white : Colors.black87,
              ),
              label: Text(
                'Shuffle',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Radio / Endless Mix Button
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: IconButton(
            icon: Icon(
              Icons.radio_rounded,
              size: 22,
              color: isDark ? Colors.white : Colors.black87,
            ),
            tooltip: 'Start Artist Radio',
            onPressed: details.topSongs.isEmpty
                ? null
                : () {
                    final firstSong = details.topSongs.first;
                    player.playTrack(firstSong);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Started radio for ${details.name}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildSongItem(
    BuildContext context, {
    required Track song,
    required int index,
    required bool isCurrentTrack,
    required bool isPlaying,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final plays = song.extraData?['plays'] as String?;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isCurrentTrack
              ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.primary.withValues(alpha: 0.08))
              : Colors.transparent,
        ),
        child: Row(
          children: [
            // Rank Number or Playing Equalizer Bars
            SizedBox(
              width: 28,
              child: Center(
                child: isCurrentTrack
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: LiveEqualizerBars(
                          isPlaying: isPlaying,
                          barCount: 3,
                        ),
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // Cover Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: HoloImage(
                  song.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: isDark ? const Color(0xFF1E222D) : Colors.grey[200],
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Song Info (Title and Album/Subtitle)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isCurrentTrack
                          ? AppColors.primary
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.album.isNotEmpty ? song.album : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Plays Counter or Formatted Duration
            if (plays != null && plays.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  plays,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ] else if (song.durationSeconds > 0) ...[
              Text(
                song.formattedDuration,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(width: 6),
            ],

            // Universal Plus (+) Button to Add to Queue or Playlist
            IconButton(
              icon: Icon(
                Icons.add_rounded,
                size: 22,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
              tooltip: 'Add to queue or playlist',
              splashRadius: 20,
              onPressed: () {
                showAddToSheet(context, track: song);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseSection(
    BuildContext context, {
    required String title,
    required List<ArtistRelease> releases,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 185,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: releases.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final release = releases[index];
              return InkWell(
                onTap: () => _onAlbumTap(release),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Album Cover Art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: HoloImage(
                            release.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? const Color(0xFF1E222D)
                                  : Colors.grey[200],
                              child: Icon(
                                Icons.album_rounded,
                                size: 40,
                                color:
                                    isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Title
                      Text(
                        release.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),

                      // Subtitle (e.g. Album • 2026)
                      Text(
                        release.year.isNotEmpty
                            ? '${release.type} • ${release.year}'
                            : release.type,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBioSection(
      BuildContext context, ArtistDetails details, bool isDark) {
    final bio = details.bio ?? '';
    final isLongBio = bio.length > 240;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF14171F)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'About ${details.name}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (details.totalViews != null && details.totalViews!.isNotEmpty)
                Text(
                  details.totalViews!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isBioExpanded || !isLongBio ? bio : '${bio.substring(0, 240)}...',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.85)
                  : Colors.black87,
            ),
          ),
          if (isLongBio) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _isBioExpanded = !_isBioExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _isBioExpanded ? 'Read less' : 'Read more',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading ${widget.artistName}...',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load artist profile',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'An error occurred while fetching artist details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadArtist,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
