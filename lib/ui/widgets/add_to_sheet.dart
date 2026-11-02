import 'holo_image.dart';
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
    backgroundColor: Colors.transparent,
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

class _AddToPlaylistSheet extends StatefulWidget {
  final Track track;
  final bool isDark;

  const _AddToPlaylistSheet({
    required this.track,
    required this.isDark,
  });

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  bool _isCreating = false;
  late final TextEditingController _newPlaylistController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _newPlaylistController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _newPlaylistController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitNewPlaylist(PlayerProvider player) async {
    final name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;

    final playlist = await player.createPlaylist(
      name,
      initialTracks: [widget.track],
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created "${playlist.title}" and added song'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final playlists = player.playlists;
    final trackId = widget.track.youtubeVideoId ?? widget.track.id;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF11141B) : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: widget.isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF333A4D)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Track Header Preview Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF161A22) : const Color(0xFFF1F4F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.isDark ? const Color(0xFF232838) : const Color(0xFFE2E6EF),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: widget.isDark
                              ? const Color(0xFF222736)
                              : const Color(0xFFE2E6EF),
                          child: Builder(builder: (context) {
                            final vid = widget.track.youtubeVideoId ?? widget.track.id;
                            final highRes = widget.track.highResThumbnailUrl.isNotEmpty
                                ? widget.track.highResThumbnailUrl
                                : widget.track.thumbnailUrl;

                            Widget placeholder() => const Icon(
                                  Icons.music_note_rounded,
                                  color: AppColors.primary,
                                  size: 24,
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

                            if (highRes.isNotEmpty) {
                              return HoloImage(
                                highRes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) {
                                  if (widget.track.thumbnailUrl.isNotEmpty &&
                                      widget.track.thumbnailUrl != highRes) {
                                    return HoloImage(
                                      widget.track.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => buildYtFallback(),
                                    );
                                  }
                                  return buildYtFallback();
                                },
                              );
                            }
                            return placeholder();
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Song',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: widget.isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ),
                                if (widget.track.durationSeconds > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.track.formattedDuration,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: widget.isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary,
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
                ),
              ),

              // Queue Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Column(
                  children: [
                    _ActionTile(
                      isDark: widget.isDark,
                      icon: Icons.queue_music_rounded,
                      iconColor: AppColors.primary,
                      iconBgColor: widget.isDark
                          ? const Color(0xFF281711)
                          : const Color(0xFFFFECE5),
                      title: 'Add to Playing Queue',
                      subtitle: 'Add song to the end of the current queue',
                      onTap: () {
                        player.addToQueue(widget.track);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added "${widget.track.title}" to queue'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _ActionTile(
                      isDark: widget.isDark,
                      icon: Icons.playlist_play_rounded,
                      iconColor: const Color(0xFF10B981),
                      iconBgColor: widget.isDark
                          ? const Color(0xFF11261D)
                          : const Color(0xFFE6F8F0),
                      title: 'Play Next',
                      subtitle: 'Plays immediately after the current song',
                      onTap: () {
                        player.playNext(widget.track);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('"${widget.track.title}" will play next'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Playlist Section Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Playlists',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: widget.isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isCreating = !_isCreating;
                          if (_isCreating) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _focusNode.requestFocus();
                            });
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isCreating
                                  ? Icons.close_rounded
                                  : Icons.add_rounded,
                              size: 17,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isCreating ? 'Cancel' : 'New Playlist',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Inline Playlist Creator Form
              if (_isCreating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF181D27)
                          : const Color(0xFFEEF2F8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newPlaylistController,
                            focusNode: _focusNode,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submitNewPlaylist(player),
                            decoration: InputDecoration(
                              hintText: 'Playlist name...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: widget.isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.lightTextTertiary,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: widget.isDark
                                  ? const Color(0xFF10131A)
                                  : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 11),
                            minimumSize: const Size(0, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _submitNewPlaylist(player),
                          child: const Text(
                            'Create',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Playlist Content: Empty State or Flexible Scrollable List
              if (playlists.isEmpty && !_isCreating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 22, horizontal: 20),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF141720)
                          : const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.isDark
                            ? const Color(0xFF1F2432)
                            : const Color(0xFFE8ECF2),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? const Color(0xFF1D2230)
                                : const Color(0xFFEAF0FA),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.playlist_add_rounded,
                            size: 22,
                            color: widget.isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No playlists yet',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: widget.isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Create a playlist to organize your library.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: widget.isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isCreating = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _focusNode.requestFocus();
                              });
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: widget.isDark ? 0.12 : 0.08,
                            ),
                            side: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 11),
                            minimumSize: const Size(0, 42),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: const Text(
                            'Create Playlist',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (playlists.isNotEmpty)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: playlists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isInPlaylist = playlist.tracks.any(
                          (t) => (t.youtubeVideoId ?? t.id) == trackId);

                      return Material(
                        color: widget.isDark
                            ? const Color(0xFF161A22)
                            : const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
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
                                  playlist.id, widget.track);
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    color: widget.isDark
                                        ? const Color(0xFF222736)
                                        : const Color(0xFFE2E6EF),
                                    child: playlist.coverUrl != null &&
                                            playlist.coverUrl!.isNotEmpty
                                        ? HoloImage(
                                            playlist.coverUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.queue_music_rounded,
                                              color: AppColors.primary,
                                              size: 20,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.queue_music_rounded,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        playlist.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        playlist.formattedTrackCount,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: widget.isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isInPlaylist)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_rounded,
                                          color: Color(0xFF10B981),
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Added',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: widget.isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF161A22) : const Color(0xFFF6F8FB),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
              Icon(
                Icons.add_rounded,
                size: 20,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
