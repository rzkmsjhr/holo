import 'package:flutter/material.dart';
import 'track.dart';

class DailyMix {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String coverUrl;
  final List<Color> gradientColors;
  final List<Track> tracks;
  final String? seedArtist;

  const DailyMix({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.coverUrl,
    required this.gradientColors,
    required this.tracks,
    this.seedArtist,
  });

  DailyMix copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? badge,
    String? coverUrl,
    List<Color>? gradientColors,
    List<Track>? tracks,
    String? seedArtist,
  }) {
    return DailyMix(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      badge: badge ?? this.badge,
      coverUrl: coverUrl ?? this.coverUrl,
      gradientColors: gradientColors ?? this.gradientColors,
      tracks: tracks ?? this.tracks,
      seedArtist: seedArtist ?? this.seedArtist,
    );
  }
}
