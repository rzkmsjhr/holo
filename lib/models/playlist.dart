import 'track.dart';

class Playlist {
  final String id;
  final String title;
  final String description;
  final List<Track> tracks;
  final String? coverUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.title,
    this.description = '',
    List<Track>? tracks,
    this.coverUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tracks = tracks ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get formattedDuration {
    final totalSecs =
        tracks.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    if (totalSecs == 0) return '0 min';
    final hrs = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    if (hrs > 0) {
      return '$hrs hr ${mins > 0 ? "$mins min" : ""}';
    }
    return '$mins min';
  }

  String get formattedTrackCount =>
      '${tracks.length} ${tracks.length == 1 ? "song" : "songs"}';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String? ??
          'playlist_${DateTime.now().millisecondsSinceEpoch}',
      title: map['title'] as String? ?? 'Untitled Playlist',
      description: map['description'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt']) ?? DateTime.now()
          : DateTime.now(),
      tracks: (map['tracks'] as List?)
              ?.map((item) => Track.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    List<Track>? tracks,
    String? coverUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tracks: tracks ?? List.from(this.tracks),
      coverUrl: coverUrl ?? this.coverUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
