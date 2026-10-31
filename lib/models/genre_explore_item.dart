import 'package:flutter/material.dart';

class GenreCandidate {
  final String artist;
  final String coverUrl;

  const GenreCandidate({
    required this.artist,
    required this.coverUrl,
  });
}

class GenreExploreItem {
  final String id;
  final String title;
  final List<Color> gradientColors;
  final List<GenreCandidate> candidates;
  final List<String> genreKeywords;
  final String searchQuery;
  int activeIndex;

  GenreExploreItem({
    required this.id,
    required this.title,
    required this.gradientColors,
    required this.candidates,
    required this.genreKeywords,
    required this.searchQuery,
    this.activeIndex = 0,
  });

  GenreCandidate get currentCandidate =>
      candidates.isNotEmpty ? candidates[activeIndex % candidates.length] : const GenreCandidate(artist: '', coverUrl: '');

  void advance() {
    if (candidates.length > 1) {
      activeIndex = (activeIndex + 1) % candidates.length;
    }
  }

  GenreExploreItem copyWith({
    String? id,
    String? title,
    List<Color>? gradientColors,
    List<GenreCandidate>? candidates,
    List<String>? genreKeywords,
    String? searchQuery,
    int? activeIndex,
  }) {
    return GenreExploreItem(
      id: id ?? this.id,
      title: title ?? this.title,
      gradientColors: gradientColors ?? this.gradientColors,
      candidates: candidates ?? List.from(this.candidates),
      genreKeywords: genreKeywords ?? this.genreKeywords,
      searchQuery: searchQuery ?? this.searchQuery,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}
