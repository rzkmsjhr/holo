import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/playlist.dart';
import 'holo_image.dart';

/// Dynamic playlist cover preview widget.
/// - If the playlist has an explicit imported custom coverUrl, displays that cover.
/// - If user-created without a custom cover, dynamically slides through the cover arts
///   of the tracks inside the playlist every ~3.2 seconds without requiring file permissions.
/// - If empty or single-track, displays static cover or musical placeholder.
class PlaylistCoverPreview extends StatefulWidget {
  final Playlist playlist;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const PlaylistCoverPreview({
    super.key,
    required this.playlist,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  State<PlaylistCoverPreview> createState() => _PlaylistCoverPreviewState();
}

class _PlaylistCoverPreviewState extends State<PlaylistCoverPreview> {
  Timer? _cycleTimer;
  int _currentIndex = 0;
  List<String> _uniqueArtworks = [];

  @override
  void initState() {
    super.initState();
    _extractArtworks();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant PlaylistCoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id ||
        oldWidget.playlist.tracks.length != widget.playlist.tracks.length ||
        oldWidget.playlist.coverUrl != widget.playlist.coverUrl) {
      _extractArtworks();
      _startTimerIfNeeded();
    }
  }

  void _extractArtworks() {
    final urls = <String>[];
    for (final t in widget.playlist.tracks) {
      final art = t.highResThumbnailUrl.isNotEmpty
          ? t.highResThumbnailUrl
          : t.thumbnailUrl;
      if (art.isNotEmpty && !art.contains('unsplash.com') && !urls.contains(art)) {
        urls.add(art);
      }
    }
    _uniqueArtworks = urls;
    if (_currentIndex >= _uniqueArtworks.length) {
      _currentIndex = 0;
    }
  }

  void _startTimerIfNeeded() {
    _cycleTimer?.cancel();
    _cycleTimer = null;

    // Only cycle when there is no explicit custom cover and >= 2 distinct track artworks
    final hasExplicitCustomCover = widget.playlist.coverUrl != null &&
        widget.playlist.coverUrl!.isNotEmpty &&
        !_uniqueArtworks.contains(widget.playlist.coverUrl);

    if (!hasExplicitCustomCover && _uniqueArtworks.length >= 2) {
      _cycleTimer = Timer.periodic(const Duration(milliseconds: 3200), (timer) {
        if (!mounted) return;
        setState(() {
          _currentIndex = (_currentIndex + 1) % _uniqueArtworks.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: AppColors.secondary,
      child: const Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius ?? BorderRadius.circular(10);

    // 1. Explicit custom/imported cover
    final hasExplicitCustomCover = widget.playlist.coverUrl != null &&
        widget.playlist.coverUrl!.isNotEmpty &&
        !_uniqueArtworks.contains(widget.playlist.coverUrl);

    if (hasExplicitCustomCover) {
      return ClipRRect(
        borderRadius: r,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: HoloImage(
            widget.playlist.coverUrl!,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          ),
        ),
      );
    }

    // 2. Empty playlist
    if (_uniqueArtworks.isEmpty) {
      return ClipRRect(
        borderRadius: r,
        child: _buildPlaceholder(),
      );
    }

    // 3. Single artwork
    if (_uniqueArtworks.length == 1) {
      return ClipRRect(
        borderRadius: r,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: HoloImage(
            _uniqueArtworks.first,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          ),
        ),
      );
    }

    // 4. Dynamic sliding/moving thumbnails (>= 2 artworks)
    final currentUrl = _uniqueArtworks[_currentIndex % _uniqueArtworks.length];

    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.secondary,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final inAnimation = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation);
            return SlideTransition(
              position: inAnimation,
              child: child,
            );
          },
          child: SizedBox(
            key: ValueKey('cover_${widget.playlist.id}_$currentUrl'),
            width: widget.width,
            height: widget.height,
            child: HoloImage(
              currentUrl,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => _buildPlaceholder(),
            ),
          ),
        ),
      ),
    );
  }
}
