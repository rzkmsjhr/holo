import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Persistent disk-cached network image widget.
/// Once an album/cover art URL is loaded once, it is stored on device storage
/// and loads instantly without re-downloading.
class HoloImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final Widget? placeholder;

  const HoloImage(
    this.imageUrl, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.high,
    this.errorBuilder,
    this.loadingBuilder,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      if (errorBuilder != null) {
        return errorBuilder!(context, 'Empty image URL', null);
      }
      return placeholder ?? const SizedBox.shrink();
    }

    if (kIsWeb) {
      return Image.network(
        imageUrl,
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        filterQuality: filterQuality,
        loadingBuilder: loadingBuilder,
        errorBuilder: errorBuilder,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      filterQuality: filterQuality,
      fadeInDuration: const Duration(milliseconds: 100),
      fadeOutDuration: Duration.zero,
      placeholder: (ctx, url) {
        if (placeholder != null) return placeholder!;
        if (loadingBuilder != null) {
          return loadingBuilder!(
            ctx,
            const SizedBox.shrink(),
            const ImageChunkEvent(cumulativeBytesLoaded: 0, expectedTotalBytes: 100),
          );
        }
        return const SizedBox.shrink();
      },
      errorWidget: (ctx, url, error) {
        if (errorBuilder != null) {
          return errorBuilder!(ctx, error, null);
        }
        return placeholder ?? const SizedBox.shrink();
      },
    );
  }
}
