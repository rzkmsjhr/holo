import 'track.dart';

import '../core/utils/text_encoding_utils.dart';

class TrendingTrack {
  final int rank;
  final String trend; // "=", "+2", "-1"
  final String artist;
  final String title;
  final String plays;
  final String query;
  final String? thumbnailUrl;
  final String? youtubeVideoId;

  const TrendingTrack({
    required this.rank,
    required this.trend,
    required this.artist,
    required this.title,
    required this.plays,
    required this.query,
    this.thumbnailUrl,
    this.youtubeVideoId,
  });

  factory TrendingTrack.fromMap(Map<String, dynamic> map) {
    final rawThumb = map['thumbnailUrl'] as String?;
    final cleanThumb = (rawThumb != null && !rawThumb.contains('unsplash.com')) ? rawThumb : null;
    return TrendingTrack(
      rank: map['rank'] as int? ?? 1,
      trend: map['trend'] as String? ?? '=',
      artist: TextEncodingUtils.cleanMojibake(map['artist'] as String? ?? 'Unknown Artist'),
      title: TextEncodingUtils.cleanMojibake(map['title'] as String? ?? 'Unknown Title'),
      plays: map['plays'] as String? ?? '0',
      query: TextEncodingUtils.cleanMojibake(map['query'] as String? ?? ''),
      thumbnailUrl: cleanThumb,
      youtubeVideoId: map['youtubeVideoId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rank': rank,
      'trend': trend,
      'artist': artist,
      'title': title,
      'plays': plays,
      'query': query,
      'thumbnailUrl': thumbnailUrl,
      'youtubeVideoId': youtubeVideoId,
    };
  }

  String get formattedPlays {
    final clean = plays.replaceAll(',', '').replaceAll('.', '').trim();
    final num = int.tryParse(clean);
    if (num == null) return '$plays plays';
    if (num >= 1000000) {
      final m = num / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 1 : 2)}M plays';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(0)}K plays';
    }
    return '$num plays';
  }

  String get formattedPlaysNumber {
    final clean = plays.replaceAll(',', '').replaceAll('.', '').trim();
    final num = int.tryParse(clean);
    if (num == null) return plays;
    if (num >= 1000000) {
      final m = num / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 1 : 2)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(0)}K';
    }
    return '$num';
  }

  TrendingTrack copyWith({
    int? rank,
    String? trend,
    String? artist,
    String? title,
    String? plays,
    String? query,
    String? thumbnailUrl,
    String? youtubeVideoId,
  }) {
    return TrendingTrack(
      rank: rank ?? this.rank,
      trend: trend ?? this.trend,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      plays: plays ?? this.plays,
      query: query ?? this.query,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
    );
  }

  Track toTrack({String? audioSource}) {
    return Track(
      id: youtubeVideoId ?? 'trending_$rank',
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl ?? '',
      durationSeconds: 210,
      youtubeVideoId: youtubeVideoId,
      audioSource: audioSource ?? 'youtube',
      isLossless: false,
      extraData: const {'itemType': 'song'},
    );
  }
}
