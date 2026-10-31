import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../models/genre_explore_item.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../services/genre_explore_service.dart';
import '../../services/youtube_music_service.dart';
import '../widgets/add_to_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final YouTubeMusicService _ytmService = YouTubeMusicService();

  bool _isLoading = false;
  List<Track>? _searchResults = [];
  String? _lastQuery = '';
  String? _errorMessage;

  List<String>? _recentQueries = [];
  List<GenreExploreItem>? _genres;
  Timer? _backgroundCycleTimer;

  List<Track> get _safeSearchResults => _searchResults ??= [];
  String get _safeLastQuery => _lastQuery ??= '';
  List<String> get _safeRecentQueries => _recentQueries ??= [];
  List<GenreExploreItem> get _safeGenres {
    if (_genres == null || _genres!.isEmpty) {
      _genres = GenreExploreService.getDefaultGenres();
    }
    return _genres!;
  }

  @override
  void initState() {
    super.initState();
    _loadRecentQueries();
    _genres = GenreExploreService.getDefaultGenres();

    // Dynamically cycle through candidate artists for genre backgrounds
    _backgroundCycleTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) {
        setState(() {
          for (final g in _safeGenres) {
            g.advance();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _backgroundCycleTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('recent_search_queries');
      if (list != null && list.isNotEmpty) {
        setState(() {
          _recentQueries = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRecentQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final list = _safeRecentQueries;
    list.removeWhere((q) => q.toLowerCase() == clean.toLowerCase());
    list.insert(0, clean);
    if (list.length > 8) {
      _recentQueries = list.sublist(0, 8);
    }
    setState(() {});

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recent_search_queries', _safeRecentQueries);
    } catch (_) {}
  }

  Future<void> _removeRecentQuery(String query) async {
    setState(() {
      _safeRecentQueries.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recent_search_queries', _safeRecentQueries);
    } catch (_) {}
  }

  Future<void> _clearAllRecentQueries() async {
    setState(() {
      _safeRecentQueries.clear();
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_search_queries');
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    _saveRecentQuery(clean);

    setState(() {
      _isLoading = true;
      _lastQuery = clean;
      _errorMessage = null;
    });

    try {
      final results = await _ytmService.searchSongs(clean);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to complete search. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dynamically personalize explore genres using the taste system
    _genres = GenreExploreService.personalizeGenres(
      topArtists: player.topArtists,
      recentTracks: player.recentlyPlayed,
      currentGenres: _genres,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Search',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),

            // Search Bar Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums...',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _safeSearchResults.clear();
                              _lastQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor:
                      isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_off_rounded,
                                  size: 40,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Search unavailable',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () =>
                                      _performSearch(_safeLastQuery),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _safeSearchResults.isNotEmpty
                          ? ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 130),
                              itemCount: _safeSearchResults.length,
                              itemBuilder: (context, index) {
                                final track = _safeSearchResults[index];
                                final isCurrent =
                                    player.currentTrack?.id == track.id;
                                return _buildResultTile(
                                    context, track, isCurrent, player);
                              },
                            )
                          : _safeLastQuery.isNotEmpty
                              ? Center(
                                  child: Text(
                                    'No results found for "$_safeLastQuery"',
                                    style: TextStyle(
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                )
                              : _buildExploreAndRecentView(
                                  context, player, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreAndRecentView(
      BuildContext context, PlayerProvider player, bool isDark) {
    final recent = _safeRecentQueries;
    final genresList = _safeGenres;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 130),
      children: [
        // 1. Recent Searches Section
        if (recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              GestureDetector(
                onTap: _clearAllRecentQueries,
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recent.take(5).map((q) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface.withValues(alpha: 0.6)
                      : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  leading: Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                  title: Text(
                    q,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _removeRecentQuery(q),
                  ),
                  onTap: () {
                    _searchController.text = q;
                    _performSearch(q);
                  },
                ),
              )),
          const SizedBox(height: 18),
        ],

        // 2. Explore Genres Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Explore Genres',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            if (player.topArtists.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Based on your taste',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 3. Exact 2-Column Grid of Genre Cards with Dynamic Artist Backgrounds
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.75,
          ),
          itemCount: genresList.length,
          itemBuilder: (context, index) {
            final genre = genresList[index];
            return _buildGenreCard(genre, isDark);
          },
        ),
      ],
    );
  }

  Widget _buildGenreCard(GenreExploreItem genre, bool isDark) {
    final candidate = genre.currentCandidate;

    return GestureDetector(
      onTap: () {
        _searchController.text = genre.title;
        _performSearch(genre.searchQuery);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Dynamic Artist Background with Cross-fade Animation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: candidate.coverUrl.isNotEmpty
                    ? Image.network(
                        candidate.coverUrl,
                        key: ValueKey('${genre.id}_${candidate.artist}'),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: genre.gradientColors.first,
                        ),
                      )
                    : Container(
                        key: ValueKey('${genre.id}_empty'),
                        color: genre.gradientColors.first,
                      ),
              ),

              // 2. Color Gradient Overlay with Contrast Protection
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      genre.gradientColors[0].withValues(alpha: 0.45),
                      genre.gradientColors[1].withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

              // 3. Dark Bottom Vignette for Artist Name Readability
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // 4. Card Content: Genre Title & Dynamic Artist Badge
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Genre Title
                    Text(
                      genre.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),

                    // Representative Artist Attribution
                    if (candidate.artist.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.album_rounded,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              candidate.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(BuildContext context, Track track, bool isCurrent,
      PlayerProvider player) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      onTap: () {
        player.playTrack(track);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: isCurrent
          ? (isDark ? AppColors.darkSurface : AppColors.lightSurface)
          : Colors.transparent,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 46,
          height: 46,
          color: AppColors.secondary,
          child: track.thumbnailUrl.isNotEmpty
              ? Image.network(
                  track.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.music_note, color: Colors.white),
                )
              : const Icon(Icons.music_note, color: Colors.white),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isCurrent ? AppColors.primary : null,
              ),
            ),
          ),
          if (track.isLossless) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'FLAC',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A0C10),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            track.formattedDuration,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => showAddToSheet(context, track: track),
          ),
        ],
      ),
    );
  }
}
