import 'track.dart';

class ArtistRelease {
  final String title;
  final String year;
  final String type; // Album, Single, EP
  final String browseId;
  final String thumbnailUrl;

  const ArtistRelease({
    required this.title,
    required this.year,
    required this.type,
    required this.browseId,
    required this.thumbnailUrl,
  });

  String get highResThumbnailUrl => Track.toHighResUrl(thumbnailUrl);
}

class ArtistDetails {
  final String name;
  final String browseId;
  final String? bannerUrl;
  final String? avatarUrl;
  final String? subscribers;
  final String? monthlyAudience;
  final String? bio;
  final String? wikiUrl;
  final String? totalViews;
  final List<Track> topSongs;
  final String? topSongsPlaylistId;
  final List<ArtistRelease> albums;
  final List<ArtistRelease> singles;
  final bool hasLoadedAllSongs;

  const ArtistDetails({
    required this.name,
    required this.browseId,
    this.bannerUrl,
    this.avatarUrl,
    this.subscribers,
    this.monthlyAudience,
    this.bio,
    this.wikiUrl,
    this.totalViews,
    required this.topSongs,
    this.topSongsPlaylistId,
    this.albums = const [],
    this.singles = const [],
    this.hasLoadedAllSongs = false,
  });

  String get effectiveImage {
    if (bannerUrl != null && bannerUrl!.isNotEmpty) {
      return Track.toHighResUrl(bannerUrl!);
    }
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Track.toHighResUrl(avatarUrl!);
    }
    return '';
  }

  ArtistDetails copyWith({
    String? name,
    String? browseId,
    String? bannerUrl,
    String? avatarUrl,
    String? subscribers,
    String? monthlyAudience,
    String? bio,
    String? wikiUrl,
    String? totalViews,
    List<Track>? topSongs,
    String? topSongsPlaylistId,
    List<ArtistRelease>? albums,
    List<ArtistRelease>? singles,
    bool? hasLoadedAllSongs,
  }) {
    return ArtistDetails(
      name: name ?? this.name,
      browseId: browseId ?? this.browseId,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      subscribers: subscribers ?? this.subscribers,
      monthlyAudience: monthlyAudience ?? this.monthlyAudience,
      bio: bio ?? this.bio,
      wikiUrl: wikiUrl ?? this.wikiUrl,
      totalViews: totalViews ?? this.totalViews,
      topSongs: topSongs ?? this.topSongs,
      topSongsPlaylistId: topSongsPlaylistId ?? this.topSongsPlaylistId,
      albums: albums ?? this.albums,
      singles: singles ?? this.singles,
      hasLoadedAllSongs: hasLoadedAllSongs ?? this.hasLoadedAllSongs,
    );
  }
}
