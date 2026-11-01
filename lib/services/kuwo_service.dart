import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';

class KuwoService {
  static const String searchUrl = 'https://flac.music.hi.cn/ajax.php?act=search';
  static const String getUrlEndpoint =
      'https://flac.music.hi.cn/ajax.php?act=getUrl';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  /// Searches Kuwo catalog for candidate tracks
  Future<List<Map<String, dynamic>>> searchCandidates(String query,
      {int size = 15}) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      final res = await http
          .post(
            Uri.parse(searchUrl),
            headers: {
              'User-Agent': userAgent,
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
              'Accept': 'application/json, text/plain, */*',
            },
            body:
                'platform=kuwo&keyword=${Uri.encodeQueryComponent(clean)}&page=1&size=$size',
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return [];

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      if (data['code'] != 0) return [];

      final List list = data['data']?['list'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Extracts the highest-bitrate FLAC option from a Kuwo candidate's minfo list.
  /// Returns null if the candidate does not offer a lossless FLAC stream.
  String? extractFlacBitrate(Map<String, dynamic> candidate) {
    final minfos = candidate['minfo'];
    if (minfos is! List) return null;

    int bestBitrate = 0;
    String? bestBitrateStr;

    for (final m in minfos) {
      if (m is Map) {
        final fmt = m['format']?.toString().trim().toLowerCase() ?? '';
        if (fmt == 'flac') {
          final brStr = m['bitrate']?.toString().trim() ?? '2000';
          final brVal = int.tryParse(brStr) ?? 2000;
          if (brVal >= bestBitrate) {
            bestBitrate = brVal;
            bestBitrateStr = brStr;
          }
        }
      }
    }

    return bestBitrateStr;
  }

  /// Resolves the direct FLAC CDN stream URL from Kuwo
  Future<String?> getFlacStreamUrl({
    required String songId,
    required dynamic time,
    required String sign,
    String bitrate = '2000',
  }) async {
    try {
      final timeStr = time?.toString() ?? '';
      final body =
          'platform=kuwo&songid=${Uri.encodeComponent(songId)}&format=flac&bitrate=${Uri.encodeComponent(bitrate)}&time=${Uri.encodeComponent(timeStr)}&sign=${Uri.encodeComponent(sign)}';

      final res = await http
          .post(
            Uri.parse(getUrlEndpoint),
            headers: {
              'User-Agent': userAgent,
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return null;

      final decoded = TextEncodingUtils.decodeHttpBytes(res.bodyBytes);
      final data = jsonDecode(decoded);
      if (data['code'] == 0 && data['data']?['url'] != null) {
        final url = data['data']['url'].toString().trim();
        final respFormat =
            data['data']?['format']?.toString().trim().toLowerCase();
        if (url.isEmpty) return null;
        if (respFormat != null &&
            respFormat.isNotEmpty &&
            respFormat != 'flac') {
          return null;
        }
        if (!url.toLowerCase().contains('.flac') && respFormat != 'flac') {
          return null;
        }
        return url;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Searches Kuwo and automatically extracts playable FLAC tracks
  Future<List<Track>> searchTracks(String query) async {
    final candidates = await searchCandidates(query);
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

      tracks.add(Track(
        id: 'kuwo_$id',
        title: name,
        artist: artist,
        album: albumName,
        thumbnailUrl: picUrl.isNotEmpty
            ? picUrl
            : 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500',
        durationSeconds: dur,
        flacStreamUrl: null, // Resolved on-demand when user clicks
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz',
        extraData: {
          'songid': id,
          'time': time,
          'sign': sign,
          'bitrate': flacBitrate,
        },
      ));
    }

    return tracks;
  }
}
