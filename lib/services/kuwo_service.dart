import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../core/network/holo_http_client.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import 'flac_cache_service.dart';

class KuwoService {
  static const String searchUrl = 'https://flac.music.hi.cn/ajax.php?act=search';
  static const String getUrlEndpoint =
      'https://flac.music.hi.cn/ajax.php?act=getUrl';

  static const List<String> _userAgentPool = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15',
  ];

  static const List<int> _publicOctets = [
    14, 27, 36, 39, 42, 43, 45, 49, 58, 59, 60, 61, 101, 103, 106, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 139,
    140, 144, 150, 153, 163, 171, 175, 180, 182, 183, 202, 203, 210, 211, 218,
    219, 220, 221, 222, 223,
  ];

  static int _reqCounter = 1;

  static int _nextEphemeralSeed() {
    final nanos = DateTime.now().microsecondsSinceEpoch;
    final count = _reqCounter++;
    return (nanos ^ (count * 0x9E3779B9)) & 0x7FFFFFFF;
  }

  static String _generateEphemeralIp(int seed) {
    final a = _publicOctets[seed % _publicOctets.length];
    final b = (seed >> 8) & 0xFF;
    final c = (seed >> 16) & 0xFF;
    final d = ((seed >> 24) % 253) + 1;
    return '$a.$b.$c.$d';
  }

  static Map<String, String> _buildEphemeralHeaders({String accept = '*/*'}) {
    final seed = _nextEphemeralSeed();
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      'Accept': accept,
    };
    if (!kIsWeb) {
      final ip = _generateEphemeralIp(seed);
      final ua = _userAgentPool[seed % _userAgentPool.length];
      headers['User-Agent'] = ua;
      headers['Referer'] = 'https://flac.music.hi.cn/';
      headers['Origin'] = 'https://flac.music.hi.cn';
      headers['X-Forwarded-For'] = ip;
      headers['X-Real-IP'] = ip;
      headers['Client-IP'] = ip;
      headers['True-Client-IP'] = ip;
    }
    return headers;
  }

  static Future<http.Response> _postEphemeral(
    String endpoint,
    String body, {
    String accept = '*/*',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final headers = _buildEphemeralHeaders(accept: accept);
    if (kIsWeb) {
      return HoloHttpClient.client
          .post(Uri.parse(endpoint), headers: headers, body: body)
          .timeout(timeout);
    }

    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 1)
      ..maxConnectionsPerHost = 1;
    final client = IOClient(inner);
    try {
      return await client
          .post(Uri.parse(endpoint), headers: headers, body: body)
          .timeout(timeout);
    } finally {
      client.close();
    }
  }

  /// Validates that a flac.music.hi.cn CDN URL points to a lossless FLAC track
  /// rather than a lossy `.mp3`/`.aac`/`.m4a`/`.ogg` or `/lx/resource/` spoken copyright stub (`2044590383.mp3`).
  static bool isValidHiCnFlacUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    final path = lower.split('?').first;
    if (path.endsWith('.mp3') ||
        path.endsWith('.aac') ||
        path.endsWith('.m4a') ||
        path.endsWith('.ogg')) {
      return false;
    }
    if (lower.contains('/lx/resource/') || lower.contains('2044590383')) {
      return false;
    }
    return true;
  }

  static int? _parseInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim());
    return null;
  }

  /// Performs a fast Range preflight on direct hi.cn CDN URLs to reject HTTP 403/410,
  /// `audio/mpeg` copyright notices, undersized responses (< 250 KB), or non-FLAC headers.
  Future<bool> _verifyStreamHeadersAndMagic(String directUrl) async {
    if (kIsWeb) return true;
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 1);
    final client = IOClient(inner);
    try {
      final req = http.Request('GET', Uri.parse(directUrl));
      req.headers['User-Agent'] =
          _userAgentPool[_nextEphemeralSeed() % _userAgentPool.length];
      req.headers['Range'] = 'bytes=0-16383';

      final res = await client.send(req).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200 && res.statusCode != 206) {
        return false;
      }

      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('audio/mpeg') || ct.contains('text/html')) {
        return false;
      }

      // Check full resource size via Content-Range ("bytes 0-16383/TOTAL") or Content-Length
      final cr = res.headers['content-range'];
      int? totalBytes;
      if (cr != null && cr.contains('/')) {
        final totalPart = cr.split('/').last.trim();
        totalBytes = int.tryParse(totalPart);
      } else if (res.statusCode == 200) {
        totalBytes = res.contentLength;
      }
      if (totalBytes != null &&
          totalBytes > 0 &&
          totalBytes < FlacCacheService.minValidFlacBytes) {
        return false;
      }

      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(const Duration(seconds: 4))) {
        bytes.addAll(chunk);
        if (bytes.length >= 16384) break;
      }
      if (bytes.length >= 4 && !FlacCacheService.hasFlacMagicPrefix(bytes)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Searches flac.music.hi.cn catalog (`platform`: `'kuwo'` or `'wyy'`) with ephemeral isolation & retries.
  /// Throws an exception if all retry attempts fail so callers never cache transient outages as unmatched.
  Future<List<Map<String, dynamic>>> searchCandidates(
    String query, {
    int size = 15,
    String platform = 'kuwo',
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final body =
        'platform=${Uri.encodeQueryComponent(platform)}&keyword=${Uri.encodeQueryComponent(clean)}&page=1&size=$size';

    const maxAttempts = 3;
    Object? lastErr;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }

      try {
        final res = await _postEphemeral(
          searchUrl,
          body,
          accept: 'application/json, text/plain, */*',
          timeout: const Duration(seconds: 10),
        );

        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastErr = 'HTTP ${res.statusCode} from $platform search';
          if (res.statusCode == 429 || res.statusCode >= 500) {
            continue;
          }
          throw Exception(lastErr);
        }

        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        if (data['code'] != 0) {
          lastErr = '$platform search code=${data['code']}: ${data['msg'] ?? ''}';
          continue;
        }

        final List list = data['data']?['list'] ?? [];
        return list.cast<Map<String, dynamic>>();
      } catch (e) {
        lastErr = e;
      }
    }

    throw Exception(lastErr ?? 'Network error querying $platform search');
  }

  /// Extracts the highest-bitrate lossless FLAC option from a candidate's `minfo` list.
  /// Prioritizes Hi-Res master streams (`zg`/`hir` or >= 4000) over standard SQ FLAC.
  String? extractFlacBitrate(Map<String, dynamic> candidate) {
    final minfos = candidate['minfo'];
    if (minfos is! List) return null;

    int bestWeight = 0;
    String? bestBitrateStr;

    for (final m in minfos) {
      if (m is Map) {
        final fmt = m['format']?.toString().trim().toLowerCase() ?? '';
        if (fmt == 'flac') {
          final brStr = m['bitrate']?.toString().trim() ?? '2000';
          final brVal = int.tryParse(brStr) ?? 2000;
          final level = m['level']?.toString().trim().toLowerCase() ?? '';

          var weight = brVal;
          if (level == 'zg' || level == 'hir' || brVal >= 4000) {
            weight = brVal > 4000 ? brVal : 4000;
          }

          if (weight >= bestWeight) {
            bestWeight = weight;
            bestBitrateStr = brStr.isNotEmpty && brStr != '0'
                ? brStr
                : (weight >= 4000 ? '4000' : '2000');
          }
        }
      }
    }

    return bestBitrateStr;
  }

  /// Checks if candidate offers a 24-bit Hi-Res master FLAC stream.
  bool isHiResFlac(Map<String, dynamic> candidate) {
    final minfos = candidate['minfo'];
    if (minfos is! List) return false;

    for (final m in minfos) {
      if (m is Map) {
        final fmt = m['format']?.toString().trim().toLowerCase() ?? '';
        if (fmt == 'flac') {
          final level = m['level']?.toString().trim().toLowerCase() ?? '';
          final brVal = int.tryParse(m['bitrate']?.toString().trim() ?? '0') ?? 0;
          if (level == 'zg' || level == 'hir' || brVal >= 4000) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Resolves and verifies a direct lossless FLAC CDN URL (`platform`: `'kuwo'` or `'wyy'`).
  /// Retries with fresh ephemeral identity if throttled or substituted with a demo clip.
  Future<String?> getFlacStreamUrl({
    required String songId,
    required dynamic time,
    required String sign,
    String bitrate = '2000',
    String platform = 'kuwo',
    int expectedDurSecs = 0,
  }) async {
    final timeStr = time?.toString() ?? '';
    final body =
        'platform=${Uri.encodeQueryComponent(platform)}&songid=${Uri.encodeComponent(songId)}&format=flac&bitrate=${Uri.encodeComponent(bitrate)}&time=${Uri.encodeComponent(timeStr)}&sign=${Uri.encodeComponent(sign)}';

    const maxAttempts = 3;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        final jitter = _nextEphemeralSeed() % 150;
        await Future.delayed(Duration(milliseconds: 400 * attempt + jitter));
      }

      try {
        final res = await _postEphemeral(
          getUrlEndpoint,
          body,
          timeout: const Duration(seconds: 10),
        );

        if (res.statusCode < 200 || res.statusCode >= 300) {
          if (res.statusCode == 429 || res.statusCode >= 500) {
            continue;
          }
          return null;
        }

        final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
        final data = jsonDecode(decoded);
        final code = _parseInt(data['code']);
        if (code != 0) {
          if (code == -3) return null;
          continue;
        }

        final payload = data['data'];
        if (payload is! Map) continue;

        final url = payload['url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;

        final retFmt = payload['format']?.toString().trim().toLowerCase() ?? '';
        final retBr = _parseInt(payload['bitrate']);
        final retDur = _parseInt(payload['duration']);

        final durMismatch = expectedDurSecs > 30 &&
            retDur != null &&
            retDur > 0 &&
            (retDur < expectedDurSecs ~/ 2 || (expectedDurSecs - retDur).abs() > 20);

        final isThrottledSubstitute = durMismatch ||
            (retBr != null && retBr <= 1) ||
            url.toLowerCase().contains('/lx/resource/');

        if (isThrottledSubstitute) {
          continue;
        }

        final isLossyDowngrade = (retFmt.isNotEmpty && retFmt != 'flac') ||
            (retBr != null && retBr > 0 && retBr < 500) ||
            !isValidHiCnFlacUrl(url);

        if (isLossyDowngrade) {
          return null;
        }

        final isPlayableFlac = await _verifyStreamHeadersAndMagic(url);
        if (!isPlayableFlac) {
          return null;
        }

        return url;
      } catch (_) {}
    }

    return null;
  }

  /// Searches Kuwo and extracts playable FLAC tracks.
  Future<List<Track>> searchTracks(String query) async {
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await searchCandidates(query);
    } catch (_) {
      return [];
    }

    final List<Track> tracks = [];
    for (final c in candidates) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final flacBitrate = extractFlacBitrate(c);
      if (flacBitrate == null) continue;

      final name = c['name']?.toString() ?? 'Unknown';
      final artist = c['artist']?.toString() ?? 'Unknown Artist';
      final albumName = c['album_name']?.toString() ?? '';
      final picUrl = c['pic_url']?.toString() ?? '';
      final dur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;
      final time = c['time'];
      final sign = c['sign']?.toString() ?? '';

      final isHiRes = isHiResFlac(c);
      tracks.add(Track(
        id: 'kuwo_$id',
        title: name,
        artist: artist,
        album: albumName,
        thumbnailUrl: picUrl,
        durationSeconds: dur,
        flacStreamUrl: null, // Resolved on-demand when user clicks
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: isHiRes
            ? '24-bit • 96kHz Lossless FLAC'
            : '16-bit • 44.1kHz Lossless FLAC',
        extraData: {
          'platform': 'kuwo',
          'songid': id,
          'time': time,
          'sign': sign,
          'bitrate': flacBitrate,
          'isHiRes': isHiRes,
        },
      ));
    }

    return tracks;
  }
}
