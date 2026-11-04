import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/text_encoding_utils.dart';
import '../models/track.dart';
import 'flac_cache_service.dart';
import 'kuwo_service.dart';
import 'monochrome_service.dart';

enum EditionKind {
  remix,
  live,
  acoustic,
  instrumental,
  soundtrack,
  reRecorded,
  cover,
}

class EditionMatrix {
  static final RegExp remixRegex = RegExp(
    r'\b(remix|remixes|club\s*mix|extended\s*mix|vip\s*mix|dub\s*mix|dance\s*mix|dance\s*remix|electro\s*mix)\b',
    caseSensitive: false,
  );
  static final RegExp liveRegex = RegExp(
    r'\b(live\s*at|live\s*version|in\s*concert|live\s*in|live\s*from|tour\s*version|festival\s*live|hits\s+alive|alive\s*vol\w*|alive\s*\d{4}|live\s*sessions?|(?:london|red\s*rocks|vegas|mtv\s*unplugged|bbc|spotify|itunes|aol)\s+sessions?)\b|[\(\[\{]\s*(?:live|live\s+[^)\]\}]+)\s*[\)\]\}]|\s+-\s+live\b|(现场|演唱会|秀场音乐|秀场|现场版)',
    caseSensitive: false,
  );
  static final RegExp acousticRegex = RegExp(
    r'\b(acoustic|unplugged|stripped|piano\s*version|orchestral\s*version)\b|[\(\[\{]\s*(?:acoustic|piano|orchestral)\s*[\)\]\}]',
    caseSensitive: false,
  );
  static final RegExp instrumentalRegex = RegExp(
    r'\b(instrumental|instrumen|inst\.?|karaoke|karoke|backing\s*track|minus\s*(?:one|1)|minus-one|-1|off\s*vocal|no\s*vocal|tanpa\s*vokal)\b|(伴奏|原版伴奏|纯音乐|伴唱|消音)',
    caseSensitive: false,
  );
  static final RegExp soundtrackRegex = RegExp(
    r'\b(soundtrack|ost|motion\s*picture)\b|(电影主题曲|电视剧主题曲|电影插曲|电影片尾曲|影视原声|电影原声)',
    caseSensitive: false,
  );
  static final RegExp reRecordedRegex = RegExp(
    r'\b(re-record\w*|rerecord\w*|re-cut|recut)\b',
    caseSensitive: false,
  );
  static final RegExp coverRegex = RegExp(
    r'\b(originally\s*performed\s*by|made\s*popular\s*by|in\s*the\s*style\s*of|tribute\s*version|tribute\s*to)\b|[\(\[\{]\s*cover\s*[\)\]\}]|\s+-\s+cover\b',
    caseSensitive: false,
  );

  static Set<EditionKind> detect(String title, [String? album]) {
    final editions = <EditionKind>{};
    final text = album != null && album.isNotEmpty ? '$title $album' : title;

    if (remixRegex.hasMatch(text)) editions.add(EditionKind.remix);
    if (liveRegex.hasMatch(text)) editions.add(EditionKind.live);
    if (acousticRegex.hasMatch(text)) editions.add(EditionKind.acoustic);
    if (instrumentalRegex.hasMatch(text)) editions.add(EditionKind.instrumental);
    if (soundtrackRegex.hasMatch(text)) editions.add(EditionKind.soundtrack);
    if (reRecordedRegex.hasMatch(text)) editions.add(EditionKind.reRecorded);
    if (coverRegex.hasMatch(text)) editions.add(EditionKind.cover);

    return editions;
  }

  static bool isCompatible(Set<EditionKind> target, Set<EditionKind> cand) {
    if (target.isEmpty) {
      return cand.isEmpty;
    }
    return target.length == cand.length && target.containsAll(cand);
  }

  static bool hasConflict(Set<EditionKind> target, Set<EditionKind> cand) =>
      !isCompatible(target, cand);
}

class HifiMatcher {
  final KuwoService _kuwoService = KuwoService();
  final MonochromeService _monochromeService = MonochromeService();

  /// Matcher version 12 - matching nadanada v12 specification
  static const int matcherVersion = 12;
  static const String _storageKey = 'holo_hifi_cache_v12';
  static const List<String> _legacyStorageKeys = [
    'holo_hifi_cache',
    'holo_hifi_cache_v2',
    'holo_hifi_cache_v11',
  ];

  bool _isInitialized = false;

  // In-memory cache for fast resolution
  static final Map<String, Track> _resolutionCache = {};
  static final Set<String> _unmatchedCache = {};

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clean up legacy caches
      for (final oldKey in _legacyStorageKeys) {
        if (prefs.containsKey(oldKey)) {
          prefs.remove(oldKey);
        }
      }

      final saved = prefs.getString(_storageKey);
      if (saved != null && saved.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(saved);
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            final t = Track.fromJson(val);
            if (t.isLossless &&
                t.flacStreamUrl != null &&
                t.flacStreamUrl!.isNotEmpty) {
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

  /// Checks whether a track was already determined to have no Hi-Fi match.
  bool isUnmatched(Track track) {
    final trackIdKey = track.youtubeVideoId ?? track.id;
    if (_unmatchedCache.contains(trackIdKey)) return true;
    final textKey =
        '${track.artist.toLowerCase()}:::${track.title.toLowerCase()}';
    return _unmatchedCache.contains(textKey);
  }

  /// Synchronous 0ms gate normalization applied to any track entering playlist or queue.
  Track prepareTrackThroughGateSync(Track rawTrack, {bool isHifiEnabled = true}) {
    var track = rawTrack;
    if (!isEligibleTrack(track) || !isHifiEnabled) {
      return track.copyWith(
        flacStreamUrl: null,
        audioSource: 'youtube',
        isLossless: false,
        audioFormat: 'YouTube Audio (160kbps)',
        extraData: {
          ...?track.extraData,
          'hifiVersion': matcherVersion,
          'hifiChecked': true,
        },
      );
    }

    // Check version
    final v = track.extraData?['hifiVersion'];
    if (track.isLossless && (v == null || v != matcherVersion)) {
      track = track.copyWith(
        flacStreamUrl: null,
        audioSource: 'youtube',
        isLossless: false,
        audioFormat: 'YouTube Audio (160kbps)',
      );
    }

    // Check cache
    final cached = getCachedHiFi(track);
    if (cached != null && cached.flacStreamUrl != null && cached.flacStreamUrl!.isNotEmpty) {
      final cachedWithAlbum = cached.extraData?['resolvedWithAlbum'] == true;
      final currentHasAlbum = track.album.trim().isNotEmpty;
      if (currentHasAlbum && !cachedWithAlbum) {
        return track;
      }
      return cached;
    }

    return track;
  }

  /// Known upstream mismatch blacklist matching nadanada matcher.rs
  static const Set<String> knownUpstreamMismatches = {
    '168395054749057024', // Dewa 19 - Aku Milikmu (2021 Virzha)
    '168589766881927168', // Dewa 19 feat. Virzha - Aku Milikmu
    '168395069831774208', // Dewa 19 - Tak Kan Ada Cinta Yang Lain (2021 Ello)
    '168395062953115648', // Dewa 19 - Mahameru (2021 Virzha)
    '162001181',          // Kuwo fake tag: Panem. The Land sound-alike cover of Portugal. The Man - Feel It Still
    'kuwo_162001181',
    '228981606',          // Kuwo mislabeled: Andra & The Backbone - Main Hati (audio is actually Kepayang)
    'kuwo_228981606',
    '228983127',          // Kuwo mislabeled: Andra & The Backbone - Kepayang (audio is actually Hitamku)
    'kuwo_228983127',
    '5266278',            // Kuwo: Maroon 5 - Animals (2015 Victoria's Secret runway music)
    'kuwo_5266278',
    '196763238',          // Kuwo: Imagine Dragons - Demons (TELYKast Remix)
    'kuwo_196763238',
    '198259372',          // Kuwo: Imagine Dragons - Demons (Live From Red Rocks / 2014)
    'kuwo_198259372',
    '238687094',          // Kuwo: Imagine Dragons - Demons (Live London Sessions / 2013)
    'kuwo_238687094',
    '238687044',          // Kuwo: Imagine Dragons - Demons (TELYKast Remix on Super Deluxe)
    'kuwo_238687044',
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

  static final RegExp deluxeAlbumRegex = RegExp(
    r"\b(expanded(\s*edition)?|super\s*deluxe(\s*edition)?|deluxe(\s*edition)?|special\s*edition|bonus\s*track\s*edition|anniversary(\s*edition)?|collector('?s)?\s*edition|tour\s*edition)\b",
    caseSensitive: false,
  );

  static final RegExp compilationAlbumRegex = RegExp(
    r'\b(greatest\s*hits|best\s*of|hits\s*vol\w*|volume\s*\d+|vol\.\s*\d+|the\s*collection|anthology|compilation|various\s*artists|essential)\b',
    caseSensitive: false,
  );

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

  /// Strips Latin diacritics / accented characters (ported from nadanada script.rs)
  static String stripLatinDiacritics(String s) {
    const from = 'àáâãäåāăąÀÁÂÃÄÅĀĂĄèéêëēĕėęěÈÉÊËĒĔĖĘĚìíîïīĭįıÌÍÎÏĪĬĮİòóôõöøōŏőÒÓÔÕÖØŌŎŐùúûüūŭůűųÙÚÛÜŪŬŮŰŲýỳŷÿÝỲŶŸñńņňÑŃŅŇçćĉċčÇĆĈĊČśŝşșšŚŜŞȘŠźżžŹŻŽðđÐĐłŁß';
    const to   = 'aaaaaaaaaAAAAAAAAAeeeeeeeeeEEEEEEEEEiiiiiiiiIIIIIIIIoooooooooOOOOOOOOOuuuuuuuuuUUUUUUUUUyyyyYYYYnnnnNNNNcccccCCCCCsssssSSSSSzzzZZZddDDlLs';
    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final char = s[i];
      final idx = from.indexOf(char);
      if (idx != -1) {
        sb.write(to[idx]);
      } else {
        sb.write(char);
      }
    }
    return sb.toString();
  }

  /// Checks if a YouTube track is eligible for Hi-Fi elevation.
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
    lower = stripLatinDiacritics(lower);
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
    lower = stripLatinDiacritics(lower);
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

  /// Scores a candidate track against target metadata using universal edition verification,
  /// token-residue title scoring, duration matching, and tiered album matching (matching nadanada v11).
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

    // 1. Universal Edition Matrix Compatibility
    final targetEditions = EditionMatrix.detect(targetTitle, targetAlbum);
    final candEditions = EditionMatrix.detect(candTitle, candAlbum);
    if (!EditionMatrix.isCompatible(targetEditions, candEditions)) {
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

    // Check for unrequested collaborators in candidate artist (-35 penalty each)
    final targetList = splitArtistList(targetArtist);
    final candList = splitArtistList(candArtist);
    final lowerTitle = '$targetTitle ${targetAlbum ?? ''}'.toLowerCase();
    int unrequestedArtists = 0;
    for (final c in candList) {
      if (!targetList.any((t) => t == c || cleanString(t) == cleanString(c)) &&
          !lowerTitle.contains(c.toLowerCase())) {
        unrequestedArtists++;
      }
    }
    if (unrequestedArtists > 0) {
      score = (score - (unrequestedArtists * 35)).clamp(0, 300);
    }

    // 3. Title comparison with token residue scoring
    final targetClean = cleanString(targetTitle);
    final candClean = cleanString(candTitle);

    bool titleMatched = false;
    if (targetClean.isNotEmpty && candClean.isNotEmpty) {
      if (targetClean == candClean) {
        score += 100;
        titleMatched = true;
      } else if (candClean.contains(targetClean) || targetClean.contains(candClean)) {
        final maxLen = targetClean.length > candClean.length ? targetClean.length : candClean.length;
        final minLen = targetClean.length < candClean.length ? targetClean.length : candClean.length;
        final residue = maxLen - minLen;
        if (residue <= 3) {
          score += 85;
          titleMatched = true;
        } else if (residue <= 8) {
          score += 65;
          titleMatched = true;
        } else {
          score += 45;
          titleMatched = true;
        }
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

    // 4. Strict Studio Duration comparison
    if (targetDurSecs > 0 && candDurSecs > 0) {
      final diff = (targetDurSecs - candDurSecs).abs();
      final maxAllowedDiff = targetDurSecs > 350
          ? (targetDurSecs * 0.02).clamp(7.0, 12.0).round()
          : 7;

      if (diff > maxAllowedDiff) {
        return 0; // Alternate take, live version, or unedited audio -> disqualify
      }

      if (diff <= 2) {
        score += 40; // Exact studio duration match down to 2s
      } else if (diff <= 4) {
        score += 15; // Minor fade/pad variance
      } else {
        score = (score - 30).clamp(0, 300); // 5s to 7s penalty
      }
    } else if (targetDurSecs > 0 && candDurSecs == 0) {
      score = (score - 25).clamp(0, 300);
    }

    // 5. Tiered Album comparison & compilation penalty
    if (candAlbum != null && candAlbum.trim().isNotEmpty) {
      final cLower = candAlbum.toLowerCase();
      final targetIsComp = targetAlbum != null &&
          compilationAlbumRegex.hasMatch(targetAlbum.toLowerCase());

      // Compilation penalty if target is not a compilation
      if (!targetIsComp && compilationAlbumRegex.hasMatch(cLower)) {
        score = (score - 45).clamp(0, 300);
      }

      if (targetAlbum != null && targetAlbum.trim().isNotEmpty) {
        final tClean = cleanString(targetAlbum);
        final cClean = cleanString(candAlbum);
        if (tClean.isNotEmpty && cClean.isNotEmpty) {
          final tHasDeluxe = deluxeAlbumRegex.hasMatch(targetAlbum.toLowerCase());
          final cHasDeluxe = deluxeAlbumRegex.hasMatch(cLower);

          if (tClean == cClean) {
            if (!tHasDeluxe && cHasDeluxe) {
              score += 30; // Tier 2 Deluxe bonus
            } else {
              score += 65; // Tier 1 Canonical base album bonus
            }
          } else if (tClean.contains(cClean) || cClean.contains(tClean)) {
            if (!tHasDeluxe && cHasDeluxe) {
              score += 20;
            } else {
              score += 35; // Partial album match
            }
          }
        }
      }
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
    return matchToHifi(track);
  }

  /// Attempts to elevate an eligible YouTube track to Lossless FLAC
  /// with STRICT provider priority: Kuwo Primary -> Monochrome Fallback -> YouTube (null).
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
    final targetAlbum = youtubeTrack.album.trim();

    // =========================================================================
    // PASS 1: KUWO PRIMARY PROVIDER (flac.music.hi.cn)
    // Multi-pass query: Album-first -> Base artist+title -> Clean title
    // =========================================================================
    final kuwoQueries = <String>[];
    if (targetAlbum.isNotEmpty) {
      kuwoQueries.add('$targetArtist $cleanedTitle $targetAlbum'.trim());
      final deAlb = stripLatinDiacritics('$targetArtist $cleanedTitle $targetAlbum'.trim());
      if (deAlb != kuwoQueries.first && !kuwoQueries.contains(deAlb)) {
        kuwoQueries.add(deAlb);
      }
    }
    final baseKuwo = '$targetArtist $cleanedTitle'.trim();
    if (!kuwoQueries.contains(baseKuwo)) {
      kuwoQueries.add(baseKuwo);
    }
    final deBase = stripLatinDiacritics(baseKuwo);
    if (deBase != baseKuwo && !kuwoQueries.contains(deBase)) {
      kuwoQueries.add(deBase);
    }
    if (!kuwoQueries.contains(cleanedTitle)) {
      kuwoQueries.add(cleanedTitle);
    }

    Map<String, dynamic>? bestKuwoRaw;
    String? bestKuwoBitrate;
    bool bestKuwoIsHiRes = false;
    int bestKuwoScore = 0;

    for (final q in kuwoQueries.take(4)) {
      try {
        final list = await _kuwoService.searchCandidates(q, size: 12);
        // Detect albums containing multiple tracks with identical title (e.g. single releases with Track 1 = Vocal, Track 2 = Minus One/Karaoke)
        final albumTitleMinId = <String, int>{};
        for (final c in list) {
          final ct = cleanString(c['name']?.toString() ?? '');
          final ca = cleanString(c['album_name']?.toString() ?? '');
          if (ct.isNotEmpty && ca.isNotEmpty) {
            final key = '$ct::$ca';
            final idNum =
                int.tryParse(c['id']?.toString() ?? '') ?? 0x7FFFFFFFFFFFFFFF;
            final existingMin = albumTitleMinId[key];
            if (existingMin == null || idNum < existingMin) {
              albumTitleMinId[key] = idNum;
            }
          }
        }

        for (final c in list) {
          final flacBitrate = _kuwoService.extractFlacBitrate(c);
          if (flacBitrate == null) continue;

          final cId = c['id']?.toString() ?? '';
          if (cId.isEmpty) continue;
          final cTitle = c['name']?.toString() ?? '';
          final cArtist = c['artist']?.toString() ?? '';
          final cAlbum = c['album_name']?.toString() ?? '';
          final cDur = int.tryParse(c['duration']?.toString() ?? '0') ?? 0;

          var score = scoreTrackCandidate(
            targetTitle: youtubeTrack.title,
            targetArtist: targetArtist,
            targetDurSecs: targetDurSecs,
            targetAlbum: targetAlbum.isNotEmpty ? targetAlbum : null,
            candId: cId,
            candTitle: cTitle,
            candArtist: cArtist,
            candAlbum: cAlbum,
            candDurSecs: cDur,
          );

          if (score == 0) continue;

          // If album has multiple tracks sharing the identical title, the primary vocal track is Track 1 (lowest numeric song ID).
          // Any subsequent track (Track 2+, higher ID) is an unlabelled Minus-One / Accompaniment cut -> penalize heavily by 60 points.
          final ct = cleanString(cTitle);
          final ca = cleanString(cAlbum);
          final idNum = int.tryParse(cId) ?? 0x7FFFFFFFFFFFFFFF;
          final minId = albumTitleMinId['$ct::$ca'];
          if (minId != null && idNum > minId) {
            score = (score - 60).clamp(0, 300);
          }

          if (score >= 140) {
            bool isBetter = false;
            if (score > bestKuwoScore) {
              isBetter = true;
            } else if (score == bestKuwoScore && bestKuwoRaw != null) {
              final currId = int.tryParse(cId) ?? 0x7FFFFFFFFFFFFFFF;
              final bestId =
                  int.tryParse(bestKuwoRaw['id']?.toString() ?? '') ?? 0;
              isBetter = currId < bestId;
            }
            if (isBetter) {
              bestKuwoScore = score;
              bestKuwoRaw = c;
              bestKuwoBitrate = flacBitrate;
              bestKuwoIsHiRes = _kuwoService.isHiResFlac(c);
            }
          }
        }
      } catch (_) {}

      // Early break on definitive high-confidence match
      final earlyExit = targetAlbum.isNotEmpty ? 200 : 170;
      if (bestKuwoScore >= earlyExit) {
        break;
      }
    }

    if (bestKuwoRaw != null && bestKuwoBitrate != null && bestKuwoScore >= 140) {
      final songId = bestKuwoRaw['id']?.toString() ?? '';
      final time = bestKuwoRaw['time'];
      final sign = bestKuwoRaw['sign']?.toString() ?? '';

      final flacUrl = await _kuwoService.getFlacStreamUrl(
        songId: songId,
        time: time,
        sign: sign,
        bitrate: bestKuwoBitrate,
      );

      if (flacUrl != null && flacUrl.isNotEmpty) {
        final elevated = youtubeTrack.copyWith(
          flacStreamUrl: flacUrl,
          audioSource: 'kuwo',
          isLossless: true,
          audioFormat: bestKuwoIsHiRes
              ? '24-bit • 96kHz Lossless FLAC'
              : '16-bit • 44.1kHz Lossless FLAC',
          extraData: {
            ...?youtubeTrack.extraData,
            'hifiVersion': matcherVersion,
            'hifiId': 'kuwo_$songId',
            'songid': songId,
            'time': time,
            'sign': sign,
            'bitrate': bestKuwoBitrate,
            'matchScore': bestKuwoScore,
            'isHiRes': bestKuwoIsHiRes,
            'resolvedWithAlbum': targetAlbum.isNotEmpty,
            'hifiChecked': true,
          },
        );

        _persistResolution(trackIdKey, elevated);
        _persistResolution(textKey, elevated);
        flacCache.cacheFlacStream(trackIdKey, flacUrl);
        return elevated;
      }
    }

    // =========================================================================
    // PASS 2: MONOCHROME SECONDARY FALLBACK (tracks.monochrome.st)
    // Only queried if Kuwo returned no qualifying candidate >= 140
    // =========================================================================
    if (!MonochromeService.isCoolingDown()) {
      final monoQueries = <String>[];
      final baseMono = '$targetArtist $cleanedTitle'.trim();
      monoQueries.add(baseMono);
      final deMono = stripLatinDiacritics(baseMono);
      if (deMono != baseMono) {
        monoQueries.add(deMono);
      }
      if (targetAlbum.isNotEmpty) {
        monoQueries.add('$targetArtist $cleanedTitle $targetAlbum'.trim());
      }
      if (!monoQueries.contains(cleanedTitle)) {
        monoQueries.add(cleanedTitle);
      }

      Track? bestMonoTrack;
      int bestMonoScore = 0;

      for (final q in monoQueries.take(3)) {
        try {
          final list = await _monochromeService.searchTracks(q, limit: 12);
          for (final mono in list) {
            final candId = mono.extraData?['recordingId']?.toString() ?? mono.id;
            final score = scoreTrackCandidate(
              targetTitle: youtubeTrack.title,
              targetArtist: targetArtist,
              targetDurSecs: targetDurSecs,
              targetAlbum: targetAlbum.isNotEmpty ? targetAlbum : null,
              candId: candId,
              candTitle: mono.title,
              candArtist: mono.artist,
              candAlbum: mono.album,
              candDurSecs: mono.durationSeconds,
            );

            if (score >= 140) {
              bool isBetter = false;
              if (score > bestMonoScore) {
                isBetter = true;
              } else if (score == bestMonoScore && bestMonoTrack != null) {
                final currId =
                    int.tryParse(mono.id) ?? 0x7FFFFFFFFFFFFFFF;
                final bestId = int.tryParse(bestMonoTrack.id) ?? 0;
                isBetter = currId < bestId;
              }
              if (isBetter) {
                bestMonoScore = score;
                bestMonoTrack = mono;
              }
            }
          }
        } catch (_) {}

        if (bestMonoScore >= 170) {
          break;
        }
      }

      if (bestMonoTrack != null && bestMonoTrack.flacStreamUrl != null && bestMonoScore >= 140) {
        final isVerified = await _monochromeService.verifyStreamUrl(bestMonoTrack.flacStreamUrl!);
        if (isVerified) {
          final isHiRes = bestMonoTrack.audioFormat?.contains('24-bit') == true;
          final elevated = youtubeTrack.copyWith(
            flacStreamUrl: bestMonoTrack.flacStreamUrl,
            audioSource: 'monochrome',
            isLossless: true,
            audioFormat: bestMonoTrack.audioFormat ?? '16-bit • 44.1kHz Lossless FLAC',
            extraData: {
              ...?youtubeTrack.extraData,
              'hifiVersion': matcherVersion,
              'hifiId': bestMonoTrack.id,
              'matchScore': bestMonoScore,
              'isHiRes': isHiRes,
              'resolvedWithAlbum': targetAlbum.isNotEmpty,
              'hifiChecked': true,
            },
          );

          _persistResolution(trackIdKey, elevated);
          _persistResolution(textKey, elevated);
          flacCache.cacheFlacStream(trackIdKey, bestMonoTrack.flacStreamUrl!);
          return elevated;
        }
      }
    }

    // =========================================================================
    // PASS 3: Neither Kuwo nor Monochrome matched -> Fallback to YouTube
    // =========================================================================
    _unmatchedCache.add(trackIdKey);
    _unmatchedCache.add(textKey);
    return null;
  }
}
