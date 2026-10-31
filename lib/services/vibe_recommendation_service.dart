import '../../models/track.dart';
import 'youtube_music_service.dart';

/// Implements intelligent Vibe and Genre Endless Play recommendation
/// based on YouTube Music Mix Spheres, Anchor Consistency, and Artist Fatigue penalties.
class VibeRecommendationService {
  final YouTubeMusicService _ytmService;
  final Map<String, List<Track>> _mixCache = {};

  VibeRecommendationService({YouTubeMusicService? ytmService})
      : _ytmService = ytmService ?? YouTubeMusicService();

  /// Resolves the next best track that fits the current vibe, queue context,
  /// and anchor genre while avoiding artist fatigue and semantic duplicates.
  Future<Track?> getNextVibeTrack({
    required List<Track> queue,
    required int currentIndex,
  }) async {
    if (queue.isEmpty) return null;

    // 1. Identify primary context nodes
    final lastIdx = queue.length - 1;
    final songA = queue[lastIdx];
    final songB = queue.length >= 2 ? queue[lastIdx - 1] : null;
    final anchorSong = queue.first;

    final songAId = songA.youtubeVideoId ?? songA.id;
    if (songAId.isEmpty) return null;

    // 2. Fetch Mix Spheres
    final mixA = await _getMix(songAId);
    final mixB = (songB != null && (songB.youtubeVideoId ?? songB.id).isNotEmpty)
        ? await _getMix(songB.youtubeVideoId ?? songB.id)
        : <Track>[];

    final anchorId = anchorSong.youtubeVideoId ?? anchorSong.id;
    final mixAnchor = (anchorId.isNotEmpty && anchorId != songAId && (songB == null || anchorId != (songB.youtubeVideoId ?? songB.id)))
        ? await _getMix(anchorId)
        : <Track>[];

    // 3. Build candidate pool avoiding exact IDs and duplicates
    final existingIds = queue.map((s) => s.youtubeVideoId ?? s.id).toSet();
    final existingWordSets = queue.map(_getWords).toList();

    final candidatePool = <Track>[];
    final seenIds = <String>{};

    for (final track in mixA) {
      final tId = track.youtubeVideoId ?? track.id;
      if (!existingIds.contains(tId) && !seenIds.contains(tId)) {
        candidatePool.add(track);
        seenIds.add(tId);
      }
    }

    if (mixB.isNotEmpty) {
      for (final track in mixB) {
        final tId = track.youtubeVideoId ?? track.id;
        if (!existingIds.contains(tId) && !seenIds.contains(tId)) {
          candidatePool.add(track);
          seenIds.add(tId);
        }
      }
    }

    // Filter semantic duplicates (Jaccard similarity > 0.55 against queue songs)
    var available = candidatePool.where((cand) {
      final candWords = _getWords(cand);
      for (final exWords in existingWordSets) {
        if (_calculateSimilarity(candWords, exWords) > 0.55) {
          return false;
        }
      }
      return true;
    }).toList();

    // 4. Fallback search if candidate pool is exhausted
    if (available.isEmpty) {
      try {
        final cleanArtist = _extractArtistClean(songA);
        final query = cleanArtist.isNotEmpty ? '$cleanArtist songs' : '${songA.title} songs';
        final searchFallback = await _ytmService.searchSongs(query);
        available = searchFallback.where((cand) {
          final tId = cand.youtubeVideoId ?? cand.id;
          if (existingIds.contains(tId)) return false;
          final candWords = _getWords(cand);
          for (final exWords in existingWordSets) {
            if (_calculateSimilarity(candWords, exWords) > 0.55) return false;
          }
          return true;
        }).toList();
      } catch (_) {}
    }

    if (available.isEmpty) {
      // Final fallback: return first candidate from mixA even if similarity was close
      if (mixA.isNotEmpty) {
        final firstUnplayed = mixA.firstWhere(
          (t) => !existingIds.contains(t.youtubeVideoId ?? t.id),
          orElse: () => mixA.first,
        );
        return firstUnplayed;
      }
      return null;
    }

    // 5. Score candidates based on nadanada vibe sphere logic
    final sphereB = songB != null ? _analyzeSphere(mixB, songB) : null;
    final sphereAnchor = queue.length >= 3 ? _analyzeSphere(mixAnchor, anchorSong) : null;
    final recentHistory = queue.sublist(queue.length > 7 ? queue.length - 7 : 0);

    final scored = <_ScoredCandidate>[];

    for (final cand in available) {
      int score = 0;
      final candArtistNorm = _normalizeArtistName(_extractArtistClean(cand));
      final candWords = candArtistNorm.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

      // Rule A: Fatigue penalty - strictly reject if candidate is by the immediate predecessor's artist
      if (_isSameArtist(cand, songA)) {
        scored.add(_ScoredCandidate(cand, -9999, rejected: true));
        continue;
      }

      // Rule B: Penalize if artist appeared in the last 2-7 songs
      final recentConflicts = recentHistory.where((h) => _isSameArtist(cand, h)).length;
      if (recentConflicts > 0) {
        score -= recentConflicts * 80;
      }

      // Rule C: YouTube Music Mix relevance rank bonus
      final rankInA = mixA.indexWhere((t) => (t.youtubeVideoId ?? t.id) == (cand.youtubeVideoId ?? cand.id));
      if (rankInA != -1) {
        score += (50 - rankInA).clamp(0, 50);
      }

      // Rule D: Consistency with Song B (Sphere B)
      if (sphereB != null) {
        final candId = cand.youtubeVideoId ?? cand.id;
        if (sphereB.trackIds.contains(candId)) {
          score += 80; // Direct track match in Song B's sphere
        } else if (sphereB.artistNames.contains(candArtistNorm)) {
          score += 50; // Artist is in Song B's sphere
        } else if (candWords.any((w) => sphereB.artistWords.contains(w))) {
          score += 25; // Shared artist token
        } else {
          score -= 50; // Disconnected from Song B
        }
      }

      // Rule E: Consistency with Playlist Anchor (Original Mood / Theme)
      if (sphereAnchor != null) {
        final candId = cand.youtubeVideoId ?? cand.id;
        if (sphereAnchor.trackIds.contains(candId)) {
          score += 70; // Direct track match with anchor theme
        } else if (sphereAnchor.artistNames.contains(candArtistNorm)) {
          score += 45; // Artist belongs to anchor theme
        } else if (candWords.any((w) => sphereAnchor.artistWords.contains(w))) {
          score += 20; // Shared token with anchor
        } else {
          score -= 60; // Disconnected from anchor theme
        }
      }

      // Rule F: Penalize derivatives (karaoke, covers, instrumental, 8d audio, slowed)
      if (_isDerivative(cand)) {
        score -= 150;
      }

      scored.add(_ScoredCandidate(cand, score, rejected: false));
    }

    // 6. Select the top valid candidate
    final valid = scored.where((s) => !s.rejected && s.score > -200).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (valid.isNotEmpty) {
      return valid.first.track;
    }

    final fallback = scored.where((s) => !s.rejected).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return fallback.isNotEmpty ? fallback.first.track : available.first;
  }

  Future<List<Track>> _getMix(String videoId) async {
    if (_mixCache.containsKey(videoId)) {
      return _mixCache[videoId]!;
    }
    try {
      final res = await _ytmService.getRelatedTracks(videoId);
      if (res.isNotEmpty) {
        _mixCache[videoId] = res;
        if (_mixCache.length > 30) {
          _mixCache.remove(_mixCache.keys.first);
        }
        return res;
      }
    } catch (_) {}
    return [];
  }

  Set<String> _getWords(Track track) {
    final text = '${track.title} ${track.artist}'.toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'\b(?:official|music|video|audio|hd|hq|lyrics?|topic|mv|visualizer)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ');
    return text.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
  }

  double _calculateSimilarity(Set<String> setA, Set<String> setB) {
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  String _extractArtistClean(Track track) {
    var artist = track.artist
        .replaceAll(RegExp(r'\s*-\s*topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'vevo$', caseSensitive: false), '')
        .replaceAll(RegExp(r'official(\s+channel|\s+music)?$', caseSensitive: false), '')
        .trim();
    if (track.title.contains(' - ')) {
      final prefix = track.title.split(' - ')[0].trim();
      if (prefix.length >= 2 && prefix.length <= 40) return prefix;
    } else if (track.title.contains(' ~ ')) {
      final prefix = track.title.split(' ~ ')[0].trim();
      if (prefix.length >= 2 && prefix.length <= 40) return prefix;
    }
    return artist;
  }

  String _normalizeArtistName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
        .replaceAll(RegExp(r'\b(?:feat|ft|featuring|with|prod|x)\b.*$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u4e00-\u9faf]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isSameArtist(Track a, Track b) {
    final normA = _normalizeArtistName(_extractArtistClean(a));
    final normB = _normalizeArtistName(_extractArtistClean(b));
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;
    if (normA.length > 3 && normB.length > 3 && (normA.contains(normB) || normB.contains(normA))) {
      return true;
    }
    return false;
  }

  bool _isDerivative(Track track) {
    final titleAndArtist = '${track.title} ${track.artist}'.toLowerCase();
    return RegExp(
      r'\b(karaoke|instrumental|cover|tribute|remix|slowed|reverb|sped up|nightcore|8d audio|acoustic|piano version)\b',
      caseSensitive: false,
    ).hasMatch(titleAndArtist);
  }

  _MixSphere _analyzeSphere(List<Track> mix, Track baseSong) {
    final sphere = _MixSphere();
    final baseId = baseSong.youtubeVideoId ?? baseSong.id;
    if (baseId.isNotEmpty) sphere.trackIds.add(baseId);

    final baseArtist = _normalizeArtistName(_extractArtistClean(baseSong));
    if (baseArtist.isNotEmpty) {
      sphere.artistNames.add(baseArtist);
      for (final w in baseArtist.split(RegExp(r'\s+')).where((w) => w.length > 2)) {
        sphere.artistWords.add(w);
      }
    }

    for (final track in mix) {
      final tId = track.youtubeVideoId ?? track.id;
      if (tId.isNotEmpty) sphere.trackIds.add(tId);
      final art = _normalizeArtistName(_extractArtistClean(track));
      if (art.isNotEmpty) {
        sphere.artistNames.add(art);
        for (final w in art.split(RegExp(r'\s+')).where((w) => w.length > 2)) {
          sphere.artistWords.add(w);
        }
      }
    }

    return sphere;
  }
}

class _MixSphere {
  final Set<String> trackIds = {};
  final Set<String> artistNames = {};
  final Set<String> artistWords = {};
}

class _ScoredCandidate {
  final Track track;
  final int score;
  final bool rejected;

  _ScoredCandidate(this.track, this.score, {this.rejected = false});
}
