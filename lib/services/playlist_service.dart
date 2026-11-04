import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class PlaylistService {
  static const String _storageKey = 'user_saved_playlists';
  List<Playlist> _cachedPlaylists = [];
  bool _isLoaded = false;

  /// Loads all saved playlists from local storage
  Future<List<Playlist>> loadPlaylists({List<Track>? sampleCatalog}) async {
    if (_isLoaded && _cachedPlaylists.isNotEmpty) {
      return _cachedPlaylists;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _cachedPlaylists = decoded
            .map((item) => Playlist.fromMap(item as Map<String, dynamic>))
            .toList();
        _isLoaded = true;
        return _cachedPlaylists;
      }
    } catch (_) {}

    // First run / starter playlist if nothing saved
    _cachedPlaylists = _createDefaultStarterPlaylists(sampleCatalog ?? []);
    await _saveToStorage();
    _isLoaded = true;
    return _cachedPlaylists;
  }

  /// Creates a new user playlist
  Future<Playlist> createPlaylist(
    String title, {
    String description = '',
    List<Track>? initialTracks,
    String? coverUrl,
  }) async {
    final cleanTitle = title.trim();
    final newId = 'playlist_${DateTime.now().millisecondsSinceEpoch}';
    final tracks = initialTracks != null ? List<Track>.from(initialTracks) : <Track>[];
    final cover = (coverUrl != null && coverUrl.isNotEmpty)
        ? coverUrl
        : (tracks.isNotEmpty ? tracks.first.highResThumbnailUrl : null);

    final newPlaylist = Playlist(
      id: newId,
      title: cleanTitle.isNotEmpty ? cleanTitle : 'My Playlist',
      description: description,
      tracks: tracks,
      coverUrl: cover,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _cachedPlaylists.insert(0, newPlaylist);
    await _saveToStorage();
    return newPlaylist;
  }

  /// Updates an existing playlist
  Future<void> updatePlaylist(Playlist updated) async {
    final index = _cachedPlaylists.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _cachedPlaylists[index] = updated.copyWith(updatedAt: DateTime.now());
      await _saveToStorage();
    }
  }

  /// Renames a playlist
  Future<void> renamePlaylist(String playlistId, String newTitle) async {
    final clean = newTitle.trim();
    if (clean.isEmpty) return;

    final index = _cachedPlaylists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final current = _cachedPlaylists[index];
      _cachedPlaylists[index] = current.copyWith(title: clean);
      await _saveToStorage();
    }
  }

  /// Deletes a playlist
  Future<void> deletePlaylist(String playlistId) async {
    _cachedPlaylists.removeWhere((p) => p.id == playlistId);
    await _saveToStorage();
  }

  /// Adds a track to a playlist. Returns true if added, false if already in playlist.
  Future<bool> addTrackToPlaylist(String playlistId, Track track) async {
    final index = _cachedPlaylists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;

    final current = _cachedPlaylists[index];
    final trackId = track.youtubeVideoId ?? track.id;

    // Check if already in playlist
    final alreadyExists = current.tracks.any(
        (t) => (t.youtubeVideoId ?? t.id) == trackId);
    if (alreadyExists) return false;

    final updatedTracks = List<Track>.from(current.tracks)..add(track);
    final cover = current.coverUrl ?? track.highResThumbnailUrl;

    _cachedPlaylists[index] = current.copyWith(
      tracks: updatedTracks,
      coverUrl: cover,
    );

    await _saveToStorage();
    return true;
  }

  /// Removes a track from a playlist
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final index = _cachedPlaylists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final current = _cachedPlaylists[index];
    final updatedTracks = current.tracks
        .where((t) => (t.youtubeVideoId ?? t.id) != trackId)
        .toList();

    final cover = updatedTracks.isNotEmpty
        ? updatedTracks.first.highResThumbnailUrl
        : null;

    _cachedPlaylists[index] = current.copyWith(
      tracks: updatedTracks,
      coverUrl: cover,
    );

    await _saveToStorage();
  }

  /// Reorders tracks in a playlist
  Future<void> reorderTracksInPlaylist(
      String playlistId, int oldIndex, int newIndex) async {
    final index = _cachedPlaylists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final current = _cachedPlaylists[index];
    final tracks = List<Track>.from(current.tracks);
    if (tracks.isEmpty || oldIndex < 0 || oldIndex >= tracks.length) {
      return;
    }
    final targetIndex = newIndex.clamp(0, tracks.length - 1);
    if (oldIndex == targetIndex) return;

    final item = tracks.removeAt(oldIndex);
    tracks.insert(targetIndex, item);

    _cachedPlaylists[index] = current.copyWith(tracks: tracks);
    await _saveToStorage();
  }

  List<Playlist> _createDefaultStarterPlaylists(List<Track> catalog) {
    if (catalog.isEmpty) return [];

    return [
      Playlist(
        id: 'starter_late_night_drive',
        title: 'Late Night Drive',
        description: 'Mellow nighttime vibes and heavy rotation',
        tracks: List.from(catalog),
        coverUrl: catalog.first.highResThumbnailUrl,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Playlist(
        id: 'starter_favorites',
        title: 'Favorites',
        description: 'Your favorite tracks in one place',
        tracks: catalog.take(3).toList(),
        coverUrl: catalog.length > 1 ? catalog[1].highResThumbnailUrl : null,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final maps = _cachedPlaylists.map((p) => p.toMap()).toList();
      await prefs.setString(_storageKey, jsonEncode(maps));
    } catch (_) {}
  }
}
