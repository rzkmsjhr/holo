import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
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

class HifiMatcher {
  final KuwoService _kuwoService = KuwoService();
  final MonochromeService _monochromeService = MonochromeService();

  /// Current matcher version. Incrementing forces stale persisted tracks to be re-evaluated.
  static const int matcherVersion = 8;

  // In-memory cache for fast resolution
  static final Map<String, Track> _resolutionCache = {};
  static final Set<String> _unmatchedCache = {};

  static const Set<String> knownUpstreamMismatches = {
    '168395054749057024', // Dewa 19 - Aku Milikmu (2021 Virzha single instead of 1994 Ari Lasso master)
    '168589766881927168', // Dewa 19 feat. Virzha - Aku Milikmu (2021 Virzha remake)
    '168395069831774208', // Dewa 19 - Tak Kan Ada Cinta Yang Lain (2021 Ello remake)
    '168395062953115648', // Dewa 19 - Mahameru (2021 Virzha remake)
  };

  static const List<String> videoKeywords = [
    'official music video',
    'official video',
    'music video',
    'official audio video',
    'lyric video',
    'lyrics video',
    'visualizer',
    'official visualizer',
    'performance video',
    'live performance',
    'dance practice',
    'live at',
    'live in',
    'live from',
    'live concert',
    'full concert',
    'trailer',
    'teaser',
    '[mv]',
    '(mv)',
    '[m/v]',
    '(m/v)',
    '[official video]',
    '(official video)',
    '[official music video]',
    '(official music video)',
    '(video)',
    '[video]',
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
  /// Rejects music videos, live concerts, dance practices, covers, and derivatives.
  static bool isEligibleTrack(Track track) {
    final itemType = (track.extraData?['itemType']?.toString() ?? '').toLowerCase().trim();
    if (itemType == 'video') return false;

    final channel = track.artist.toLowerCase().trim();
    if (channel.contains('vevo')) return false;

    final title = track.title.toLowerCase().trim();
    if (videoKeywords.any((k) => title.contains(k))) return false;
    if (derivativeKeywords.any((k) => title.contains(k))) return false;
    if (RegExp(r'\b(mv|m/v)\b', caseSensitive: false).hasMatch(title)) return false;

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

  /// Scores a candidate track against target metadata using multilingual cross-script comparison.
  /// Returns a confidence score from 0 to 200. Minimum qualifying score is 85.
  static int scoreTrackCandidate({
    required String targetTitle,
    required String targetArtist,
    required int targetDurSecs,
    required String candId,
    required String candTitle,
    required String candArtist,
    required int candDurSecs,
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

    // If title does not match at all, reject immediately
    if (!titleMatched) {
      return 0;
    }

    // 4. Strict duration comparison
    if (targetDurSecs > 0 && candDurSecs > 0) {
      final diff = (targetDurSecs - candDurSecs).abs();
      final maxAllowedDiff = (targetDurSecs * 0.05).clamp(15.0, 25.0).round();
      if (diff > maxAllowedDiff) {
        return 0;
      }

      if (diff <= 2) {
        score += 40;
      } else if (diff <= 4) {
        score += 25;
      } else if (diff <= 7) {
        score += 10;
      } else if (diff <= 12) {
        score = (score - 15).clamp(0, 300);
      } else {
        score = (score - 45).clamp(0, 300);
      }
    } else if (targetDurSecs > 0 && candDurSecs == 0) {
      score = (score - 20).clamp(0, 300);
    }

    return score;
  }

  /// Attempts to elevate an eligible YouTube track to Lossless FLAC.
  /// Priority:
  /// 1. Kuwo FLAC (Top Priority for Lossless FLAC)
  /// 2. Monochrome FLAC (Secondary verified fallback)
  /// 3. Returns null if neither can serve Hi-Fi (falls back cleanly to YouTube)
  Future<Track?> matchToHifi(Track youtubeTrack) async {
    // 0. Eligibility check
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

    final cleanedTitle = cleanTitle(youtubeTrack.title);
    final targetArtist = youtubeTrack.artist.trim();
    final targetDurSecs = youtubeTrack.durationSeconds;

    final queries = [
      '$cleanedTitle $targetArtist'.trim(),
      cleanedTitle,
    ];

    // 1. Primary Provider: Kuwo FLAC
    Map<String, dynamic>? bestKuwoCand;
    String? bestKuwoFlacBitrate;
    int bestKuwoScore = 0;

    for (final q in queries) {
      try {
        final candidates = await _kuwoService.searchCandidates(q, size: 8);
        for (final c in candidates) {
          final flacBitrate = _kuwoService.extractFlacBitrate(c);
          if (flacBitrate == null) continue;

          final cId = c['id']?.toString() ?? '';
          if (cId.isEmpty) continue;
          final cTitle = c['name']?.toString() ?? '';
          final cArtist = c['artist']?.toString() ?? '';
          final cDur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;

          final score = scoreTrackCandidate(
            targetTitle: youtubeTrack.title,
            targetArtist: targetArtist,
            targetDurSecs: targetDurSecs,
            candId: cId,
            candTitle: cTitle,
            candArtist: cArtist,
            candDurSecs: cDur,
          );

          if (score >= 85 && score > bestKuwoScore) {
            bestKuwoCand = c;
            bestKuwoFlacBitrate = flacBitrate;
            bestKuwoScore = score;
          }
        }
      } catch (_) {}

      if (bestKuwoScore >= 95) {
        break; // Strong match found on primary query; skip secondary query
      }
    }

    Track? kuwoElevated;
    bool kuwoIsHiRes = false;

    if (bestKuwoCand != null && bestKuwoFlacBitrate != null) {
      final songId = bestKuwoCand['id']?.toString() ?? '';
      final time = bestKuwoCand['time'];
      final sign = bestKuwoCand['sign']?.toString() ?? '';
      kuwoIsHiRes = _kuwoService.isHiResFlac(bestKuwoCand);

      final flacUrl = await _kuwoService.getFlacStreamUrl(
        songId: songId,
        time: time,
        sign: sign,
        bitrate: bestKuwoFlacBitrate,
      );

      if (flacUrl != null && flacUrl.isNotEmpty) {
        kuwoElevated = youtubeTrack.copyWith(
          flacStreamUrl: flacUrl,
          audioSource: 'kuwo',
          isLossless: true,
          audioFormat: kuwoIsHiRes
              ? '24-bit • 96kHz Lossless FLAC'
              : '16-bit • 44.1kHz Lossless FLAC',
          extraData: {
            ...?youtubeTrack.extraData,
            'hifiVersion': matcherVersion,
            'hifiId': 'kuwo_$songId',
            'matchScore': bestKuwoScore,
            'isHiRes': kuwoIsHiRes,
            'bitrate': bestKuwoFlacBitrate,
          },
        );

        // Return immediately as soon as Kuwo resolves a valid lossless FLAC
        _resolutionCache[trackIdKey] = kuwoElevated;
        _resolutionCache[textKey] = kuwoElevated;
        return kuwoElevated;
      }
    }

    // 2. Secondary Provider: Monochrome FLAC (check for 24-bit Hi-Res master or Kuwo fallback)
    try {
      final monoCandidates = await _monochromeService.searchTracks(
        '$cleanedTitle $targetArtist',
        limit: 10,
      );

      Track? bestMonoCand;
      int bestMonoScore = 0;

      for (final candidate in monoCandidates) {
        final score = scoreTrackCandidate(
          targetTitle: youtubeTrack.title,
          targetArtist: targetArtist,
          targetDurSecs: targetDurSecs,
          candId: candidate.id,
          candTitle: candidate.title,
          candArtist: candidate.artist,
          candDurSecs: candidate.durationSeconds,
        );

        if (score >= 85 && score > bestMonoScore) {
          bestMonoCand = candidate;
          bestMonoScore = score;
        }
      }

      if (bestMonoCand != null && bestMonoCand.flacStreamUrl != null) {
        final monoFormat = bestMonoCand.audioFormat ?? '16-bit • 44.1kHz Lossless FLAC';
        final monoIsHiRes = monoFormat.contains('24-bit') || monoFormat.contains('96kHz');

        // Verify stream URL before elevating
        final isVerified = await _monochromeService
            .verifyStreamUrl(bestMonoCand.flacStreamUrl!);

        if (isVerified) {
          final elevated = youtubeTrack.copyWith(
            flacStreamUrl: bestMonoCand.flacStreamUrl,
            audioSource: 'monochrome',
            isLossless: true,
            audioFormat: monoFormat,
            extraData: {
              ...?youtubeTrack.extraData,
              'hifiVersion': matcherVersion,
              'hifiId': bestMonoCand.id,
              'matchScore': bestMonoScore,
              'isHiRes': monoIsHiRes,
            },
          );
          _resolutionCache[trackIdKey] = elevated;
          _resolutionCache[textKey] = elevated;
          return elevated;
        }
      }
    } catch (_) {}

    // 3. Mark as unmatched for fast replay
    _unmatchedCache.add(trackIdKey);
    _unmatchedCache.add(textKey);
    return null;
  }
}
