import 'dart:convert';
import 'package:http/http.dart' as http;
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
      final res = await http.post(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent': userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'platform=kuwo&keyword=${Uri.encodeComponent(clean)}&page=1&size=$size',
      );

      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      if (data['code'] != 0) return [];

      final List list = data['data']?['list'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
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

      final res = await http.post(
        Uri.parse(getUrlEndpoint),
        headers: {
          'User-Agent': userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data['code'] == 0 && data['data']?['url'] != null) {
        return data['data']['url'] as String;
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

      final name = c['name']?.toString() ?? 'Unknown';
      final artist = c['artist']?.toString() ?? 'Unknown Artist';
      final albumName = c['album_name']?.toString() ?? '';
      final picUrl = c['pic_url']?.toString() ?? '';
      final dur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;
      final time = c['time'];
      final sign = c['sign']?.toString() ?? '';

      // Check for FLAC in minfo
      final List? minfos = c['minfo'] as List?;
      String bitrate = '2000';
      if (minfos != null) {
        final flacs = minfos
            .where((m) => m['format']?.toString().toLowerCase() == 'flac');
        if (flacs.isNotEmpty) {
          bitrate = flacs.first['bitrate']?.toString() ?? '2000';
        }
      }

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
          'bitrate': bitrate,
        },
      ));
    }

    return tracks;
  }
}
