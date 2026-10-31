import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../widgets/add_to_sheet.dart';
import '../widgets/live_equalizer_bars.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedSegment = 0; // 0 = Saved, 1 = Queue
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Liked',
    'Playlists',
    'Albums',
    'Artists',
    'Downloaded',
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final subtitleText = _selectedSegment == 0
        ? '${player.playlists.length} ${player.playlists.length == 1 ? "playlist" : "playlists"}'
        : (_selectedSegment == 1
            ? '${player.likedTracks.length} ${player.likedTracks.length == 1 ? "liked song" : "liked songs"}'
            : '${player.queue.length} tracks in queue');

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Music',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 26),
                        tooltip: 'Create New Playlist',
                        onPressed: () =>
                            showCreatePlaylistDialog(context, player),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Segmented Control: Playlists vs Liked vs Queue
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.lightSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildSegmentItem(0, 'Playlists', isDark),
                    _buildSegmentItem(
                      1,
                      'Liked',
                      isDark,
                      icon: Icons.favorite_rounded,
                      count: player.likedTracks.length,
                    ),
                    _buildSegmentItem(
                      2,
                      'Queue',
                      isDark,
                      count: player.queue.length,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips (Only shown on Saved Playlists)
            if (_selectedSegment == 0)
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = filter == _selectedFilter;
                    return GestureDetector(
                      onTap: () {
                        if (filter == 'Liked') {
                          setState(() => _selectedSegment = 1);
                        } else {
                          setState(() => _selectedFilter = filter);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary)
                              : (isDark
                                  ? AppColors.darkSurface
                                  : AppColors.lightSurface),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? (isDark
                                      ? AppColors.darkCanvas
                                      : AppColors.lightCanvas)
                                  : (isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Content Area
            Expanded(
              child: _selectedSegment == 0
                  ? _buildSavedPlaylistsView(context, player, isDark)
                  : (_selectedSegment == 1
                      ? _buildLikedSongsView(context, player, isDark)
                      : _buildQueueView(context, player)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentItem(
    int index,
    String label,
    bool isDark, {
    IconData? icon,
    int? count,
  }) {
    final isSelected = _selectedSegment == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedSegment = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.darkSurface : AppColors.lightSurface)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isSelected
                      ? (index == 1
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary))
                      : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? (isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary)
                      : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (index == 1
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (isDark ? Colors.white12 : Colors.black12))
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? (index == 1
                              ? AppColors.primary
                              : (isDark ? Colors.white70 : Colors.black54))
                          : (isDark ? Colors.white38 : Colors.black38),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedLikedSongsTile(
    BuildContext context,
    PlayerProvider player,
    bool isDark,
  ) {
    final count = player.likedTracks.length;

    return GestureDetector(
      onTap: () => setState(() => _selectedSegment = 1),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14171F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Gradient Heart Container
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),

            // Title & Count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Liked Songs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: AppColors.primary.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Auto playlist • $count ${count == 1 ? "song" : "songs"}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            if (count > 0)
              IconButton(
                icon: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 34,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  player.playTrackList(player.likedTracks, 0);
                },
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedSongsView(
    BuildContext context,
    PlayerProvider player,
    bool isDark,
  ) {
    final liked = player.likedTracks;

    if (liked.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF14171F)
                      : AppColors.lightSurfaceElevated,
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: const Icon(
                  Icons.favorite_border_rounded,
                  size: 34,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No liked songs yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the heart icon (♥) on any song in the player to save your favorites here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
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

    final totalSecs =
        liked.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final durationStr = totalSecs >= 3600
        ? '${totalSecs ~/ 3600} hr ${(totalSecs % 3600) ~/ 60} min'
        : '${totalSecs ~/ 60} min';

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
      children: [
        // Hero Liked Banner Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5416), Color(0xFF5A32A3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5416).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR COLLECTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Liked Songs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${liked.length} ${liked.length == 1 ? "song" : "songs"} • $durationStr',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => player.playTrackList(liked, 0),
                          icon: const Icon(Icons.play_arrow_rounded,
                              size: 18, color: Color(0xFF0A0C10)),
                          label: const Text(
                            'Play All',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0A0C10),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => player.shuffleTrackList(liked),
                          icon: const Icon(Icons.shuffle_rounded,
                              size: 16, color: Colors.white),
                          label: const Text(
                            'Shuffle',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Section Title
        Text(
          'All Songs (${liked.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),

        // Songs List
        ...List.generate(liked.length, (index) {
          final song = liked[index];
          final isCurrent = player.currentTrack?.youtubeVideoId ==
                  song.youtubeVideoId ||
              player.currentTrack?.id == song.id;
          final isPlaying = isCurrent && player.isPlaying;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? (isDark
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.08))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Rank / Playing Equalizer Bars
                SizedBox(
                  width: 26,
                  child: Center(
                    child: isCurrent
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: LiveEqualizerBars(
                              isPlaying: isPlaying,
                              barCount: 3,
                            ),
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),

                // Cover Art Thumbnail
                GestureDetector(
                  onTap: () => player.playTrackList(liked, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Image.network(
                        song.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: isDark
                              ? const Color(0xFF1E222D)
                              : Colors.grey[200],
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 20,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Title and Artist
                Expanded(
                  child: GestureDetector(
                    onTap: () => player.playTrackList(liked, index),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isCurrent
                                ? AppColors.primary
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.album.isNotEmpty
                              ? '${song.artist} • ${song.album}'
                              : song.artist,
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
                ),

                // Duration
                if (song.durationSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      song.formattedDuration,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),

                // Favorite Heart Button (removes from liked songs)
                IconButton(
                  icon: const Icon(
                    Icons.favorite_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Remove from Liked Songs',
                  splashRadius: 18,
                  onPressed: () {
                    player.toggleFavorite(song);
                  },
                ),

                // Universal + Button (adds to queue or playlist)
                IconButton(
                  icon: Icon(
                    Icons.add_rounded,
                    size: 22,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                  tooltip: 'Add to queue or playlist',
                  splashRadius: 18,
                  onPressed: () {
                    showAddToSheet(context, track: song);
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSavedPlaylistsView(
    BuildContext context,
    PlayerProvider player,
    bool isDark,
  ) {
    // Other filters handling
    if (_selectedFilter == 'Downloaded') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done_rounded,
              size: 48,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              'No downloaded songs',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Downloaded music will appear here for offline playback.',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final playlists = player.playlists;

    if (playlists.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
        children: [
          // Pinned Liked Songs Tile
          _buildPinnedLikedSongsTile(context, player, isDark),
          const SizedBox(height: 14),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 56,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No custom playlists yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create a playlist to organize your tracks and listen whenever you want.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => showCreatePlaylistDialog(context, player),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Create Playlist',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final heroPlaylist = playlists.first;
    final heroCover = heroPlaylist.coverUrl ??
        (heroPlaylist.tracks.isNotEmpty
            ? heroPlaylist.tracks.first.highResThumbnailUrl
            : null);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
      children: [
        // Pinned Liked Songs Tile
        _buildPinnedLikedSongsTile(context, player, isDark),

        // Hero Playlist Card
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PlaylistDetailScreen(playlistId: heroPlaylist.id),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.secondary, Color(0xFF14171F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 80,
                    height: 80,
                    color: AppColors.primary,
                    child: heroCover != null && heroCover.isNotEmpty
                        ? Image.network(
                            heroCover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_note_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.music_note_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HEAVY ROTATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        heroPlaylist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${heroPlaylist.formattedTrackCount} • ${heroPlaylist.formattedDuration}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: heroPlaylist.tracks.isNotEmpty
                                ? () => player.playPlaylist(heroPlaylist)
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlaylistDetailScreen(
                                            playlistId: heroPlaylist.id),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.play_arrow_rounded,
                                size: 18, color: Color(0xFF0A0C10)),
                            label: Text(
                              heroPlaylist.tracks.isNotEmpty
                                  ? 'Play All'
                                  : 'View',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0A0C10),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded,
                                color: Colors.white70, size: 20),
                            onPressed: () {
                              _showPlaylistOptions(
                                  context, player, heroPlaylist);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),

        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your Playlists (${playlists.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            TextButton.icon(
              onPressed: () => showCreatePlaylistDialog(context, player),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'New',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Playlists List
        ...playlists.map((playlist) {
          final cover = playlist.coverUrl ??
              (playlist.tracks.isNotEmpty
                  ? playlist.tracks.first.highResThumbnailUrl
                  : null);

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 52,
                height: 52,
                color: AppColors.secondary,
                child: cover != null && cover.isNotEmpty
                    ? Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.queue_music_rounded,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white,
                      ),
              ),
            ),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            subtitle: Text(
              '${playlist.formattedTrackCount} • ${playlist.formattedDuration}',
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
                if (playlist.tracks.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: AppColors.primary,
                      size: 30,
                    ),
                    tooltip: 'Play Playlist',
                    onPressed: () => player.playPlaylist(playlist),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  onPressed: () {
                    _showPlaylistOptions(context, player, playlist);
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PlaylistDetailScreen(playlistId: playlist.id),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  void _showPlaylistOptions(
    BuildContext context,
    PlayerProvider player,
    Playlist playlist,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF0F1218) : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  playlist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const Divider(height: 1, thickness: 0.5),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open Playlist'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  );
                },
              ),
              if (playlist.tracks.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: const Text('Play Next in Queue'),
                  onTap: () {
                    for (final t in playlist.tracks.reversed) {
                      player.playNext(t);
                    }
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Added "${playlist.title}" tracks to play next'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Rename Playlist'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showRenamePlaylistDialog(context, player, playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: const Text('Delete Playlist',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showDeletePlaylistDialog(context, player, playlist);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueView(BuildContext context, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (player.queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 56,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Playing queue is empty',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "+" on any song from Search or Trending to add it to queue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Swipe left to remove • Drag left handle to reorder',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
              GestureDetector(
                onTap: () => player.clearQueue(),
                child: const Text(
                  'Clear All',
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
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 130),
            itemCount: player.queue.length,
            onReorderItem: (oldIndex, newIndex) =>
                player.reorderQueue(oldIndex, newIndex),
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 6,
                color: isDark
                    ? const Color(0xFF1D212C)
                    : AppColors.lightSurfaceElevated,
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final track = player.queue[index];
              final isCurrent = player.currentTrack?.id == track.id;

              return Dismissible(
                key: ValueKey('queue_${track.id}_$index'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.redAccent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white),
                ),
                onDismissed: (_) => player.removeFromQueue(index),
                child: Material(
                  key: ValueKey('track_item_${track.id}_$index'),
                  color: isCurrent
                      ? (isDark
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.08))
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => player.playTrack(track),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // Functional Drag Handle
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: 20,
                                color: isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.lightTextTertiary,
                              ),
                            ),
                          ),

                          // Artwork Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 42,
                              height: 42,
                              color: AppColors.secondary,
                              child: Builder(builder: (context) {
                                final art = track.thumbnailUrl.isNotEmpty
                                    ? track.thumbnailUrl
                                    : player.getArtwork(
                                        track.artist, track.title);

                                if (art == null || art.isEmpty) {
                                  player.resolveArtworkFor(
                                      track.artist, track.title);
                                }

                                return art != null && art.isNotEmpty
                                    ? Image.network(
                                        art,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                          Icons.music_note_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.music_note_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      );
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title and Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: isCurrent
                                              ? AppColors.primary
                                              : null,
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
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (isCurrent && player.isPlaying) ...[
                                      const Icon(
                                        Icons.equalizer_rounded,
                                        size: 14,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        isCurrent
                                            ? '${track.artist} • Now Playing'
                                            : track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isCurrent
                                              ? AppColors.primary
                                              : (isDark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors
                                                      .lightTextSecondary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Clean Duration
                          Text(
                            track.formattedDuration,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
