import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/trending_track.dart';
import '../../providers/player_provider.dart';

/// Shows the universal "Add to Queue or Playlist" modal bottom sheet
void showAddToSheet(
  BuildContext context, {
  required Track track,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? const Color(0xFF0F1218) : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return _AddToPlaylistSheet(
        track: track,
        isDark: isDark,
      );
    },
  );
}

/// Convenience helper to open the Add to Sheet for a TrendingTrack
Future<void> showAddToSheetForTrending(
  BuildContext context, {
  required TrendingTrack trendingTrack,
  required PlayerProvider player,
}) async {
  // Use temporary placeholder track if resolution takes time, or quick fallback
  final track = trendingTrack.toTrack();
  if (context.mounted) {
    showAddToSheet(context, track: track);
  }
}

/// Displays the Create New Playlist dialog
Future<void> showCreatePlaylistDialog(
  BuildContext context,
  PlayerProvider player, {
  Track? initialTrack,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final controller = TextEditingController();

  await showDialog(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'New Playlist',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            filled: true,
            fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final playlist = await player.createPlaylist(
                  name,
                  initialTracks: initialTrack != null ? [initialTrack] : null,
                );
                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Created "${playlist.title}"'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}

/// Displays the Rename Playlist dialog
Future<void> showRenamePlaylistDialog(
  BuildContext context,
  PlayerProvider player,
  Playlist playlist,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final controller = TextEditingController(text: playlist.title);

  await showDialog(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor: isDark
            ? AppColors.darkSurfaceElevated
            : AppColors.lightSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rename Playlist',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            filled: true,
            fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != playlist.title) {
                await player.renamePlaylist(playlist.id, newName);
                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Renamed to "$newName"'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

/// Displays the Delete Playlist confirmation dialog
Future<void> showDeletePlaylistDialog(
  BuildContext context,
  PlayerProvider player,
  Playlist playlist, {
  VoidCallback? onDeleted,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showDialog(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor: isDark
            ? AppColors.darkSurfaceElevated
            : AppColors.lightSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Playlist?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete "${playlist.title}"? This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              await player.deletePlaylist(playlist.id);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
              }
              onDeleted?.call();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${playlist.title}"'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  final Track track;
  final bool isDark;

  const _AddToPlaylistSheet({
    required this.track,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final playlists = player.playlists;
    final trackId = track.youtubeVideoId ?? track.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
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

            // Track Header Card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 50,
                      height: 50,
                      color: AppColors.secondary,
                      child: track.thumbnailUrl.isNotEmpty
                          ? Image.network(
                              track.highResThumbnailUrl.isNotEmpty
                                  ? track.highResThumbnailUrl
                                  : track.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.music_note, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
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
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // Queue Actions
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Add to Playing Queue',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Add song to the end of the current queue',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              onTap: () {
                player.addToQueue(track);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added "${track.title}" to queue'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.playlist_play_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              title: const Text(
                'Play Next',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Plays immediately after the current song',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              onTap: () {
                player.playNext(track);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('"${track.title}" will play next'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            const Divider(height: 1, thickness: 0.5),

            // Add to Playlist Section Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ADD TO PLAYLIST',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showCreatePlaylistDialog(
                        context,
                        player,
                        initialTrack: track,
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'New Playlist',
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

            // Playlist items
            Expanded(
              child: playlists.isEmpty
                  ? Center(
                      child: Text(
                        'No playlists yet. Tap "New Playlist" above!',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final isInPlaylist = playlist.tracks.any(
                            (t) => (t.youtubeVideoId ?? t.id) == trackId);

                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 44,
                              height: 44,
                              color: AppColors.secondary,
                              child: playlist.coverUrl != null &&
                                      playlist.coverUrl!.isNotEmpty
                                  ? Image.network(
                                      playlist.coverUrl!,
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            playlist.formattedTrackCount,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          trailing: isInPlaylist
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF10B981),
                                  size: 22,
                                )
                              : const Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 22,
                                ),
                          onTap: () async {
                            if (isInPlaylist) {
                              await player.removeTrackFromPlaylist(
                                  playlist.id, trackId);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Removed from "${playlist.title}"'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } else {
                              await player.addTrackToPlaylist(
                                  playlist.id, track);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Added to "${playlist.title}"'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
