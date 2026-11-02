import '../widgets/holo_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../widgets/add_to_sheet.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _isReordering = false;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Playlist? playlist = player.playlists.cast<Playlist?>().firstWhere(
          (p) => p?.id == widget.playlistId,
          orElse: () => null,
        );

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Playlist'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Playlist not found',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Library'),
              ),
            ],
          ),
        ),
      );
    }

    final coverUrl = playlist.coverUrl ??
        (playlist.tracks.isNotEmpty ? playlist.tracks.first.highResThumbnailUrl : null);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            SliverAppBar(
              pinned: true,
              backgroundColor: isDark ? AppColors.darkCanvas : AppColors.lightCanvas,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              actions: [
                if (playlist.tracks.length > 1)
                  IconButton(
                    icon: Icon(
                      _isReordering ? Icons.check_rounded : Icons.reorder_rounded,
                      color: _isReordering ? AppColors.primary : null,
                    ),
                    tooltip: _isReordering ? 'Done reordering' : 'Reorder tracks',
                    onPressed: () {
                      setState(() {
                        _isReordering = !_isReordering;
                      });
                    },
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                  onSelected: (value) {
                    if (value == 'rename') {
                      showRenamePlaylistDialog(context, player, playlist);
                    } else if (value == 'delete') {
                      showDeletePlaylistDialog(
                        context,
                        player,
                        playlist,
                        onDeleted: () => Navigator.pop(context),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Rename Playlist'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.redAccent),
                          SizedBox(width: 10),
                          Text(
                            'Delete Playlist',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Hero Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  children: [
                    // Cover Art
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.secondary, Color(0xFF14171F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: coverUrl != null && coverUrl.isNotEmpty
                              ? HoloImage(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      size: 72,
                                      color: Colors.white70,
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.queue_music_rounded,
                                    size: 72,
                                    color: Colors.white70,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Text(
                      playlist.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle / Details
                    Text(
                      '${playlist.formattedTrackCount} • ${playlist.formattedDuration}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    if (playlist.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        playlist.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Play All Button
                        ElevatedButton.icon(
                          onPressed: playlist.tracks.isNotEmpty
                              ? () => player.playPlaylist(playlist)
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text(
                            'Play All',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Shuffle Button
                        OutlinedButton.icon(
                          onPressed: playlist.tracks.isNotEmpty
                              ? () {
                                  player.playPlaylist(playlist);
                                  player.toggleShuffle();
                                }
                              : null,
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text(
                            'Shuffle',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                            side: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Track Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tracks',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (_isReordering)
                      const Text(
                        'Drag handles to reorder',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Empty Tracklist State
            if (playlist.tracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 48,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No songs in this playlist yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap the "+" button on any track across Search or Trending to add it to this playlist.',
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
                  ),
                ),
              )
            else if (_isReordering)
              // Reorderable list mode
              SliverToBoxAdapter(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: playlist.tracks.length,
                  onReorderItem: (oldIndex, newIndex) {
                    player.reorderPlaylistTracks(
                        playlist.id, oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = playlist.tracks[index];
                    return ListTile(
                      key: ValueKey(track.id + index.toString()),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Icon(Icons.drag_indicator_rounded,
                              color: Colors.grey, size: 20),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(track.formattedDuration),
                    );
                  },
                ),
              )
            else
              // Standard track list mode with + button and remove action
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = playlist.tracks[index];
                    final isCurrent = player.currentTrack?.id == track.id;

                    return _buildTrackTile(
                      context,
                      track: track,
                      index: index,
                      isCurrent: isCurrent,
                      playlist: playlist,
                      player: player,
                      isDark: isDark,
                    );
                  },
                  childCount: playlist.tracks.length,
                ),
              ),

            // Bottom padding for mini player
            const SliverToBoxAdapter(
              child: SizedBox(height: 130),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackTile(
    BuildContext context, {
    required Track track,
    required int index,
    required bool isCurrent,
    required Playlist playlist,
    required PlayerProvider player,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => player.playPlaylist(playlist, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              // Track index or playing indicator
              SizedBox(
                width: 24,
                child: isCurrent && player.isPlaying
                    ? const Icon(
                        Icons.equalizer_rounded,
                        size: 16,
                        color: AppColors.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
              ),
              const SizedBox(width: 8),

              // Thumbnail
              ClipRRect(
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
                      player.resolveArtworkFor(track.artist, track.title);
                    }

                    final vid = track.youtubeVideoId ?? track.id;

                    Widget placeholder() => const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 20,
                        );

                    Widget buildYtFallback() {
                      if (vid.length == 11) {
                        return HoloImage(
                          'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                          fit: BoxFit.cover,
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
                        errorBuilder: (_, __, ___) =>
                            buildThumbFallback(),
                      );
                    }

                    return buildThumbFallback();
                  }),
                ),
              ),
              const SizedBox(width: 12),

              // Title & Artist
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
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isCurrent ? AppColors.primary : null,
                            ),
                          ),
                        ),
                        if (track.isLossless) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
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
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Duration
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

              // Universal + button (Add to Queue or another Playlist)
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Add to queue or playlist',
                onPressed: () => showAddToSheet(context, track: track),
              ),

              // Remove from this playlist
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Remove from playlist',
                onPressed: () {
                  final trackId = track.youtubeVideoId ?? track.id;
                  player.removeTrackFromPlaylist(playlist.id, trackId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed "${track.title}" from "${playlist.title}"'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
