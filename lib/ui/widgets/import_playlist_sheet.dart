import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../services/playlist_import_service.dart';
import '../screens/playlist_detail_screen.dart';
import 'holo_image.dart';

Future<void> showImportPlaylistSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const ImportPlaylistSheet(),
  );
}

class ImportPlaylistSheet extends StatefulWidget {
  const ImportPlaylistSheet({super.key});

  @override
  State<ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

class _ImportPlaylistSheetState extends State<ImportPlaylistSheet> {
  final TextEditingController _urlController = TextEditingController();
  bool _isImporting = false;
  String? _clipboardCandidate;
  ParsedPlaylistUrl? _detectedFromClipboard;
  ParsedPlaylistUrl? _detectedFromInput;

  // Progress state
  int _importProgressCurrent = 0;
  int _importProgressTotal = 0;
  String _currentImportTrack = '';

  // Result state
  Playlist? _createdPlaylist;
  PlaylistImportResult? _importResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onInputChanged);
    _checkClipboard();
  }

  @override
  void dispose() {
    _urlController.removeListener(_onInputChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      if (_detectedFromInput != null) {
        setState(() => _detectedFromInput = null);
      } else {
        setState(() {});
      }
      return;
    }
    final parsed = PlaylistImportService.parsePlaylistUrl(text);
    if (parsed != _detectedFromInput) {
      setState(() {
        _detectedFromInput = parsed;
        _errorMessage = null;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        final parsed = PlaylistImportService.parsePlaylistUrl(text);
        if (parsed != null && mounted) {
          setState(() {
            _clipboardCandidate = text;
            _detectedFromClipboard = parsed;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _startImport(String url) async {
    if (_isImporting) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _createdPlaylist = null;
      _importResult = null;
      _importProgressCurrent = 0;
      _importProgressTotal = 0;
      _currentImportTrack = '';
    });

    final player = context.read<PlayerProvider>();

    try {
      final (created, result) = await player.importPlaylistFromUrl(
        url,
        onProgress: (current, total, trackName) {
          if (mounted) {
            setState(() {
              _importProgressCurrent = current;
              _importProgressTotal = total;
              _currentImportTrack = trackName;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isImporting = false;
          _createdPlaylist = created;
          _importResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          final errStr = e.toString().replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
          _errorMessage = errStr.isNotEmpty
              ? errStr
              : 'Failed to import playlist. Please verify the link is public.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14171F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Row
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import Playlist',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _buildPlatformBadge(
                              'YouTube',
                              const Color(0xFFFF0000),
                              Icons.play_arrow_rounded,
                              isDark,
                            ),
                            const SizedBox(width: 6),
                            _buildPlatformBadge(
                              'Spotify',
                              const Color(0xFF1DB954),
                              Icons.album_rounded,
                              isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _isImporting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // View Modes: Result Success vs Progress vs Input
              if (_createdPlaylist != null && _importResult != null)
                _buildSuccessView(context, isDark)
              else if (_isImporting)
                _buildImportingProgressView(isDark)
              else ...[
                // 1-Tap Clipboard Card (Convenience)
                if (_clipboardCandidate != null && _detectedFromClipboard != null)
                  _buildClipboardCard(isDark),

                // Manual Input Field
                _buildUrlInputField(isDark),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Import Button
                ElevatedButton(
                  onPressed: _urlController.text.trim().isEmpty || _isImporting
                      ? null
                      : () => _startImport(_urlController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.lightSurfaceElevated,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Import Playlist',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformBadge(
    String label,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardCard(bool isDark) {
    final isSpotify =
        _detectedFromClipboard?.platform == PlaylistPlatform.spotify;
    final color = isSpotify ? const Color(0xFF1DB954) : const Color(0xFFFF0000);
    final platformName = isSpotify ? 'Spotify' : 'YouTube';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _urlController.text = _clipboardCandidate!;
            _startImport(_clipboardCandidate!);
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isSpotify ? Icons.album_rounded : Icons.play_arrow_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              platformName,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Found in Clipboard',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _clipboardCandidate!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _urlController.text = _clipboardCandidate!;
                    _startImport(_clipboardCandidate!);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14),
                      SizedBox(width: 3),
                      Text(
                        'Import',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUrlInputField(bool isDark) {
    final detected = _detectedFromInput;
    final isSpotify = detected?.platform == PlaylistPlatform.spotify;
    final isYoutube = detected?.platform == PlaylistPlatform.youtube;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _urlController,
          enabled: !_isImporting,
          autofocus: _clipboardCandidate == null,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'Paste YouTube or Spotify playlist link',
            hintStyle: TextStyle(
              fontSize: 13.5,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceElevated
                : AppColors.lightSurfaceElevated,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            suffixIcon: _urlController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: () => _urlController.clear(),
                  )
                : IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _urlController.text = data!.text!.trim();
                      }
                    },
                  ),
          ),
        ),

        // Live Platform Detection Indicator
        if (isSpotify || isYoutube) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: isSpotify
                    ? const Color(0xFF1DB954)
                    : const Color(0xFFFF0000),
              ),
              const SizedBox(width: 5),
              Text(
                isSpotify
                    ? 'Valid Spotify Playlist detected'
                    : 'Valid YouTube Playlist detected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSpotify
                      ? const Color(0xFF1DB954)
                      : const Color(0xFFFF0000),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildImportingProgressView(bool isDark) {
    final isSpotify = _detectedFromInput?.platform == PlaylistPlatform.spotify ||
        _detectedFromClipboard?.platform == PlaylistPlatform.spotify;
    final platformName = isSpotify ? 'Spotify' : 'YouTube';
    final progress = _importProgressTotal > 0
        ? _importProgressCurrent / _importProgressTotal
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Importing from $platformName...',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (_importProgressTotal > 0) ...[
            Text(
              'Matched $_importProgressCurrent / $_importProgressTotal songs',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceElevated,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            if (_currentImportTrack.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _currentImportTrack,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ] else ...[
            Text(
              'Fetching playlist metadata and tracks...',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context, bool isDark) {
    final playlist = _createdPlaylist!;
    final result = _importResult!;
    final cover = playlist.coverUrl ??
        (playlist.tracks.isNotEmpty ? playlist.tracks.first.highResThumbnailUrl : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success Header Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1D212C) : AppColors.lightSurfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: AppColors.primary,
                  child: cover.isNotEmpty
                      ? HoloImage(cover, fit: BoxFit.cover)
                      : const Icon(
                          Icons.queue_music_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF38EF7D),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Import Complete',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF38EF7D),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${playlist.tracks.length} tracks imported',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Unmatched tracks warning (if any)
        if (result.unmatchedTrackNames.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.25),
              ),
            ),
            child: ExpansionTile(
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              leading: const Icon(
                Icons.info_outline_rounded,
                color: Colors.orangeAccent,
                size: 20,
              ),
              title: Text(
                '${result.unmatchedTrackNames.length} tracks could not be matched',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.orangeAccent,
                ),
              ),
              subtitle: const Text(
                'Tap to see omitted tracks',
                style: TextStyle(fontSize: 11),
              ),
              children: result.unmatchedTrackNames
                  .take(15)
                  .map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• $t',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Action Buttons: Play Now & View Playlist
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'View Playlist',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: playlist.tracks.isEmpty
                    ? null
                    : () {
                        final player = context.read<PlayerProvider>();
                        Navigator.of(context).pop();
                        player.playPlaylist(playlist, 0);
                      },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Play Now',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
