import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/network/holo_http_client.dart';

class FlacCacheService {
  static final FlacCacheService _instance = FlacCacheService._internal();
  factory FlacCacheService() => _instance;
  FlacCacheService._internal();

  Directory? _cacheDir;
  bool _isInitialized = false;
  final Set<String> _downloadingKeys = {};
  static const int _maxCacheSizeBytes = 500 * 1024 * 1024; // 500 MB max

  Future<void> init() async {
    if (_isInitialized || kIsWeb) return;
    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${baseDir.path}/flac_audio_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _isInitialized = true;
      _cleanupOldCache();
    } catch (_) {}
  }

  static String sanitizeKey(String key) {
    return key
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  /// Returns path to local FLAC file if cached and valid
  String? getCachedFilePath(String trackKey) {
    if (kIsWeb || _cacheDir == null) return null;
    final safeKey = sanitizeKey(trackKey);
    final file = File('${_cacheDir!.path}/$safeKey.flac');
    if (file.existsSync()) {
      final len = file.lengthSync();
      // Valid FLAC must be at least 100KB
      if (len > 100 * 1024) {
        return file.path;
      }
    }
    return null;
  }

  /// Caches FLAC stream to disk asynchronously
  Future<String?> cacheFlacStream(String trackKey, String streamUrl) async {
    if (kIsWeb || _cacheDir == null || streamUrl.isEmpty) return null;
    final safeKey = sanitizeKey(trackKey);
    final targetFile = File('${_cacheDir!.path}/$safeKey.flac');

    if (targetFile.existsSync() && targetFile.lengthSync() > 100 * 1024) {
      return targetFile.path;
    }

    if (_downloadingKeys.contains(safeKey)) {
      return null;
    }
    _downloadingKeys.add(safeKey);

    final tempFile = File('${_cacheDir!.path}/$safeKey.tmp');

    try {
      final req = http.Request('GET', Uri.parse(streamUrl));
      req.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      final response = await HoloHttpClient.client.send(req).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = tempFile.openWrite();
        await response.stream.pipe(sink);
        await sink.close();

        if (await tempFile.exists()) {
          final bytes = await tempFile.openRead(0, 4).first;
          // Verify FLAC magic header 'fLaC' (0x66, 0x4C, 0x61, 0x43)
          final isFlac = bytes.length >= 4 &&
              bytes[0] == 0x66 &&
              bytes[1] == 0x4C &&
              bytes[2] == 0x61 &&
              bytes[3] == 0x43;

          if (isFlac && await tempFile.length() > 100 * 1024) {
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            await tempFile.rename(targetFile.path);
            _cleanupOldCache();
            return targetFile.path;
          } else {
            await tempFile.delete();
          }
        }
      }
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } finally {
      _downloadingKeys.remove(safeKey);
    }
    return null;
  }

  Future<void> _cleanupOldCache() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;
    try {
      final entities = await _cacheDir!.list().toList();
      final files = entities.whereType<File>().toList();

      int totalSize = 0;
      for (final f in files) {
        totalSize += await f.length();
      }

      if (totalSize > _maxCacheSizeBytes) {
        files.sort((a, b) =>
            a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (final f in files) {
          if (totalSize <= (_maxCacheSizeBytes * 0.75)) break;
          final len = await f.length();
          await f.delete();
          totalSize -= len;
        }
      }
    } catch (_) {}
  }
}
