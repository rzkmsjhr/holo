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

  /// Clients to query for stream manifests to bypass web client cipher/SABR restrictions
  static const List<YoutubeApiClient> _preferredClients = [
    YoutubeApiClient.safari,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
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

  /// Extracts the highest bitrate stream that contains audio (audio-only preferred, then muxed)
  String? _extractBestAudioUrl(StreamManifest manifest) {
    if (manifest.audioOnly.isNotEmpty) {
      final bestAudio = manifest.audioOnly.withHighestBitrate();
      return bestAudio.url.toString();
    }
    if (manifest.muxed.isNotEmpty) {
      // Muxed streams contain video and audio; just_audio can decode and play the audio track natively
      final bestMuxed = manifest.muxed.withHighestBitrate();
      return bestMuxed.url.toString();
    }
    return null;
  }

  /// Resolves a playable audio stream for a track, first trying [primaryVideoId].
  /// If [primaryVideoId] is unavailable or fails, automatically searches for alternative
  /// YouTube video candidates for [artist] and [title].
  Future<StreamResolutionResult> resolveStreamForTrack({
    required String title,
    required String artist,
    String? primaryVideoId,
  }) async {
    final cleanId = primaryVideoId?.trim() ?? '';
    final isRealId = cleanId.isNotEmpty &&
        !cleanId.startsWith('trending_') &&
        !cleanId.startsWith('track_');

    if (isRealId) {
      final directUrl = await getAudioStreamUrl(cleanId);
      if (directUrl != null && directUrl.isNotEmpty) {
        return StreamResolutionResult.success(directUrl, cleanId);
      }
    }

    // Primary ID failed or was missing; perform fallback candidate search
    return resolveAlternativeStream(
      title: title,
      artist: artist,
      failedVideoId: cleanId,
    );
  }

  /// Searches for alternative YouTube videos for a track, excluding [failedVideoId]
  Future<StreamResolutionResult> resolveAlternativeStream({
    required String title,
    required String artist,
    String? failedVideoId,
  }) async {
    final searchQueries = [
      '$artist $title audio',
      '$artist $title',
      '$title $artist',
    ];

    final attemptedIds = <String>{};
    if (failedVideoId != null && failedVideoId.isNotEmpty) {
      attemptedIds.add(failedVideoId);
    }

    for (final query in searchQueries) {
      try {
        final searchResults = await _yt.search
            .search(query)
            .timeout(const Duration(seconds: 5));

        for (final video in searchResults.take(4)) {
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
      'YouTube audio is restricted or unavailable for "$title" by $artist.',
    );
  }

  void dispose() {
    _yt.close();
  }
}
