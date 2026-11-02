import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// Optional listener/debugger callback for real-time diagnostic logs
  void Function(String message)? onLog;

  void _log(String message) {
    onLog?.call(message);
    debugPrint('[YouTubeResolver] $message');
  }

  /// Resolves direct audio stream URL for a YouTube video.
  /// Tries clients individually with detailed logging so no failure is hidden or guessed.
  Future<String?> getAudioStreamUrl(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) {
      _log('getAudioStreamUrl: videoId is empty');
      return null;
    }
    _log('Extracting audio for videoId: "$cleanId"...');

    // 1. Try androidSdkless (most reliable for avoiding PO-token / bot checks)
    try {
      _log('Trying client: androidSdkless for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId, ytClients: [YoutubeApiClient.androidSdkless])
          .timeout(const Duration(seconds: 8));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: androidSdkless resolved stream for "$cleanId" (audio count: ${manifest.audioOnly.length})');
        return streamUrl;
      }
      _log('androidSdkless manifest had 0 audio streams for "$cleanId"');
    } catch (e) {
      _log('androidSdkless failed for "$cleanId": $e');
    }

    // 2. Try default manifest client
    try {
      _log('Trying default client for "$cleanId"...');
      final defaultManifest = await _yt.videos.streamsClient
          .getManifest(cleanId)
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(defaultManifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: Default client resolved stream for "$cleanId" (audio count: ${defaultManifest.audioOnly.length})');
        return streamUrl;
      }
      _log('Default client manifest had 0 audio streams for "$cleanId"');
    } catch (e) {
      _log('Default client failed for "$cleanId": $e');
    }

    // 3. Try standard android client
    try {
      _log('Trying client: android for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId, ytClients: [YoutubeApiClient.android])
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: android client resolved stream for "$cleanId"');
        return streamUrl;
      }
    } catch (e) {
      _log('android client failed for "$cleanId": $e');
    }

    // 4. Try iOS client
    try {
      _log('Trying client: ios for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId, ytClients: [YoutubeApiClient.ios])
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: ios client resolved stream for "$cleanId"');
        return streamUrl;
      }
    } catch (e) {
      _log('ios client failed for "$cleanId": $e');
    }

    _log('FAILURE: All client extractors failed for videoId "$cleanId"');
    return null;
  }

  /// Extracts the highest bitrate stream that contains audio (audio-only preferred, then muxed).
  /// Prefers MP4/M4A (AAC) for universal cross-platform compatibility across Android, iOS & Web.
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

    _log('resolveStreamForTrack: title="$title", artist="$artist", primaryId="$cleanId", isRealId=$isRealId');

    if (isRealId && (excludedVideoIds == null || !excludedVideoIds.contains(cleanId))) {
      _log('Step 1: Attempting direct extraction on primaryId "$cleanId"...');
      final directUrl = await getAudioStreamUrl(cleanId);
      if (directUrl != null && directUrl.isNotEmpty) {
        _log('Primary videoId "$cleanId" succeeded directly!');
        return StreamResolutionResult.success(directUrl, cleanId);
      }
      _log('Primary videoId "$cleanId" failed direct extraction. Proceeding to candidate search...');
    } else {
      _log('Primary videoId is invalid, synthetic, or excluded: "$cleanId". Proceeding to candidate search...');
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

    _log('Candidate fallback search started for "$title" by "$artist". Attempted IDs so far: $attemptedIds');
    _log('Queries: $searchQueries');

    for (final query in searchQueries) {
      try {
        _log('Running search query: "$query"...');
        final searchResults = await _yt.search
            .search(query)
            .timeout(const Duration(seconds: 6));

        _log('Query "$query" returned ${searchResults.length} video results');

        for (final video in searchResults.take(5)) {
          final candId = video.id.value;
          if (attemptedIds.contains(candId)) {
            _log('Skipping candidate [$candId] (already attempted)');
            continue;
          }
          attemptedIds.add(candId);
          _log('Evaluating candidate: [$candId] "${video.title}" by "${video.author}" (duration: ${video.duration})');

          final streamUrl = await getAudioStreamUrl(candId);
          if (streamUrl != null && streamUrl.isNotEmpty) {
            _log('SUCCESS: Candidate [$candId] yielded valid stream URL!');
            return StreamResolutionResult.success(streamUrl, candId);
          } else {
            _log('Candidate [$candId] failed audio extraction');
          }
        }
      } catch (e) {
        _log('Search query "$query" failed with error: $e');
      }
    }

    _log('FAILURE: All ${searchQueries.length} search queries exhausted without finding a playable candidate.');
    return StreamResolutionResult.failure(
      'Unable to stream "$title" by $artist.',
    );
  }

  void dispose() {
    _yt.close();
  }
}
