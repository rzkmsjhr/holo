import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../core/network/holo_http_client.dart';
import 'youtube_music_service.dart';

class StreamInfo {
  final String url;
  final bool isVideo;
  final String title;
  final String author;

  const StreamInfo({
    required this.url,
    required this.isVideo,
    this.title = '',
    this.author = '',
  });
}

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

  static const String _innertubePlayerUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';
  static const String _innertubeSearchUrl =
      'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
  static const String _androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip';

  /// Optional listener/debugger callback for real-time diagnostic logs
  void Function(String message)? onLog;

  void _log(String message) {
    onLog?.call(message);
    debugPrint('[YouTubeResolver] $message');
  }

  /// Resolves direct progressive stream URL and video metadata for a YouTube video.
  Future<StreamInfo?> getStreamInfo(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return null;

    final directInnertube = await _extractDirectInnertubeStreamInfo(cleanId);
    if (directInnertube != null) {
      return directInnertube;
    }

    final fallbackUrl = await getAudioStreamUrl(cleanId);
    if (fallbackUrl != null) {
      return StreamInfo(url: fallbackUrl, isVideo: false);
    }
    return null;
  }

  /// Resolves direct progressive stream URL for a YouTube video.
  /// Prioritizes progressive MP4 (`itag=18` with `ratebypass=yes`) which supports
  /// standard HTTP Range requests (`bytes=0-`) and full-track seeking without HTTP 403.
  Future<String?> getAudioStreamUrl(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) {
      _log('getAudioStreamUrl: videoId is empty');
      return null;
    }
    _log('Extracting stream for videoId: "$cleanId"...');

    // 1. Direct Innertube ANDROID 20.10.38 player API (fastest, bypasses WatchPage & Set-Cookie crash)
    final directInnertube = await _extractDirectInnertubeStreamInfo(cleanId);
    if (directInnertube != null && directInnertube.url.isNotEmpty) {
      return directInnertube.url;
    }

    // 2. Try YoutubeExplode androidSdkless with requireWatchPage: false
    try {
      _log('Trying client: androidSdkless (requireWatchPage: false) for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(
            cleanId,
            ytClients: [YoutubeApiClient.androidSdkless],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: androidSdkless resolved stream for "$cleanId" (muxed: ${manifest.muxed.length}, audioOnly: ${manifest.audioOnly.length})');
        return streamUrl;
      }
      _log('androidSdkless manifest had 0 playable streams for "$cleanId"');
    } catch (e) {
      _log('androidSdkless failed for "$cleanId": $e');
    }

    // 3. Try YoutubeExplode android client with requireWatchPage: false
    try {
      _log('Trying client: android (requireWatchPage: false) for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(
            cleanId,
            ytClients: [YoutubeApiClient.android],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: android client resolved stream for "$cleanId"');
        return streamUrl;
      }
    } catch (e) {
      _log('android client failed for "$cleanId": $e');
    }

    // 4. Try YoutubeExplode ios client with requireWatchPage: false
    try {
      _log('Trying client: ios (requireWatchPage: false) for "$cleanId"...');
      final manifest = await _yt.videos.streamsClient
          .getManifest(
            cleanId,
            ytClients: [YoutubeApiClient.ios],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 6));

      final streamUrl = _extractBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        _log('SUCCESS: ios client resolved stream for "$cleanId"');
        return streamUrl;
      }
    } catch (e) {
      _log('ios client failed for "$cleanId": $e');
    }

    _log('FAILURE: All direct client extractors failed for videoId "$cleanId"');
    return null;
  }

  /// Queries YouTube Innertube `/youtubei/v1/player` directly using ANDROID 20.10.38.
  /// Extracts progressive MP4 (`formats`, `itag=18`) first because YouTube's CDN
  /// grants `ratebypass=yes` and unrestricted `Range: bytes=0-` / full-file seeking on `itag=18`,
  /// whereas `adaptiveFormats` (`audioOnly`) carry a `bui` token that rejects `Range: bytes=0-` with HTTP 403.
  Future<StreamInfo?> _extractDirectInnertubeStreamInfo(String videoId) async {
    final clients = <Map<String, dynamic>>[
      {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'androidSdkVersion': 34,
        'osName': 'Android',
        'osVersion': '14',
        'hl': 'en',
        'gl': 'US',
      },
      {
        'clientName': 'IOS',
        'clientVersion': '20.10.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.3.2.22D82',
        'hl': 'en',
        'gl': 'US',
      },
    ];

    for (final client in clients) {
      final clientName = client['clientName'] as String;
      try {
        _log('Trying direct Innertube $clientName player for "$videoId"...');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (!kIsWeb && clientName == 'ANDROID') 'User-Agent': _androidUserAgent,
        };

        final response = await HoloHttpClient.client
            .post(
              Uri.parse(_innertubePlayerUrl),
              headers: headers,
              body: jsonEncode({
                'videoId': videoId,
                'contentCheckOk': true,
                'racyCheckOk': true,
                'context': {'client': client},
              }),
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode != 200) {
          _log('Direct Innertube $clientName returned HTTP ${response.statusCode} for "$videoId"');
          continue;
        }

        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final status = data['playabilityStatus']?['status']?.toString() ?? 'UNKNOWN';
        if (status != 'OK') {
          final reason = data['playabilityStatus']?['reason']?.toString() ?? status;
          _log('Direct Innertube $clientName status=$status ($reason) for "$videoId"');
          continue;
        }

        final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
        final vTitle = videoDetails?['title']?.toString() ?? '';
        final vAuthor = videoDetails?['author']?.toString() ?? '';
        final vDesc = videoDetails?['shortDescription']?.toString() ?? '';
        final isTopic = vAuthor.toLowerCase().endsWith('- topic') ||
            vDesc.contains('Auto-generated by YouTube') ||
            vDesc.contains('Provided to YouTube by');
        final isVideo = YouTubeMusicService.isVideoRecord(vTitle, vAuthor) && !isTopic;

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) continue;

        // Priority 1: Progressive muxed MP4 (`formats`, e.g. itag=18) — supports full Range: bytes=0- & seeking without 403
        final formats = streamingData['formats'] as List?;
        if (formats != null && formats.isNotEmpty) {
          for (final f in formats) {
            if (f is Map) {
              final url = f['url']?.toString();
              final mime = (f['mimeType']?.toString() ?? '').toLowerCase();
              if (url != null && url.isNotEmpty && mime.contains('mp4')) {
                _log('SUCCESS: Direct Innertube $clientName resolved progressive MP4 (itag=${f['itag']}) for "$videoId"');
                return StreamInfo(
                  url: url,
                  isVideo: isVideo,
                  title: vTitle,
                  author: vAuthor,
                );
              }
            }
          }
          final firstUrl = (formats.first as Map)['url']?.toString();
          if (firstUrl != null && firstUrl.isNotEmpty) {
            _log('SUCCESS: Direct Innertube $clientName resolved progressive stream for "$videoId"');
            return StreamInfo(
              url: firstUrl,
              isVideo: isVideo,
              title: vTitle,
              author: vAuthor,
            );
          }
        }

        // Priority 2: Adaptive audio streams if progressive formats are absent
        final adaptive = streamingData['adaptiveFormats'] as List?;
        if (adaptive != null && adaptive.isNotEmpty) {
          String? bestMp4Audio;
          String? bestAnyAudio;
          int bestMp4Bitrate = -1;
          int bestAnyBitrate = -1;

          for (final f in adaptive) {
            if (f is Map) {
              final url = f['url']?.toString();
              final mime = (f['mimeType']?.toString() ?? '').toLowerCase();
              final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
              final contentLen = f['contentLength']?.toString();
              if (url != null && url.isNotEmpty && mime.startsWith('audio/')) {
                final rangedUrl = (contentLen != null && !url.contains('&range='))
                    ? '$url&range=0-$contentLen'
                    : url;
                if (mime.contains('mp4') && bitrate > bestMp4Bitrate) {
                  bestMp4Bitrate = bitrate;
                  bestMp4Audio = rangedUrl;
                }
                if (bitrate > bestAnyBitrate) {
                  bestAnyBitrate = bitrate;
                  bestAnyAudio = rangedUrl;
                }
              }
            }
          }

          final chosen = bestMp4Audio ?? bestAnyAudio;
          if (chosen != null) {
            _log('SUCCESS: Direct Innertube $clientName resolved adaptive audio for "$videoId"');
            return StreamInfo(
              url: chosen,
              isVideo: isVideo,
              title: vTitle,
              author: vAuthor,
            );
          }
        }
      } catch (e) {
        _log('Direct Innertube $clientName failed for "$videoId": $e');
      }
    }
    return null;
  }

  /// Extracts the most reliable playable stream from a YoutubeExplode [StreamManifest].
  /// Prefers progressive muxed MP4 (`itag=18`) first because it carries `ratebypass=yes`
  /// and never returns HTTP 403 on `Range: bytes=0-` or past 60 seconds.
  String? _extractBestAudioUrl(StreamManifest manifest) {
    if (manifest.muxed.isNotEmpty) {
      final mp4Muxed = manifest.muxed
          .where((m) => m.container.name.toLowerCase().contains('mp4'))
          .toList();
      if (mp4Muxed.isNotEmpty) {
        return mp4Muxed.withHighestBitrate().url.toString();
      }
      return manifest.muxed.withHighestBitrate().url.toString();
    }
    if (manifest.audioOnly.isNotEmpty) {
      final mp4Audios = manifest.audioOnly
          .where((a) => a.container.name.toLowerCase().contains('mp4'))
          .toList();
      final chosen = mp4Audios.isNotEmpty
          ? mp4Audios.withHighestBitrate()
          : manifest.audioOnly.withHighestBitrate();
      final rawUrl = chosen.url.toString();
      final totalBytes = chosen.size.totalBytes;
      if (totalBytes > 0 && !rawUrl.contains('&range=')) {
        return '$rawUrl&range=0-$totalBytes';
      }
      return rawUrl;
    }
    return null;
  }

  /// Fast structured search returning candidate YouTube Music Song / "- Topic" video IDs.
  Future<List<String>> searchCandidateVideoIds(String query) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return const [];

    final ids = <String>[];
    final seen = <String>{};

    // 1. Primary: Use YouTubeMusicService.searchSongs (structured JSON, Songs filter, strict video/karaoke rejection)
    try {
      final ytmService = YouTubeMusicService();
      final tracks = await ytmService.searchSongs(cleanQ);
      for (final track in tracks) {
        final id = (track.youtubeVideoId ?? track.id).trim();
        if (id.isNotEmpty && seen.add(id)) {
          ids.add(id);
        }
      }
    } catch (e) {
      _log('YouTubeMusicService searchSongs failed for "$cleanQ": $e');
    }

    if (ids.isNotEmpty) {
      return ids;
    }

    // 2. Fallback: Regular YouTube search with " topic" appended to strictly return "- Topic" official audio tracks
    try {
      final topicQuery = cleanQ.toLowerCase().endsWith(' topic')
          ? cleanQ
          : '$cleanQ topic';
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final response = await HoloHttpClient.client
          .post(
            Uri.parse(_innertubeSearchUrl),
            headers: headers,
            body: jsonEncode({
              'query': topicQuery,
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': '2.20250201.00.00',
                  'hl': 'en',
                  'gl': 'US',
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final bodyText = utf8.decode(response.bodyBytes);
        final matches = RegExp(r'"videoRenderer":\{"videoId":"([a-zA-Z0-9_-]{11})"')
            .allMatches(bodyText);
        for (final m in matches) {
          final id = m.group(1);
          if (id != null && seen.add(id)) {
            ids.add(id);
          }
        }
        if (ids.isEmpty) {
          final fallbackMatches =
              RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"').allMatches(bodyText);
          for (final m in fallbackMatches) {
            final id = m.group(1);
            if (id != null && seen.add(id)) {
              ids.add(id);
            }
          }
        }
      }
    } catch (e) {
      _log('Innertube JSON topic search failed for "$cleanQ": $e');
    }

    if (ids.isNotEmpty) {
      return ids;
    }

    // 3. Fallback to YoutubeExplode search only on native platforms (with " topic" appended)
    if (!kIsWeb) {
      try {
        final topicQuery = cleanQ.toLowerCase().endsWith(' topic')
            ? cleanQ
            : '$cleanQ topic';
        final searchResults =
            await _yt.search.search(topicQuery).timeout(const Duration(seconds: 5));
        for (final v in searchResults.take(10)) {
          final author = v.author.toLowerCase();
          final title = v.title.toLowerCase();
          // Avoid videos and prefer topic tracks or non-video official audio
          if (!YouTubeMusicService.isVideoRecord(title, author) &&
              seen.add(v.id.value)) {
            ids.add(v.id.value);
          }
        }
      } catch (e) {
        _log('Fallback _yt.search failed for "$cleanQ": $e');
      }
    }

    return ids;
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

  /// Builds prioritized search queries for [title] and [artist] targeting "song" / "- Topic" tracks.
  static List<String> buildSearchQueries(String title, String artist) {
    final cleanT = cleanTitle(title);
    final cleanA = artist
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
        .trim();

    final queries = <String>[];
    void addUnique(String q) {
      final trimmed = q.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (trimmed.isNotEmpty && !queries.contains(trimmed)) {
        queries.add(trimmed);
      }
    }

    addUnique('$cleanA $cleanT');
    addUnique('$cleanA $cleanT topic');
    addUnique('$cleanT $cleanA');
    addUnique('$cleanA $title');
    addUnique('$cleanA $cleanT official audio');

    return queries;
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

    StreamInfo? primaryStreamInfo;

    if (isRealId &&
        (excludedVideoIds == null || !excludedVideoIds.contains(cleanId))) {
      // On Web, route directly to the Cloudflare Worker YouTube IFrame Bridge
      // for instant (<1s) playback without browser CORS delays.
      if (kIsWeb) {
        _log('Web platform: routing primaryId "$cleanId" via Cloudflare Worker YouTube IFrame Bridge.');
        return StreamResolutionResult.success('yt-iframe://$cleanId', cleanId);
      }

      _log('Step 1: Attempting direct extraction on primaryId "$cleanId"...');
      primaryStreamInfo = await getStreamInfo(cleanId);
      if (primaryStreamInfo != null && primaryStreamInfo.url.isNotEmpty) {
        if (!primaryStreamInfo.isVideo) {
          _log('Primary videoId "$cleanId" succeeded directly as studio/topic audio ("${primaryStreamInfo.title}")!');
          return StreamResolutionResult.success(primaryStreamInfo.url, cleanId);
        } else {
          _log('Primary videoId "$cleanId" is a music video ("${primaryStreamInfo.title}" by "${primaryStreamInfo.author}"). Searching for studio "- Topic" audio candidate...');
        }
      } else {
        _log('Primary videoId "$cleanId" failed direct extraction. Proceeding to candidate search...');
      }
    } else {
      _log('Primary videoId is invalid, synthetic, or excluded: "$cleanId". Proceeding to candidate search...');
    }

    return resolveAlternativeStream(
      title: title,
      artist: artist,
      failedVideoId: isRealId ? cleanId : null,
      excludedVideoIds: excludedVideoIds,
      fallbackResult: (primaryStreamInfo != null && primaryStreamInfo.url.isNotEmpty)
          ? StreamResolutionResult.success(primaryStreamInfo.url, cleanId)
          : null,
    );
  }

  /// Searches for alternative YouTube videos for a track, excluding already attempted IDs
  Future<StreamResolutionResult> resolveAlternativeStream({
    required String title,
    required String artist,
    String? failedVideoId,
    Set<String>? excludedVideoIds,
    StreamResolutionResult? fallbackResult,
  }) async {
    final searchQueries = buildSearchQueries(title, artist);

    final attemptedIds = <String>{};
    if (failedVideoId != null && failedVideoId.isNotEmpty) {
      attemptedIds.add(failedVideoId);
    }
    if (excludedVideoIds != null) {
      attemptedIds.addAll(excludedVideoIds);
    }

    _log('Candidate fallback search started for "$title" by "$artist". Attempted IDs so far: $attemptedIds');

    for (final query in searchQueries) {
      try {
        _log('Running Innertube search query: "$query"...');
        final candidateIds = await searchCandidateVideoIds(query);
        _log('Query "$query" returned ${candidateIds.length} candidate IDs');

        for (final candId in candidateIds.take(5)) {
          if (attemptedIds.contains(candId)) {
            continue;
          }
          attemptedIds.add(candId);
          _log('Evaluating candidate [$candId]...');

          if (kIsWeb) {
            _log('Web platform: routing candidate [$candId] via Cloudflare Worker YouTube IFrame Bridge.');
            return StreamResolutionResult.success('yt-iframe://$candId', candId);
          }

          final candInfo = await getStreamInfo(candId);
          if (candInfo != null && candInfo.url.isNotEmpty) {
            // Strictly prefer non-video / topic audio candidates
            if (!candInfo.isVideo) {
              _log('SUCCESS: Candidate [$candId] yielded studio/topic audio ("${candInfo.title}")!');
              return StreamResolutionResult.success(candInfo.url, candId);
            } else {
              _log('Candidate [$candId] is a video ("${candInfo.title}"). Continuing search for studio track...');
              fallbackResult ??= StreamResolutionResult.success(candInfo.url, candId);
            }
          } else {
            _log('Candidate [$candId] failed stream extraction');
          }
        }
      } catch (e) {
        _log('Search query "$query" failed with error: $e');
      }
    }

    if (fallbackResult != null) {
      _log('Using fallback music video stream for "$title" because no studio "- Topic" candidate was found.');
      return fallbackResult;
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
