import '../core/utils/text_encoding_utils.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String thumbnailUrl;
  final int durationSeconds;
  final bool isExplicit;
  final String? youtubeVideoId;
  final String? flacStreamUrl;
  final String? audioSource; // 'youtube', 'monochrome', 'kuwo'
  final bool isLossless;
  final String? audioFormat; // e.g. "24-bit • 96kHz Lossless FLAC"
  final Map<String, dynamic>? extraData;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    required this.thumbnailUrl,
    required this.durationSeconds,
    this.isExplicit = false,
    this.youtubeVideoId,
    this.flacStreamUrl,
    this.audioSource = 'youtube',
    this.isLossless = false,
    this.audioFormat,
    this.extraData,
  });

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Upgrades any thumbnail URL to its highest definition master resolution
  static String toHighResUrl(String? url) {
    if (url == null || url.isEmpty || url.contains('unsplash.com')) return '';
    var highRes = url;
    if (highRes.contains('googleusercontent.com')) {
      highRes = highRes.replaceAll(RegExp(r'=w\d+-h\d+'), '=w1080-h1080');
      highRes = highRes.replaceAll(RegExp(r'=s\d+'), '=s1080');
    } else if (highRes.contains('ytimg.com')) {
      highRes = highRes.replaceAll(
          RegExp(r'/(?:default|mqdefault|hqdefault|sddefault)\.jpg'),
          '/maxresdefault.jpg');
    }
    return highRes;
  }

  String get highResThumbnailUrl => toHighResUrl(thumbnailUrl);

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? thumbnailUrl,
    int? durationSeconds,
    bool? isExplicit,
    String? youtubeVideoId,
    String? flacStreamUrl,
    String? audioSource,
    bool? isLossless,
    String? audioFormat,
    Map<String, dynamic>? extraData,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isExplicit: isExplicit ?? this.isExplicit,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      flacStreamUrl: flacStreamUrl ?? this.flacStreamUrl,
      audioSource: audioSource ?? this.audioSource,
      isLossless: isLossless ?? this.isLossless,
      audioFormat: audioFormat ?? this.audioFormat,
      extraData: extraData ?? this.extraData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'isExplicit': isExplicit,
      'youtubeVideoId': youtubeVideoId,
      'flacStreamUrl': flacStreamUrl,
      'audioSource': audioSource,
      'isLossless': isLossless,
      'audioFormat': audioFormat,
      'extraData': extraData,
    };
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    final rawThumb = json['thumbnailUrl'] as String? ?? '';
    final cleanThumb = rawThumb.contains('unsplash.com') ? '' : rawThumb;
    return Track(
      id: json['id'] as String,
      title: TextEncodingUtils.cleanMojibake(json['title'] as String),
      artist: TextEncodingUtils.cleanMojibake(json['artist'] as String),
      album: TextEncodingUtils.cleanMojibake(json['album'] as String? ?? ''),
      thumbnailUrl: cleanThumb,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      isExplicit: json['isExplicit'] as bool? ?? false,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      flacStreamUrl: json['flacStreamUrl'] as String?,
      audioSource: json['audioSource'] as String? ?? 'youtube',
      isLossless: json['isLossless'] as bool? ?? false,
      audioFormat: json['audioFormat'] as String?,
      extraData: json['extraData'] as Map<String, dynamic>?,
    );
  }
}
