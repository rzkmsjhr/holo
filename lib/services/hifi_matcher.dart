import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import 'flac_cache_service.dart';
import 'kuwo_service.dart';
import 'monochrome_service.dart';

class VersionFlags {
  final bool isAcoustic;
  final bool isLive;
  final bool isRemix;
  final bool isInstrumental;
  final bool isPiano;
  final bool isOrchestral;

  const VersionFlags({
    required this.isAcoustic,
    required this.isLive,
    required this.isRemix,
    required this.isInstrumental,
    required this.isPiano,
    required this.isOrchestral,
  });

  static VersionFlags extract(String title) {
    final s = title.toLowerCase();
    return VersionFlags(
      isAcoustic: s.contains('acoustic'),
      isLive: s.contains('live'),
      isRemix: s.contains('remix') || s.contains('mix'),
      isInstrumental: s.contains('instrumental') || s.contains('karaoke'),
      isPiano: s.contains('piano'),
      isOrchestral: s.contains('orchestral'),
    );
  }

  static bool hasConflict(VersionFlags a, VersionFlags b) {
    return a.isAcoustic != b.isAcoustic ||
        a.isLive != b.isLive ||
        a.isRemix != b.isRemix ||
        a.isInstrumental != b.isInstrumental ||
        a.isPiano != b.isPiano ||
        a.isOrchestral != b.isOrchestral;
  }
}

class _HifiMatchCandidate {
  final String provider; // 'kuwo' or 'monochrome'
  final int score;
  final Map<String, dynamic>? kuwoRaw;
  final String? kuwoBitrate;
  final bool isHiRes;
  final Track? monoTrack;

  _HifiMatchCandidate({
    required this.provider,
    required this.score,
    this.kuwoRaw,
    this.kuwoBitrate,
    required this.isHiRes,
    this.monoTrack,
  });
}

class HifiMatcher {
  final KuwoService _kuwoService = KuwoService();
  final MonochromeService _monochromeService = MonochromeService();

  /// Current matcher version. Incrementing forces stale persisted tracks to be re-evaluated.
  static const int matcherVersion = 9;

  static const String _storageKey = 'holo_hifi_cache_v2';
  bool _isInitialized = false;

  // In-memory cache for fast resolution
  static final Map<String, Track> _resolutionCache = {};
  static final Set<String> _unmatchedCache = {};

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved != null && saved.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(saved);
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            final t = Track.fromJson(val);
            if (t.isLossless && t.flacStreamUrl != null && t.flacStreamUrl!.isNotEmpty) {
              _resolutionCache[key] = t;
            }
          }
        });
      }
    } catch (_) {}
    _isInitialized = true;
  }

  void _persistResolution(String key, Track track) {
    _resolutionCache[key] = track;
    SharedPreferences.getInstance().then((prefs) {
      final Map<String, dynamic> cacheMap = {};
      _resolutionCache.forEach((k, v) {
        cacheMap[k] = v.toJson();
      });
      prefs.setString(_storageKey, jsonEncode(cacheMap));
    }).catchError((_) {});
  }

  /// Synchronously checks if a track has a cached or downloaded Hi-Fi FLAC stream.
  Track? getCachedHiFi(Track track) {
    final trackIdKey = track.youtubeVideoId ?? track.id;
    if (_resolutionCache.containsKey(trackIdKey)) {
      return _resolutionCache[trackIdKey];
    }
    final textKey =
        '${track.artist.toLowerCase()}:::${track.title.toLowerCase()}';
    if (_resolutionCache.containsKey(textKey)) {
      return _resolutionCache[textKey];
    }
    final localPath = FlacCacheService().getCachedFilePath(trackIdKey) ??
        FlacCacheService().getCachedFilePath(textKey);
    if (localPath != null) {
      return track.copyWith(
        flacStreamUrl: localPath,
        audioSource: 'flac_cache',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC (Cached)',
        extraData: {
          ...?track.extraData,
          'hifiVersion': matcherVersion,
          'isLocalCache': true,
        },
      );
    }
    return null;
  }

  static const Set<String> knownUpstreamMismatches = {
    '168395054749057024', // Dewa 19 - Aku Milikmu (2021 Virzha single instead of 1994 Ari Lasso master)
    '168589766881927168', // Dewa 19 feat. Virzha - Aku Milikmu (2021 Virzha remake)
    '168395069831774208', // Dewa 19 - Tak Kan Ada Cinta Yang Lain (2021 Ello remake)
    '168395062953115648', // Dewa 19 - Mahameru (2021 Virzha remake)
  };

  static const List<String> videoKeywords = [
    'dance practice',
    'live at',
    'live in',
    'live from',
    'live concert',
    'full concert',
    'trailer',
    'teaser',
  ];

  static const List<String> derivativeKeywords = [
    'karaoke',
    'カラオケ',
    'off vocal',
    'offvocal',
    'without vocal',
    'no vocal',
    'backing track',
    'minus one',
    'guitar cover',
    'drum cover',
    'piano cover',
    'vocal cover',
    'bass cover',
    'play along',
    'tutorial',
    'how to play',
    'mashup',
    'slowed',
    'reverb',
    'sped up',
    'nightcore',
    'koplo',
    'jedag jedug',
    'funkot',
    'originally performed by',
    'original performer',
    'megamix',
  ];

  static final RegExp _featRegex =
      RegExp(r'\b(feat|featuring|ft)\.?\s+.*$', caseSensitive: false);
  static final RegExp _bracketsRegex =
      RegExp(r'[\(\[\{【〔〈《「『].*?[\)\]\}】〕〉》」』]');
  static final RegExp _nonAlphaNumRegex =
      RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true);
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _artistSplitRegex = RegExp(
    r'[,&/;|]|(?:\s+(?:feat\.?|ft\.?|featuring|with|x|and)\s+)',
    caseSensitive: false,
  );
  static final RegExp _youtubeNoiseRegex = RegExp(
    r'\b(official\s*(?:music\s*)?video|official\s*audio|official\s*visualizer|lyrics?\s*(?:video)?|music\s*video|audio|visualizer|hd|hq|4k|1080p|720p|topic|clip\s*officiel|video\s*oficial|mv)\b',
    caseSensitive: false,
  );

  /// Checks if a YouTube track is eligible for Hi-Fi elevation.
  /// Rejects live concerts, dance practices, covers, and derivatives.
  static bool isEligibleTrack(Track track) {
    final itemType = (track.extraData?['itemType']?.toString() ?? '').toLowerCase().trim();
    if (itemType == 'video') return false;

    final channel = track.artist.toLowerCase().trim();
    if (channel.contains('vevo')) return false;

    final title = track.title.toLowerCase().trim();
    if (videoKeywords.any((k) => title.contains(k))) return false;
    if (derivativeKeywords.any((k) => title.contains(k))) return false;

    return true;
  }

  /// Normalizes a string for robust cross-language fuzzy title/artist matching.
  static String cleanString(String str) {
    var lower = str.toLowerCase();
    lower = lower.replaceAll(_featRegex, '');
    lower = lower.replaceAll(_bracketsRegex, '');
    lower = TextEncodingUtils.cleanMojibake(lower);
    final alnumOnly = lower.replaceAll(_nonAlphaNumRegex, '');
    return alnumOnly.trim();
  }

  static final RegExp _trailingMeta = RegExp(
    r'\s*[-|~/:]\s*(?:studio|version|official|music\s*video|lyric\s*video|audio|video|lyrics?|visualizer|remaster(?:ed)?|live|remix|acoustic|instrumental).*$',
    caseSensitive: false,
  );
  static final RegExp _trailingSeparators = RegExp(r'\s*[-|~/:–]+\s*$');

  /// Strips YouTube video tags for query building.
  String cleanTitle(String title) {
    var lower = title.replaceAll(_trailingMeta, ' ');
    lower = lower.replaceAll(_youtubeNoiseRegex, ' ');
    lower = lower.replaceAll(_bracketsRegex, ' ');
    lower = lower.replaceAll(_trailingSeparators, ' ');
    lower = lower.replaceAll(_multiSpaceRegex, ' ').trim();
    return lower.isNotEmpty ? lower : title;
  }

  static String _normalizeArtistToken(String s) {
    var lower = s.toLowerCase();
    lower = lower.replaceAll('- topic', '').replaceAll('topic', '');
    lower = lower.replaceAll('vevo', '');
    lower = lower.replaceAll(_nonAlphaNumRegex, ' ');
    lower = lower.replaceAll(_multiSpaceRegex, ' ');
    return lower.trim();
  }

  static List<String> splitArtistList(String s) {
    if (s.trim().isEmpty) return [];
    final parts = s
        .split(_artistSplitRegex)
        .map(_normalizeArtistToken)
        .where((t) => t.isNotEmpty)
        .toList();

    final full = _normalizeArtistToken(s);
    if (full.isNotEmpty && !parts.contains(full)) {
      parts.add(full);
    }
    return parts;
  }

  static const Map<String, List<String>> _artistAliases = {
    'mariya takeuchi': ['竹内まりや'],
    '竹内まりや': ['mariya takeuchi'],
    'iu': ['아이유'],
    '아이유': ['iu'],
    'amr diab': ['عمرو دياب'],
    'عمرو دياب': ['amr diab'],
    'nont tanont': ['นนท์ ธนนท์'],
    'นนท์ ธนนท์': ['nont tanont'],
    'tatsuro yamashita': ['山下達郎'],
    '山下達郎': ['tatsuro yamashita'],
    'miki matsubara': ['松原みき'],
    '松原みき': ['miki matsubara'],
    'taeko onuki': ['大貫妙子'],
    '大貫妙子': ['taeko onuki'],
  };

  static const Map<String, List<String>> _titleAliases = {
    'single again': ['シングルアゲイン', 'シングル・アゲイン'],
    'plastic love': ['プラスティックラブ', 'プラスティック・ラヴ', 'プラスティック・ラブ'],
    'stay with me': ['真夜中のドア', '真夜中のドア stay with me'],
    'through the night': ['밤편지'],
    'tamally maak': ['تملي معاك'],
    'nour el ain': ['نور العين'],
    'phing': ['พิง'],
  };

  static bool doesArtistMatch(
    String targetArtist,
    String candidateArtist,
    String targetTitle,
  ) {
    final targetList = splitArtistList(targetArtist);
    final candList = splitArtistList(candidateArtist);

    final cleanTargetArtist = cleanString(targetArtist);
    final cleanCandArtist = cleanString(candidateArtist);

    // Cross-script alias check
    for (final entry in _artistAliases.entries) {
      final keyClean = cleanString(entry.key);
      if (cleanTargetArtist == keyClean) {
        if (entry.value.any((a) =>
            cleanString(a) == cleanCandArtist ||
            candList.any((c) => cleanString(c) == cleanString(a)))) {
          return true;
        }
      }
      if (cleanCandArtist == keyClean) {
        if (entry.value.any((a) =>
            cleanString(a) == cleanTargetArtist ||
            targetList.any((t) => cleanString(t) == cleanString(a)))) {
          return true;
        }
      }
    }

    // Check if target title contains candidate artist or candidate aliases
    final lowerTitle = targetTitle.toLowerCase();
    for (final entry in _artistAliases.entries) {
      if (cleanCandArtist == cleanString(entry.key)) {
        for (final a in entry.value) {
          if (lowerTitle.contains(a.toLowerCase())) return true;
        }
      }
    }
    for (final c in candList) {
      if (c.isNotEmpty && c.length >= 3 && lowerTitle.contains(c.toLowerCase())) {
        return true;
      }
    }

    if (targetList.isEmpty || candList.isEmpty) return false;

    bool hasPrimaryMatch = false;
    for (final t in targetList) {
      final tCompact = t.replaceAll(' ', '');
      final tNoThe = t.startsWith('the ') ? t.substring(4).trim() : t;

      for (final c in candList) {
        if (t == c) {
          hasPrimaryMatch = true;
          break;
        }
        final cCompact = c.replaceAll(' ', '');
        if (tCompact.length >= 2 && tCompact == cCompact) {
          hasPrimaryMatch = true;
          break;
        }
        final cNoThe = c.startsWith('the ') ? c.substring(4).trim() : c;
        if (tNoThe.length >= 3 && tNoThe == cNoThe) {
          hasPrimaryMatch = true;
          break;
        }
      }
      if (hasPrimaryMatch) break;
    }

    if (!hasPrimaryMatch) return false;

    // Reject unwanted feat. in candidate if target did not request it
    final lowerTarget = '$targetArtist $targetTitle'.toLowerCase();
    final lowerCand = candidateArtist.toLowerCase();
    if ((lowerCand.contains('feat') || lowerCand.contains('ft.')) &&
        !lowerTarget.contains('feat') &&
        !lowerTarget.contains('ft.')) {
      return false;
    }

    return true;
  }

  static bool isKnownUpstreamMismatch(String id, String title, String artist) {
    if (knownUpstreamMismatches.contains(id)) {
      final t = title.toLowerCase();
      if (!t.contains('virzha') &&
          !t.contains('ello') &&
          !t.contains('2021') &&
          !t.contains('remake')) {
        return true;
      }
    }

    final t = title.toLowerCase();
    if (t.contains('virzha') ||
        t.contains('ello') ||
        t.contains('2021') ||
        t.contains('remake')) {
      return true;
    }

    return false;
  }

  /// Scores a candidate track against target metadata using artist, title, duration, and album.
  /// Returns a confidence score from 0 to 300. Minimum qualifying score is 80.
  static int scoreTrackCandidate({
    required String targetTitle,
    required String targetArtist,
    required int targetDurSecs,
    required String candId,
    required String candTitle,
    required String candArtist,
    required int candDurSecs,
    String? targetAlbum,
    String? candAlbum,
  }) {
    // 0. Upstream mismatch blacklist
    if (isKnownUpstreamMismatch(candId, candTitle, candArtist)) {
      return 0;
    }

    // 1. Version conflict check (acoustic, live, remix, instrumental)
    final targetFlags = VersionFlags.extract(targetTitle);
    final candFlags = VersionFlags.extract(candTitle);
    if (VersionFlags.hasConflict(targetFlags, candFlags)) {
      return 0;
    }

    // 1b. Reject unwanted feature/remake in candidate title
    final lowerTarget = '$targetArtist $targetTitle'.toLowerCase();
    final lowerCandTitle = candTitle.toLowerCase();
    if ((lowerCandTitle.contains('feat.') ||
            lowerCandTitle.contains('feat ') ||
            lowerCandTitle.contains('ft.') ||
            lowerCandTitle.contains('ft ')) &&
        !lowerTarget.contains('feat') &&
        !lowerTarget.contains('ft.') &&
        !lowerTarget.contains('ft ')) {
      return 0;
    }

    // 2. Artist match check (mandatory)
    if (!doesArtistMatch(targetArtist, candArtist, targetTitle)) {
      return 0;
    }

    int score = 50; // Base score for verified artist match

    // 3. Title comparison
    final targetClean = cleanString(targetTitle);
    final candClean = cleanString(candTitle);

    bool titleMatched = false;
    if (targetClean.isNotEmpty && candClean.isNotEmpty) {
      if (targetClean == candClean) {
        score += 100;
        titleMatched = true;
      } else if (targetClean.contains(candClean) || candClean.contains(targetClean)) {
        score += 65;
        titleMatched = true;
      }
    }

    // Title alias check
    if (!titleMatched) {
      for (final entry in _titleAliases.entries) {
        final keyClean = cleanString(entry.key);
        if (targetClean == keyClean) {
          if (entry.value.any((a) =>
              cleanString(a) == candClean ||
              candClean.contains(cleanString(a)) ||
              cleanString(a).contains(candClean))) {
            score += 85;
            titleMatched = true;
            break;
          }
        }
        if (candClean == keyClean) {
          if (entry.value.any((a) =>
              cleanString(a) == targetClean ||
              targetClean.contains(cleanString(a)) ||
              cleanString(a).contains(targetClean))) {
            score += 85;
            titleMatched = true;
            break;
          }
        }
      }
    }

    if (!titleMatched) {
      return 0;
    }

    // 4. Album comparison (bonus points if present and matching)
    if (targetAlbum != null &&
        candAlbum != null &&
        targetAlbum.trim().isNotEmpty &&
        candAlbum.trim().isNotEmpty) {
      final tAlbum = cleanString(targetAlbum);
      final cAlbum = cleanString(candAlbum);
      if (tAlbum.isNotEmpty && cAlbum.isNotEmpty) {
        if (tAlbum == cAlbum) {
          score += 25;
        } else if (tAlbum.contains(cAlbum) || cAlbum.contains(tAlbum)) {
          score += 15;
        }
      }
    }

    // 5. Duration comparison (allowing reasonable video intro/outro variance)
    if (targetDurSecs > 0 && candDurSecs > 0) {
      final diff = (targetDurSecs - candDurSecs).abs();
      final maxAllowedDiff = (targetDurSecs * 0.12).clamp(25.0, 45.0).round();
      if (diff > maxAllowedDiff) {
        return 0;
      }

      if (diff <= 3) {
        score += 40;
      } else if (diff <= 6) {
        score += 25;
      } else if (diff <= 12) {
        score += 10;
      } else if (diff <= 25) {
        score = (score - 5).clamp(0, 300);
      } else {
        score = (score - 20).clamp(0, 300);
      }
    } else if (targetDurSecs > 0 && candDurSecs == 0) {
      score = (score - 10).clamp(0, 300);
    }

    return score;
  }

  /// Refreshes an expired FLAC URL from persistent extraData without re-matching.
  Future<Track?> refreshFlacUrl(Track track) async {
    if (!track.isLossless) return null;
    final source = track.audioSource;
    if (source == 'kuwo' && track.extraData != null) {
      final songId = track.extraData!['songid']?.toString() ?? '';
      final time = track.extraData!['time'];
      final sign = track.extraData!['sign']?.toString() ?? '';
      final bitrate = track.extraData!['bitrate']?.toString() ?? '2000';
      if (songId.isNotEmpty) {
        final newUrl = await _kuwoService.getFlacStreamUrl(
          songId: songId,
          time: time,
          sign: sign,
          bitrate: bitrate,
        );
        if (newUrl != null && newUrl.isNotEmpty) {
          final updated = track.copyWith(flacStreamUrl: newUrl);
          final trackIdKey = track.youtubeVideoId ?? track.id;
          final textKey =
              '${track.artist.toLowerCase()}:::${track.title.toLowerCase()}';
          _persistResolution(trackIdKey, updated);
          _persistResolution(textKey, updated);
          return updated;
        }
      }
    }
    // If not Kuwo or refresh failed, re-run full match
    return matchToHifi(track);
  }

  /// Attempts to elevate an eligible YouTube track to Lossless FLAC across Kuwo & Monochrome in parallel.
  Future<Track?> matchToHifi(Track youtubeTrack) async {
    if (!isEligibleTrack(youtubeTrack)) {
      return null;
    }

    final trackIdKey = youtubeTrack.youtubeVideoId ?? youtubeTrack.id;
    if (_unmatchedCache.contains(trackIdKey)) {
      return null;
    }
    if (_resolutionCache.containsKey(trackIdKey)) {
      return _resolutionCache[trackIdKey];
    }

    final textKey =
        '${youtubeTrack.artist.toLowerCase()}:::${youtubeTrack.title.toLowerCase()}';
    if (_unmatchedCache.contains(textKey)) {
      return null;
    }
    if (_resolutionCache.containsKey(textKey)) {
      return _resolutionCache[textKey];
    }

    // Check local disk cache first
    final flacCache = FlacCacheService();
    final cachedPath = flacCache.getCachedFilePath(trackIdKey) ??
        flacCache.getCachedFilePath(textKey);
    if (cachedPath != null) {
      final elevated = youtubeTrack.copyWith(
        flacStreamUrl: cachedPath,
        audioSource: 'flac_cache',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC (Cached)',
        extraData: {
          ...?youtubeTrack.extraData,
          'hifiVersion': matcherVersion,
          'isLocalCache': true,
        },
      );
      _persistResolution(trackIdKey, elevated);
      _persistResolution(textKey, elevated);
      return elevated;
    }

    final cleanedTitle = cleanTitle(youtubeTrack.title);
    final targetArtist = youtubeTrack.artist.trim();
    final targetDurSecs = youtubeTrack.durationSeconds;
    final targetAlbum = youtubeTrack.album;

    final primaryQuery = '$cleanedTitle $targetArtist'.trim();
    final secondaryQuery = cleanedTitle;

    // Concurrently search Kuwo and Monochrome
    final candidates = <_HifiMatchCandidate>[];

    await Future.wait([
      // 1. Search Kuwo
      (() async {
        for (final q in [primaryQuery, secondaryQuery]) {
          try {
            final list = await _kuwoService.searchCandidates(q, size: 8);
            for (final c in list) {
              final flacBitrate = _kuwoService.extractFlacBitrate(c);
              if (flacBitrate == null) continue;

              final cId = c['id']?.toString() ?? '';
              if (cId.isEmpty) continue;
              final cTitle = c['name']?.toString() ?? '';
              final cArtist = c['artist']?.toString() ?? '';
              final cAlbum = c['album_name']?.toString() ?? '';
              final cDur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;

              final score = scoreTrackCandidate(
                targetTitle: youtubeTrack.title,
                targetArtist: targetArtist,
                targetDurSecs: targetDurSecs,
                targetAlbum: targetAlbum,
                candId: cId,
                candTitle: cTitle,
                candArtist: cArtist,
                candAlbum: cAlbum,
                candDurSecs: cDur,
              );

              if (score >= 80) {
                candidates.add(_HifiMatchCandidate(
                  provider: 'kuwo',
                  score: score,
                  kuwoRaw: c,
                  kuwoBitrate: flacBitrate,
                  isHiRes: _kuwoService.isHiResFlac(c),
                ));
              }
            }
          } catch (_) {}
          if (candidates.any((cand) => cand.provider == 'kuwo' && cand.score >= 120)) {
            break;
          }
        }
      })(),

      // 2. Search Monochrome
      (() async {
        try {
          final list = await _monochromeService.searchTracks(primaryQuery, limit: 10);
          for (final mono in list) {
            final score = scoreTrackCandidate(
              targetTitle: youtubeTrack.title,
              targetArtist: targetArtist,
              targetDurSecs: targetDurSecs,
              targetAlbum: targetAlbum,
              candId: mono.id,
              candTitle: mono.title,
              candArtist: mono.artist,
              candAlbum: mono.album,
              candDurSecs: mono.durationSeconds,
            );

            if (score >= 80) {
              final isHiRes = mono.audioFormat?.contains('24-bit') == true;
              candidates.add(_HifiMatchCandidate(
                provider: 'monochrome',
                score: score,
                isHiRes: isHiRes,
                monoTrack: mono,
              ));
            }
          }
        } catch (_) {}
      })(),
    ]);

    if (candidates.isEmpty) {
      _unmatchedCache.add(trackIdKey);
      _unmatchedCache.add(textKey);
      return null;
    }

    // Sort by score descending (with bonus for Hi-Res)
    candidates.sort((a, b) {
      final aTotal = a.score + (a.isHiRes ? 10 : 0);
      final bTotal = b.score + (b.isHiRes ? 10 : 0);
      return bTotal.compareTo(aTotal);
    });

    // Try candidates in order until a stream resolves
    for (final cand in candidates) {
      if (cand.provider == 'kuwo' && cand.kuwoRaw != null && cand.kuwoBitrate != null) {
        final c = cand.kuwoRaw!;
        final songId = c['id']?.toString() ?? '';
        final time = c['time'];
        final sign = c['sign']?.toString() ?? '';

        final flacUrl = await _kuwoService.getFlacStreamUrl(
          songId: songId,
          time: time,
          sign: sign,
          bitrate: cand.kuwoBitrate!,
        );

        if (flacUrl != null && flacUrl.isNotEmpty) {
          final elevated = youtubeTrack.copyWith(
            flacStreamUrl: flacUrl,
            audioSource: 'kuwo',
            isLossless: true,
            audioFormat: cand.isHiRes
                ? '24-bit • 96kHz Lossless FLAC'
                : '16-bit • 44.1kHz Lossless FLAC',
            extraData: {
              ...?youtubeTrack.extraData,
              'hifiVersion': matcherVersion,
              'hifiId': 'kuwo_$songId',
              'songid': songId,
              'time': time,
              'sign': sign,
              'bitrate': cand.kuwoBitrate,
              'matchScore': cand.score,
              'isHiRes': cand.isHiRes,
            },
          );

          _persistResolution(trackIdKey, elevated);
          _persistResolution(textKey, elevated);

          // Trigger background cache of FLAC file
          flacCache.cacheFlacStream(trackIdKey, flacUrl);

          return elevated;
        }
      } else if (cand.provider == 'monochrome' && cand.monoTrack?.flacStreamUrl != null) {
        final mono = cand.monoTrack!;
        final isVerified = await _monochromeService.verifyStreamUrl(mono.flacStreamUrl!);
        if (isVerified) {
          final elevated = youtubeTrack.copyWith(
            flacStreamUrl: mono.flacStreamUrl,
            audioSource: 'monochrome',
            isLossless: true,
            audioFormat: mono.audioFormat ?? '16-bit • 44.1kHz Lossless FLAC',
            extraData: {
              ...?youtubeTrack.extraData,
              'hifiVersion': matcherVersion,
              'hifiId': mono.id,
              'matchScore': cand.score,
              'isHiRes': cand.isHiRes,
            },
          );

          _persistResolution(trackIdKey, elevated);
          _persistResolution(textKey, elevated);

          // Trigger background cache of FLAC file
          flacCache.cacheFlacStream(trackIdKey, mono.flacStreamUrl!);

          return elevated;
        }
      }
    }

    _unmatchedCache.add(trackIdKey);
    _unmatchedCache.add(textKey);
    return null;
  }
}
