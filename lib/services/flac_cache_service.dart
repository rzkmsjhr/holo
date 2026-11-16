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
  static const int minValidFlacBytes = 250 * 1024; // 250 KB minimum valid FLAC
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
      await purgeInvalidCacheFiles();
      _cleanupOldCache();
    } catch (_) {}
  }

  /// Checks whether [bytes] begins with a valid `fLaC` signature, or an
  /// ID3v2 metadata tag immediately followed by a `fLaC` stream signature.
  static bool hasFlacMagicPrefix(List<int> bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return true;
    }
    if (bytes.length >= 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final tagSize = ((bytes[6] & 0x7f) << 21) |
          ((bytes[7] & 0x7f) << 14) |
          ((bytes[8] & 0x7f) << 7) |
          (bytes[9] & 0x7f);
      final flacOffset = 10 + tagSize;
      if (bytes.length >= flacOffset + 4) {
        return bytes[flacOffset] == 0x66 &&
            bytes[flacOffset + 1] == 0x4C &&
            bytes[flacOffset + 2] == 0x61 &&
            bytes[flacOffset + 3] == 0x43;
      }
    }
    return false;
  }

  /// Validates that [file] exists, meets the 250 KB size threshold, and starts with valid FLAC magic bytes.
  static bool isValidFlacFile(File file) {
    try {
      if (!file.existsSync()) return false;
      if (file.lengthSync() < minValidFlacBytes) return false;
      final raf = file.openSync(mode: FileMode.read);
      try {
        final header = raf.readSync(16384);
        return hasFlacMagicPrefix(header);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// Purges orphaned temp files, legacy/poisoned MP3 speech stubs, and corrupt FLAC cache files.
  Future<int> purgeInvalidCacheFiles() async {
    if (kIsWeb || _cacheDir == null) return 0;
    int purged = 0;
    try {
      if (!await _cacheDir!.exists()) return 0;
      await for (final entity in _cacheDir!.list()) {
        if (entity is! File) continue;
        final lowerName = entity.path.toLowerCase();
        if (lowerName.endsWith('.tmp') ||
            lowerName.endsWith('.part') ||
            lowerName.endsWith('.mp3')) {
          try {
            await entity.delete();
            purged++;
          } catch (_) {}
          continue;
        }
        if (lowerName.endsWith('.flac') && !isValidFlacFile(entity)) {
          try {
            await entity.delete();
            purged++;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return purged;
  }

  static String sanitizeKey(String key) {
    return key
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  /// Returns path to local FLAC file if cached and valid, deleting corrupt/MP3 stubs immediately.
  String? getCachedFilePath(String trackKey) {
    if (kIsWeb || _cacheDir == null) return null;
    final safeKey = sanitizeKey(trackKey);

    final mp3Stub = File('${_cacheDir!.path}/$safeKey.mp3');
    if (mp3Stub.existsSync()) {
      try {
        mp3Stub.deleteSync();
      } catch (_) {}
    }

    final file = File('${_cacheDir!.path}/$safeKey.flac');
    if (file.existsSync()) {
      if (isValidFlacFile(file)) {
        return file.path;
      }
      try {
        file.deleteSync();
      } catch (_) {}
    }
    return null;
  }

  /// Caches FLAC stream to disk asynchronously with strict Content-Type, size, and FLAC magic verification.
  Future<String?> cacheFlacStream(String trackKey, String streamUrl) async {
    if (kIsWeb || _cacheDir == null || streamUrl.isEmpty) return null;
    final safeKey = sanitizeKey(trackKey);
    final targetFile = File('${_cacheDir!.path}/$safeKey.flac');

    if (targetFile.existsSync()) {
      if (isValidFlacFile(targetFile)) {
        return targetFile.path;
      }
      try {
        await targetFile.delete();
      } catch (_) {}
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
      final response = await HoloHttpClient.client
          .send(req)
          .timeout(const Duration(seconds: 20));

      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('audio/mpeg') ||
          contentType.contains('text/html')) {
        return null;
      }
      final contentLength = response.contentLength ?? 0;
      if (contentLength > 0 && contentLength < minValidFlacBytes) {
        return null;
      }

      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = tempFile.openWrite();
        await response.stream.pipe(sink);
        await sink.close();

        if (isValidFlacFile(tempFile)) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);
          _cleanupOldCache();
          return targetFile.path;
        } else if (await tempFile.exists()) {
          await tempFile.delete();
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

  /// Returns the total size in bytes of all cached FLAC audio files
  Future<int> getTotalCacheSizeBytes() async {
    if (kIsWeb || _cacheDir == null) return 0;
    int total = 0;
    try {
      if (await _cacheDir!.exists()) {
        final entities = await _cacheDir!.list(recursive: true).toList();
        for (final e in entities) {
          if (e is File) {
            total += await e.length();
          }
        }
      }
    } catch (_) {}
    return total;
  }

  /// Deletes all cached FLAC audio files and temporary downloads
  Future<void> clearAllCache() async {
    if (kIsWeb || _cacheDir == null) return;
    try {
      if (await _cacheDir!.exists()) {
        final entities = await _cacheDir!.list().toList();
        for (final e in entities) {
          if (e is File) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
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
