import 'package:flutter/material.dart';
import '../models/genre_explore_item.dart';
import '../models/track.dart';

class GenreExploreService {
  static List<GenreExploreItem> getDefaultGenres() {
    return [
      GenreExploreItem(
        id: 'electronic',
        title: 'Electronic',
        gradientColors: const [Color(0xFFFF5416), Color(0xFFB91C1C)],
        searchQuery: 'electronic dance music',
        genreKeywords: [
          'electronic',
          'dance',
          'tycho',
          'swedish house mafia',
          'daft punk',
          'avicii',
          'edm',
          'house'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'Tycho',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/46/be/ed/46beed8a-5d0f-1077-cbeb-aace15e69f44/cover.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Swedish House Mafia',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/7a/a0/33/7aa0335b-167b-c15a-fcac-22e22ed2ea03/5099997933755.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Daft Punk',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/e8/43/5f/e8435ffa-b6b9-b171-40ab-4ff3959ab661/886443919266.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'KAROL G',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/2b/66/b2/2b66b26c-ab23-faa1-c4ee-06fa2cce8f76/26UM1IM00558.rgb.jpg/600x600bb.jpg',
          ),
        ],
      ),
      GenreExploreItem(
        id: 'synthwave',
        title: 'Synthwave',
        gradientColors: const [Color(0xFF5A32A3), Color(0xFF3B82F6)],
        searchQuery: 'synthwave retrowave 80s',
        genreKeywords: [
          'synthwave',
          'retro',
          'the weeknd',
          'the outfield',
          'com truise',
          'kavinsky',
          '80s'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'The Weeknd',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/2a/aa/b4/2aaab42a-a4cb-a600-4a25-d78961495960/18UMGIM17204.rgb.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'The Outfield',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/af/35/d3/af35d339-a9c0-a565-712d-a31dd9e42a4b/mzi.jyzejvil.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Daft Punk',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/e8/43/5f/e8435ffa-b6b9-b171-40ab-4ff3959ab661/886443919266.jpg/600x600bb.jpg',
          ),
        ],
      ),
      GenreExploreItem(
        id: 'acoustic',
        title: 'Acoustic',
        gradientColors: const [Color(0xFF059669), Color(0xFF047857)],
        searchQuery: 'acoustic indie folk',
        genreKeywords: [
          'acoustic',
          'fourtwnty',
          'tulus',
          'feby putri',
          'raim laode',
          'folk',
          'sheeran',
          'unplugged'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'Fourtwnty',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/9b/21/0c/9b210c07-d1cc-be55-a693-76e5250ede5b/859726398386_cover.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Tulus',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/6f/18/10/6f1810e0-2d6a-a456-1362-de607c70408a/cover.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Feby Putri',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/3d/28/f8/3d28f883-fc1a-a88d-3768-2db3a0c0d461/cover.jpg/600x600bb.jpg',
          ),
        ],
      ),
      GenreExploreItem(
        id: 'rnb_soul',
        title: 'R&B Soul',
        gradientColors: const [Color(0xFFD97706), Color(0xFF78350F)],
        searchQuery: 'r&b soul neo soul',
        genreKeywords: [
          'r&b',
          'soul',
          'tyler lewis',
          'sza',
          'frank ocean',
          'adrian khalif',
          'daniel caesar'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'Tyler Lewis',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/3e/63/72/3e63723b-2407-b444-46b0-7660e7125025/663918307229.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'SZA',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/a0/6d/08/a06d082b-9322-3ede-f6aa-fe3e7b9b386f/5056556188568_cover.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Frank Ocean',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/04/f8/63/04f863fc-2852-604f-c910-a97ac069506b/12UMGIM40339.rgb.jpg/600x600bb.jpg',
          ),
        ],
      ),
      GenreExploreItem(
        id: 'pop',
        title: 'Pop Hits',
        gradientColors: const [Color(0xFFE11D48), Color(0xFF9333EA)],
        searchQuery: 'pop hits top 40',
        genreKeywords: [
          'pop',
          'tate mcrae',
          'maroon 5',
          'jennie',
          'olivia rodrigo',
          'dua lipa',
          'taylor swift'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'Tate McRae',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/ce/c8/05/cec805c6-5f81-a897-a53e-f42025b9cd5a/196874840146.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Taylor Swift',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/a0/dd/fd/a0ddfd72-ee9e-f046-6466-a5dbefc696fa/26UM1IM21436.rgb.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Maroon 5',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/d0/3e/25/d03e255d-e205-0e66-20f6-01e251896c25/14UMGIM27076.rgb.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'JENNIE',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/8d/ac/90/8dac9090-2a14-20d9-ed97-6a35ad299beb/196874620281.jpg/600x600bb.jpg',
          ),
        ],
      ),
      GenreExploreItem(
        id: 'indie_alt',
        title: 'Indie & Alt',
        gradientColors: const [Color(0xFF2563EB), Color(0xFF0D9488)],
        searchQuery: 'indie alternative rock',
        genreKeywords: [
          'indie',
          'alt',
          'hindia',
          'perunggu',
          'feast',
          'dewa 19',
          'arctic monkeys',
          'coldplay'
        ],
        candidates: const [
          GenreCandidate(
            artist: 'Hindia',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/57/f8/d2/57f8d295-5ea9-f7b2-70ff-9494ce50fc5c/cover.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Dewa 19',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music/v4/47/e3/10/47e310f4-f7e5-3d7e-b23f-d058810765e4/dewa_cintailah_cinta.jpg/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: '.Feast',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f8/db/ba/f8dbbab9-00bb-d269-b4fb-401255628ac3/1963623228970_cover.png/600x600bb.jpg',
          ),
          GenreCandidate(
            artist: 'Coldplay',
            coverUrl:
                'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f5/93/8c/f5938c49-964c-31d1-4b33-78b634f71fb7/190295978075.jpg/600x600bb.jpg',
          ),
        ],
      ),
    ];
  }

  static final Map<String, List<String>> _genreArtistMap = {
    'pop': [
      'taylor swift', 'olivia rodrigo', 'ariana grande', 'billie eilish',
      'bruno mars', 'dua lipa', 'sabrina carpenter', 'justin bieber',
      'ed sheeran', 'maroon 5', 'tate mcrae', 'jennie', 'lisa', 'rose',
      'rosé', 'harry styles', 'the weeknd', 'adele', 'katy perry',
      'shawn mendes', 'tiara andini', 'mahalini', 'lyodra', 'raisa',
      'afgan', 'isyana sarasvati', 'yura yunita', 'nadin amizah',
      'bernadya', 'charlie puth', 'sam smith', 'selena gomez', 'camila cabello',
      'bts', 'blackpink', 'newjeans', 'ive', 'aespa', 'twice', 'red velvet',
      'rihanna', 'beyonce', 'beyoncé', 'lady gaga', 'miley cyrus',
      'chappell roan', 'charli xcx', 'gracie abrams', 'troye sivan'
    ],
    'acoustic': [
      'feby putri', 'tulus', 'fourtwnty', 'raim laode', 'fiersa besari',
      'pamungkas', 'iwan fals', 'jason ranti', 'danilla', 'soegi bornean',
      'daun jatuh', 'nadin amizah', 'bernadya', 'sal priadi', 'ed sheeran',
      'john mayer', 'jack johnson', 'passenger', 'vance joy', 'kodaline',
      'james arthur', 'laufey', 'boyce avenue', 'payung teduh', 'rendy pandugo',
      'glenn fredly', 'judika', 'armada', 'virgoun', 'anji', 'budi doremi',
      'iron & wine', 'damien rice', 'bon iver', 'sufjan stevens'
    ],
    'indie_alt': [
      'hindia', '.feast', 'feast', 'perunggu', 'dewa 19', 'sheila on 7',
      'payung teduh', 'barasuara', 'efek rumah kaca', 'reality club',
      'the adams', 'danilla', 'sore', 'morfem', 'the 1975', 'arctic monkeys',
      'coldplay', 'radiohead', 'oasis', 'blur', 'the strokes', 'mac demarco',
      'men i trust', 'cigarettes after sex', 'boy pablo', 'phum viphurit',
      'wave to earth', 'wallows', 'rex orange county', 'lany', 'foster the people',
      'two door cinema club', 'phoenix', 'vampire weekend', 'mgmt', 'tame impala',
      'paramore', 'weezer', 'green day', 'blink-182', 'fall out boy',
      'my chemical romance', 'the killers', 'muse', 'gorillaz', 'foals',
      'peachy!', 'clairo', 'beabadoobee', 'cuco', 'grentperez'
    ],
    'rnb_soul': [
      'frank ocean', 'sza', 'daniel caesar', 'tyler lewis', 'steve lacy',
      'brent faiyaz', 'giveon', 'h.e.r.', 'khalid', 'kehlani', 'summer walker',
      'jhene aiko', 'jhené aiko', 'keshi', 'niki', 'joji', 'rich brian',
      'adrian khalif', 'kunto aji', 'teza sumendra', 'glenn fredly',
      'marion jola', 'rizky febian', 'bruno major', 'tom misch', 'fkj',
      'leon bridges', 'alicia keys', 'john legend', 'usher', 'the weeknd',
      'anderson .paak', 'silk sonic', 'mac miller', 'childish gambino',
      'partynextdoor', 'chloe', 'chlöe', 'snoh aalegra', 'cleo sol', 'arizona zervas'
    ],
    'electronic': [
      'tycho', 'daft punk', 'swedish house mafia', 'avicii', 'calvin harris',
      'the chainsmokers', 'martin garrix', 'kygo', 'marshmello', 'alesso',
      'david guetta', 'zedd', 'flume', 'disclosure', 'fred again..', 'fred again',
      'peggy gou', 'odesza', 'san holo', 'dipha barus', 'weird genius',
      'major lazer', 'skrillex', 'diplo', 'dj snake', 'tiesto', 'tiësto',
      'deadmau5', 'alok', 'alan walker', 'galantis', 'robin schulz',
      'porter robinson', 'madeon', 'gryffin', 'illenium', 'said the sky',
      'lost frequencies', 'bob moses', 'rufus du sol', 'rüfüs du sol', 'lane 8'
    ],
    'synthwave': [
      'daft punk', 'the weeknd', 'kavinsky', 'the midnight', 'gunship',
      'fm-84', 'fm 84', 'carpenter brut', 'com truise', 'timecop1983',
      'trevor something', 'the outfield', 'lany', 'tears for fears',
      'new order', 'depeche mode', 'm83', 'miami nights 1984', 'scandroid',
      'dynatron', 'dance with the dead', 'home', 'voyage', 'perturbator'
    ],
  };

  static bool _matchesGenre(
    GenreExploreItem g,
    String artist, {
    String? title,
    String? album,
  }) {
    final cleanA = artist.toLowerCase().trim();
    final artistList = _genreArtistMap[g.id];
    if (artistList != null) {
      for (final a in artistList) {
        if (cleanA.contains(a) || a.contains(cleanA)) {
          return true;
        }
      }
    }

    final cleanTitle = (title ?? '').toLowerCase();
    final cleanAlbum = (album ?? '').toLowerCase();

    return g.genreKeywords.any((kw) =>
        cleanA.contains(kw) ||
        cleanTitle.contains(kw) ||
        cleanAlbum.contains(kw));
  }

  /// Injects user's learned taste profile into the genre cards,
  /// placing user's played and liked artists as the primary representatives
  /// and sorting genres by user affinity.
  static List<GenreExploreItem> personalizeGenres({
    required List<String> topArtists,
    required List<Track> recentTracks,
    List<Track> likedTracks = const [],
    List<GenreExploreItem>? currentGenres,
  }) {
    final baseGenres = getDefaultGenres()
        .map((g) => g.copyWith(
              candidates: List<GenreCandidate>.from(g.candidates),
            ))
        .toList();

    // Preserve activeIndex if previous genres existed
    if (currentGenres != null) {
      final indexMap = {for (final g in currentGenres) g.id: g.activeIndex};
      for (final g in baseGenres) {
        if (indexMap.containsKey(g.id)) {
          g.activeIndex = indexMap[g.id]!;
        }
      }
    }

    final Map<String, int> genreAffinity = {};

    // 1. Analyze liked tracks (high affinity weight: 3)
    for (final track in likedTracks) {
      if (track.thumbnailUrl.isEmpty) continue;
      final cover = track.highResThumbnailUrl.isNotEmpty
          ? track.highResThumbnailUrl
          : track.thumbnailUrl;

      for (final g in baseGenres) {
        if (_matchesGenre(g, track.artist, title: track.title, album: track.album)) {
          genreAffinity[g.id] = (genreAffinity[g.id] ?? 0) + 3;

          final existingIdx = g.candidates.indexWhere(
              (c) => c.artist.toLowerCase() == track.artist.toLowerCase());
          if (existingIdx != -1) {
            g.candidates.removeAt(existingIdx);
          }
          g.candidates.insert(
            0,
            GenreCandidate(
              artist: track.artist,
              coverUrl: cover,
            ),
          );
        }
      }
    }

    // 2. Analyze user recent played tracks (weight: 1)
    for (final track in recentTracks) {
      if (track.thumbnailUrl.isEmpty) continue;
      final cover = track.highResThumbnailUrl.isNotEmpty
          ? track.highResThumbnailUrl
          : track.thumbnailUrl;

      for (final g in baseGenres) {
        if (_matchesGenre(g, track.artist, title: track.title, album: track.album)) {
          genreAffinity[g.id] = (genreAffinity[g.id] ?? 0) + 1;

          final existingIdx = g.candidates.indexWhere(
              (c) => c.artist.toLowerCase() == track.artist.toLowerCase());
          if (existingIdx != -1) {
            // Already present, leave or move up if not first
            if (existingIdx > 0 && g.candidates.first.artist.toLowerCase() != track.artist.toLowerCase()) {
              final existing = g.candidates.removeAt(existingIdx);
              g.candidates.insert(
                0,
                GenreCandidate(
                  artist: track.artist,
                  coverUrl: cover.isNotEmpty ? cover : existing.coverUrl,
                ),
              );
            }
          } else {
            g.candidates.insert(
              0,
              GenreCandidate(
                artist: track.artist,
                coverUrl: cover,
              ),
            );
          }
        }
      }
    }

    // 3. Score with top artists affinity (weight: 3)
    for (final topA in topArtists) {
      for (final g in baseGenres) {
        if (_matchesGenre(g, topA)) {
          genreAffinity[g.id] = (genreAffinity[g.id] ?? 0) + 3;
        }
      }
    }

    // 4. Sort genres so the user's highest affinity genres appear first
    baseGenres.sort((a, b) {
      final scoreA = genreAffinity[a.id] ?? 0;
      final scoreB = genreAffinity[b.id] ?? 0;
      return scoreB.compareTo(scoreA);
    });

    // Ensure activeIndex is within bounds for all candidates
    for (final g in baseGenres) {
      if (g.candidates.isNotEmpty && g.activeIndex >= g.candidates.length) {
        g.activeIndex = 0;
      }
    }

    return baseGenres;
  }
}
