import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamResolutionResult {
  final String? url;
  final String? videoId;
  final String? errorMessage;
  final bool isSuccess;

  const StreamResolutionResult({
    this.url,
    this.videoId,
    this.errorMessage,
    required this.isSuccess,
  });

  factory StreamResolutionResult.success(String url, String videoId) =>
      StreamResolutionResult(
        url: url,
        videoId: videoId,
        isSuccess: true,
      );

  factory StreamResolutionResult.failure(String message) =>
      StreamResolutionResult(
        errorMessage: message,
        isSuccess: false,
      );
}

class YouTubeStreamResolver {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Preferred clients to query for stream manifests to bypass cipher / SABR blocks
  static final List<YoutubeApiClient> _preferredClients = [
    YoutubeApiClient.android,
    YoutubeApiClient.ios,
    YoutubeApiClient.safari,
    YoutubeApiClient.androidVr,
  ];

  /// Resolves direct audio stream URL for a YouTube video.
  /// Falls back across client emulations and checks both audio-only and muxed streams.
  Future<String?> getAudioStreamUrl(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return null;

    // 1. Try with preferred mobile / embedded client emulations
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId, ytClients: _preferredClients)
          .timeout(const Duration(seconds: 8));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        return streamUrl;
      }
    } catch (_) {}

    // 2. Fallback to default client manifest
    try {
      final defaultManifest = await _yt.videos.streamsClient
          .getManifest(cleanId)
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(defaultManifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        return streamUrl;
      }
    } catch (_) {}

    return null;
  }

  /// Extracts the highest bitrate stream that contains audio (audio-only preferred, then muxed).
  /// Prefers MP4/M4A (AAC) for universal cross-platform compatibility across Android & iOS.
  String? _extractBestAudioUrl(StreamManifest manifest) {
    if (manifest.audioOnly.isNotEmpty) {
      final mp4Audios = manifest.audioOnly
          .where((a) => a.container.name.toLowerCase().contains('mp4'))
          .toList();
      if (mp4Audios.isNotEmpty) {
        return mp4Audios.withHighestBitrate().url.toString();
      }
      return manifest.audioOnly.withHighestBitrate().url.toString();
    }
    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate().url.toString();
    }
    return null;
  }

  /// Cleans noise, parentheses, and brackets from titles for maximum YouTube search recall
  static String cleanTitle(String title) {
    var cleaned = title
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(
            RegExp(
                r'\s*[-–—]\s*(?:official(?:\s*music)?\s*video|lyric\s*video|official\s*audio|video|audio|visualizer|remaster(?:ed)?|live).*$',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : title.trim();
  }

  /// Resolves a playable audio stream for a track, first trying [primaryVideoId].
  /// If [primaryVideoId] is unavailable or fails, automatically searches for alternative
  /// YouTube video candidates for [artist] and [title].
  Future<StreamResolutionResult> resolveStreamForTrack({
    required String title,
    required String artist,
    String? primaryVideoId,
    Set<String>? excludedVideoIds,
  }) async {
    final cleanId = primaryVideoId?.trim() ?? '';
    final isRealId = cleanId.isNotEmpty &&
        !cleanId.startsWith('trending_') &&
        !cleanId.startsWith('track_');

    if (isRealId && (excludedVideoIds == null || !excludedVideoIds.contains(cleanId))) {
      final directUrl = await getAudioStreamUrl(cleanId);
      if (directUrl != null && directUrl.isNotEmpty) {
        return StreamResolutionResult.success(directUrl, cleanId);
      }
    }

    // Primary ID failed or was missing/excluded; perform fallback candidate search
    return resolveAlternativeStream(
      title: title,
      artist: artist,
      failedVideoId: cleanId,
      excludedVideoIds: excludedVideoIds,
    );
  }

  /// Searches for alternative YouTube videos for a track, excluding already attempted IDs
  Future<StreamResolutionResult> resolveAlternativeStream({
    required String title,
    required String artist,
    String? failedVideoId,
    Set<String>? excludedVideoIds,
  }) async {
    final cleanT = cleanTitle(title);
    final cleanA = artist.replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '').trim();

    final searchQueries = <String>[];
    if (cleanT.toLowerCase() != title.toLowerCase()) {
      searchQueries.add('$cleanA $cleanT');
      searchQueries.add('$cleanT $cleanA');
      searchQueries.add('$cleanA $cleanT official video');
      searchQueries.add('$cleanA $cleanT lyric video');
    }
    searchQueries.add('$cleanA $title');
    searchQueries.add('$artist $title');
    searchQueries.add('$artist $title official');
    searchQueries.add('$title $artist');
    searchQueries.add('$artist $title lyric');

    final attemptedIds = <String>{};
    if (failedVideoId != null && failedVideoId.isNotEmpty) {
      attemptedIds.add(failedVideoId);
    }
    if (excludedVideoIds != null) {
      attemptedIds.addAll(excludedVideoIds);
    }

    for (final query in searchQueries) {
      try {
        final searchResults = await _yt.search
            .search(query)
            .timeout(const Duration(seconds: 5));

        for (final video in searchResults.take(5)) {
          final candId = video.id.value;
          if (attemptedIds.contains(candId)) continue;
          attemptedIds.add(candId);

          final streamUrl = await getAudioStreamUrl(candId);
          if (streamUrl != null && streamUrl.isNotEmpty) {
            return StreamResolutionResult.success(streamUrl, candId);
          }
        }
      } catch (_) {}
    }

    return StreamResolutionResult.failure(
      'Unable to stream "$title" by $artist.',
    );
  }

  void dispose() {
    _yt.close();
  }
}
