import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeStreamResolver {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Resolves the highest quality direct audio stream URL for a YouTube video
  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final cleanId = videoId.trim();
      if (cleanId.isEmpty) return null;

      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId)
          .timeout(const Duration(seconds: 8));
      final audioStream = manifest.audioOnly.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
