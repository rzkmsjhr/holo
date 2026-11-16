import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:holo_music_player/models/track.dart';
import 'package:holo_music_player/services/flac_cache_service.dart';
import 'package:holo_music_player/services/hifi_matcher.dart';
import 'package:holo_music_player/services/kuwo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hi-Fi v14 Resilience Tests (Nadanada parity 3f2cc9e – 13bdbc3)', () {
    test('KuwoService.isValidHiCnFlacUrl rejects MP3 copyright stubs and lossy URLs', () {
      expect(
        KuwoService.isValidHiCnFlacUrl(
          'https://other-bj.kuwo.cn/34c288b39e70c5728267cf14c5983716/6afa9d6c/lx/resource/n3/11/77/2044590383.mp3',
        ),
        isFalse,
      );
      expect(
        KuwoService.isValidHiCnFlacUrl(
          'https://cdn.example.com/lx/resource/notice?token=abc',
        ),
        isFalse,
      );
      expect(
        KuwoService.isValidHiCnFlacUrl('https://cdn.example.com/track.m4a?sig=1'),
        isFalse,
      );
      expect(KuwoService.isValidHiCnFlacUrl(''), isFalse);

      expect(
        KuwoService.isValidHiCnFlacUrl(
          'https://other-er.kuwo.cn/9d4fda467795f69eb793ee2a87beaf52/6afa9f24/resource/1307392909/trackmedia/F000002PNeqX10lTZr.flac',
        ),
        isTrue,
      );
      expect(
        KuwoService.isValidHiCnFlacUrl(
          'https://m704.music.126.net/20261116/hash/stream.flac?auth=xyz',
        ),
        isTrue,
      );
    });

    test('FlacCacheService.hasFlacMagicPrefix accepts raw fLaC and ID3v2-prefixed fLaC only', () {
      expect(FlacCacheService.minValidFlacBytes, equals(250 * 1024));

      // Raw fLaC header
      expect(
        FlacCacheService.hasFlacMagicPrefix([0x66, 0x4C, 0x61, 0x43, 0x00, 0x00]),
        isTrue,
      );

      // ID3v2 header of 4 bytes payload (synchsafe 0,0,0,4) followed by fLaC
      final id3Flac = <int>[
        0x49, 0x44, 0x33, // ID3
        0x03, 0x00, 0x00, // version & flags
        0x00, 0x00, 0x00, 0x04, // synchsafe size = 4
        0x01, 0x02, 0x03, 0x04, // 4 bytes ID3 body
        0x66, 0x4C, 0x61, 0x43, // fLaC
      ];
      expect(FlacCacheService.hasFlacMagicPrefix(id3Flac), isTrue);

      // MP3 sync word or HTML response
      expect(
        FlacCacheService.hasFlacMagicPrefix([0xFF, 0xFB, 0x90, 0x64]),
        isFalse,
      );
      expect(
        FlacCacheService.hasFlacMagicPrefix(utf8.encode('<html>403 Forbidden</html>')),
        isFalse,
      );
      expect(FlacCacheService.hasFlacMagicPrefix([0x66, 0x4C]), isFalse);
    });

    test('FlacCacheService.isValidFlacFile rejects undersized and corrupt files', () async {
      final tempDir = await Directory.systemTemp.createTemp('holo_flac_test_');
      try {
        // Undersized (76 KB) Kuwo copyright stub even with fLaC bytes
        final smallFile = File('${tempDir.path}/stub.flac');
        final smallBytes = List<int>.filled(80 * 1024, 0);
        smallBytes[0] = 0x66;
        smallBytes[1] = 0x4C;
        smallBytes[2] = 0x61;
        smallBytes[3] = 0x43;
        await smallFile.writeAsBytes(smallBytes);
        expect(FlacCacheService.isValidFlacFile(smallFile), isFalse);

        // Large MP3 disguised as .flac
        final mp3File = File('${tempDir.path}/fake.flac');
        final mp3Bytes = List<int>.filled(260 * 1024, 0);
        mp3Bytes[0] = 0xFF;
        mp3Bytes[1] = 0xFB;
        await mp3File.writeAsBytes(mp3Bytes);
        expect(FlacCacheService.isValidFlacFile(mp3File), isFalse);

        // Valid 260 KB fLaC file
        final validFile = File('${tempDir.path}/valid.flac');
        final validBytes = List<int>.filled(260 * 1024, 0);
        validBytes[0] = 0x66;
        validBytes[1] = 0x4C;
        validBytes[2] = 0x61;
        validBytes[3] = 0x43;
        await validFile.writeAsBytes(validBytes);
        expect(FlacCacheService.isValidFlacFile(validFile), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('HifiMatcher v14 evicts poisoned Kuwo MP3 cache URLs and removes legacy v13 key', () async {
      final poisonedTrack = Track(
        id: 'poisoned_track_1',
        title: 'Poisoned Song',
        artist: 'Some Artist',
        thumbnailUrl: '',
        durationSeconds: 200,
        flacStreamUrl:
            'https://other-bj.kuwo.cn/hash/lx/resource/n3/11/77/2044590383.mp3',
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC',
        extraData: const {'hifiId': 'kuwo_999', 'hifiVersion': 14},
      );

      final validTrack = Track(
        id: 'valid_v14_track_1',
        title: 'Clean Song',
        artist: 'Clean Artist',
        thumbnailUrl: '',
        durationSeconds: 210,
        flacStreamUrl:
            'https://other-er.kuwo.cn/hash/resource/trackmedia/clean.flac',
        audioSource: 'kuwo',
        isLossless: true,
        audioFormat: '16-bit • 44.1kHz Lossless FLAC',
        extraData: const {'hifiId': 'kuwo_1000', 'hifiVersion': 14},
      );

      SharedPreferences.setMockInitialValues({
        'holo_hifi_cache_v13': '{"legacy":"entry"}',
        'holo_hifi_cache_v14': jsonEncode({
          'poisoned_track_1': poisonedTrack.toJson(),
          'valid_v14_track_1': validTrack.toJson(),
        }),
      });

      final matcher = HifiMatcher();
      await matcher.init();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('holo_hifi_cache_v13'), isFalse);

      // Poisoned MP3 URL must be rejected
      expect(matcher.getCachedHiFi(poisonedTrack), isNull);

      // Valid FLAC entry must be served
      final retrievedValid = matcher.getCachedHiFi(validTrack);
      expect(retrievedValid, isNotNull);
      expect(
        retrievedValid!.flacStreamUrl,
        equals('https://other-er.kuwo.cn/hash/resource/trackmedia/clean.flac'),
      );
    });
  });
}
