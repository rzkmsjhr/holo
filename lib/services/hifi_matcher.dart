import '../models/track.dart';
import 'kuwo_service.dart';
import 'monochrome_service.dart';

class HifiMatcher {
  final KuwoService _kuwoService = KuwoService();
  final MonochromeService _monochromeService = MonochromeService();

  static final RegExp _bracketNoise = RegExp(
    r'[\(\[\{【『「〔《〈<][^)\]}】』」〕》〉>]*?(?:official|music\s*video|audio|video|lyrics?|hd|hq|4k|mv|m/v|pv|visualizer|feat\.?|ft\.?|remaster(?:ed)?|live|remix|version|studio)[^)\]}】』」〕》〉>]*?[\)\]\}】』」〕》〉>]',
    caseSensitive: false,
  );

  static final RegExp _trailingMeta = RegExp(
    r'\s*[-|~/:]\s*(?:studio|version|official|music\s*video|lyric\s*video|audio|video|lyrics?|visualizer|remaster(?:ed)?|live|remix|acoustic|instrumental).*$',
    caseSensitive: false,
  );

  String cleanTitle(String title) {
    var cleaned = title.replaceAll(_bracketNoise, ' ');
    cleaned = cleaned.replaceAll(_trailingMeta, ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }

  /// Attempts to elevate a YouTube track to Lossless FLAC
  /// Priority:
  /// 1. Kuwo (Top Priority for Lossless FLAC)
  /// 2. Monochrome (Secondary fallback)
  /// 3. Returns null if neither can serve Hi-Fi (falls back to YouTube)
  Future<Track?> matchToHifi(Track youtubeTrack) async {
    final cleaned = cleanTitle(youtubeTrack.title);
    final targetArtist = youtubeTrack.artist.toLowerCase();
    final targetSecs = youtubeTrack.durationSeconds;

    // 1. Top Priority: Kuwo FLAC
    try {
      final kuwoCandidates = await _kuwoService.searchCandidates(
        '$cleaned ${youtubeTrack.artist}',
        size: 10,
      );

      for (final c in kuwoCandidates) {
        final dur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;
        final cArtist = c['artist']?.toString() ?? '';
        final cName = c['name']?.toString() ?? '';

        if (_isDurationMatch(dur, targetSecs)) {
          if (_isArtistFuzzyMatch(cArtist, targetArtist) ||
              _isTitleFuzzyMatch(cName, cleaned)) {
            final songId = c['id']?.toString() ?? '';
            final time = c['time'];
            final sign = c['sign']?.toString() ?? '';

            final flacUrl = await _kuwoService.getFlacStreamUrl(
              songId: songId,
              time: time,
              sign: sign,
              bitrate: '2000',
            );

            if (flacUrl != null && flacUrl.isNotEmpty) {
              return youtubeTrack.copyWith(
                flacStreamUrl: flacUrl,
                audioSource: 'kuwo',
                isLossless: true,
                audioFormat: '16-bit • 44.1kHz',
              );
            }
          }
        }
      }
    } catch (_) {}

    // 2. Secondary Fallback: Monochrome FLAC
    try {
      final monoCandidates = await _monochromeService.searchTracks(
        '$cleaned ${youtubeTrack.artist}',
        limit: 10,
      );

      for (final candidate in monoCandidates) {
        if (_isDurationMatch(candidate.durationSeconds, targetSecs)) {
          if (_isArtistFuzzyMatch(candidate.artist, targetArtist) ||
              _isTitleFuzzyMatch(candidate.title, cleaned)) {
            return youtubeTrack.copyWith(
              flacStreamUrl: candidate.flacStreamUrl,
              audioSource: 'monochrome',
              isLossless: true,
              audioFormat: '24-bit • 96kHz',
            );
          }
        }
      }
    } catch (_) {}

    // 3. Fallback: Neither Kuwo nor Monochrome can serve Hi-Fi
    return null;
  }

  bool _isDurationMatch(int candidateSecs, int targetSecs) {
    if (targetSecs <= 0 || candidateSecs <= 0) return true;
    final diff = (candidateSecs - targetSecs).abs();
    return diff <= 5; // 5-second tolerance
  }

  bool _isArtistFuzzyMatch(String candidateArtist, String targetArtist) {
    final c = candidateArtist.toLowerCase().trim();
    final t = targetArtist.toLowerCase().trim();
    if (c.isEmpty || t.isEmpty) return false;
    if (c.contains(t) || t.contains(c)) return true;

    final separators = RegExp(r'[\s,&/、・+]+');
    final tParts = t.split(separators).where((p) => p.isNotEmpty).toList();
    for (final part in tParts) {
      if (part.length >= 2 && c.contains(part)) return true;
    }

    return false;
  }

  bool _isTitleFuzzyMatch(String candidateTitle, String targetTitle) {
    final c = cleanTitle(candidateTitle).toLowerCase();
    final t = cleanTitle(targetTitle).toLowerCase();
    return c.contains(t) || t.contains(c);
  }
}
