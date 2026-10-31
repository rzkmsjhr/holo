import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/player_provider.dart';
import '../widgets/live_equalizer_bars.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  void _showClearQueueDialog(BuildContext context, PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.darkSurfaceElevated : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear Queue?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to remove all upcoming tracks from the queue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
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
            onPressed: () {
              player.clearQueue();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = player.queue;
    final currentTrack = player.currentTrack;
    final currentIndex = player.currentIndex;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0F14) : AppColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Playing Queue',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              '${queue.length} tracks • ${currentTrack?.isLossless == true ? "Hi-Fi FLAC" : "Stereo"}',
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
        actions: [
          if (queue.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 22),
              tooltip: 'Clear Queue',
              onPressed: () => _showClearQueueDialog(context, player),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: queue.isEmpty
            ? Center(
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
                    Text(
                      'Queue is empty',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              )
            : CustomScrollView(
                slivers: [
                  // Now Playing Header & Card
                  if (currentTrack != null) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? AppColors.darkSurfaceElevated
                                  : AppColors.lightSurfaceElevated)
                              .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 48,
                                height: 48,
                                color: AppColors.secondary,
                                child: currentTrack.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        currentTrack
                                                .highResThumbnailUrl.isNotEmpty
                                            ? currentTrack.highResThumbnailUrl
                                            : currentTrack.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.high,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                          Icons.music_note,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.music_note,
                                        color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentTrack.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          currentTrack.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? AppColors.darkTextSecondary
                                                : AppColors.lightTextSecondary,
                                          ),
                                        ),
                                      ),
                                      if (currentTrack.isLossless) ...[
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
                            const SizedBox(width: 8),
                            LiveEqualizerBars(
                              isPlaying: player.isPlaying,
                              barCount: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Up Next Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'UP NEXT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                          Text(
                            'Swipe left to remove',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Reorderable Queue List
                  SliverReorderableList(
                    itemCount: queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      player.reorderQueue(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 8,
                        color: isDark
                            ? const Color(0xFF1D212C)
                            : AppColors.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;

                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(track.id + index.toString()),
                        index: index,
                        child: Material(
                          color: Colors.transparent,
                          child: Dismissible(
                            key: ValueKey('dismiss_${track.id}_$index'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              child: const Icon(Icons.delete_outline,
                                  color: Colors.white, size: 24),
                            ),
                            onDismissed: (_) {
                              player.removeFromQueue(index);
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => player.playTrack(track),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    // Immediate Drag Handle
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 8),
                                        child: Icon(
                                          Icons.drag_indicator_rounded,
                                          size: 22,
                                          color: isDark
                                              ? AppColors.darkTextTertiary
                                              : AppColors.lightTextTertiary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                  // Track Art
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      color: AppColors.secondary,
                                      child: track.thumbnailUrl.isNotEmpty
                                          ? Image.network(
                                              track
                                                      .highResThumbnailUrl
                                                      .isNotEmpty
                                                  ? track.highResThumbnailUrl
                                                  : track.thumbnailUrl,
                                              fit: BoxFit.cover,
                                              filterQuality:
                                                  FilterQuality.high,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(Icons.music_note,
                                                      color: Colors.white,
                                                      size: 20),
                                            )
                                          : const Icon(Icons.music_note,
                                              color: Colors.white, size: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Title & Artist
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isCurrent
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: isCurrent
                                                ? AppColors.primary
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                track.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? AppColors
                                                          .darkTextSecondary
                                                      : AppColors
                                                          .lightTextSecondary,
                                                ),
                                              ),
                                            ),
                                            if (track.isLossless) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 1),
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

                                  // Duration
                                  Text(
                                    track.formattedDuration,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      child: Center(
                        child: player.isEndlessPlay
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurfaceElevated)
                                      .withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.all_inclusive_rounded,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      player.isFetchingEndless
                                          ? 'Finding next vibe tracks...'
                                          : 'Endless Play active • Autoplaying similar vibe',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox(height: 24),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
