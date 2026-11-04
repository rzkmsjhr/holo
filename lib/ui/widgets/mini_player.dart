import 'holo_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/player_provider.dart';
import '../screens/now_playing_sheet.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) =>
                const NowPlayingSheet(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
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
      },
      child: Container(
        height: 58,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurface.withValues(alpha: 0.92)
              : AppColors.lightSurface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 40,
                        height: 40,
                        color: AppColors.secondary,
                        child: Builder(builder: (context) {
                          final cachedArt =
                              player.getArtwork(track.artist, track.title);
                          final art = (cachedArt != null && cachedArt.isNotEmpty)
                              ? cachedArt
                              : (track.highResThumbnailUrl.isNotEmpty
                                  ? track.highResThumbnailUrl
                                  : (track.thumbnailUrl.isNotEmpty
                                      ? track.thumbnailUrl
                                      : null));

                          final hasValidThumb = track.thumbnailUrl.isNotEmpty &&
                              !track.thumbnailUrl.contains('unsplash.com');
                          if ((cachedArt == null || cachedArt.isEmpty) && !hasValidThumb) {
                            player.resolveArtworkFor(track.artist, track.title);
                          }

                          final vid = track.youtubeVideoId ?? track.id;

                          Widget placeholderIcon() => const Icon(
                                Icons.music_note,
                                color: Colors.white,
                                size: 20,
                              );

                          Widget buildYtFallback() {
                            if (vid.length == 11) {
                              return HoloImage(
                                'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
                                fit: BoxFit.cover,
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
                                errorBuilder: (_, __, ___) => buildYtFallback(),
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
                    const SizedBox(width: 10),

                    // Title & Artist
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
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
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'FLAC',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0A0C10),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (player.playbackError != null)
                            Text(
                              player.playbackError!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Controls
                    if (player.currentIndex > 0)
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 24),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 36),
                        onPressed: () => player.previous(),
                      ),
                    if (player.isBuffering)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: AppColors.primary,
                          size: 34,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => player.togglePlayPause(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 24),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 36),
                      onPressed: () => player.next(),
                    ),
                  ],
                ),
              ),

              // Bottom Progress Line
              Positioned(
                left: 10,
                right: 10,
                bottom: 0,
                child: ValueListenableBuilder<Duration>(
                  valueListenable: player.positionNotifier,
                  builder: (context, pos, _) {
                    final progress = player.duration.inMilliseconds > 0
                        ? (pos.inMilliseconds / player.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
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
