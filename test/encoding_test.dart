import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_audio/core/utils/text_encoding_utils.dart';
import 'package:pulse_audio/models/trending_track.dart';
import 'package:pulse_audio/services/hifi_matcher.dart';

void main() {
  group('TextEncodingUtils Tests', () {
    test('Correctly decodes UTF-8 multi-byte characters', () {
      // Extended Latin (eńau)
      final enauBytes = utf8.encode('eńau');
      expect(TextEncodingUtils.decodeHttpBytes(enauBytes), 'eńau');

      // Japanese
      final jpBytes = utf8.encode('米津玄師 - さくら');
      expect(TextEncodingUtils.decodeHttpBytes(jpBytes), '米津玄師 - さくら');

      // Korean
      final koBytes = utf8.encode('뉴진스 - Ditto');
      expect(TextEncodingUtils.decodeHttpBytes(koBytes), '뉴진스 - Ditto');

      // Arabic
      final arBytes = utf8.encode('عمرو دياب - تملي معاك');
      expect(TextEncodingUtils.decodeHttpBytes(arBytes), 'عمرو دياب - تملي معاك');

      // Thai
      final thBytes = utf8.encode('นนท์ ธนนท์ - โต๊ะริม');
      expect(TextEncodingUtils.decodeHttpBytes(thBytes), 'นนท์ ธนนท์ - โต๊ะริม');
    });

    test('Repairs Latin-1 mojibake back to UTF-8', () {
      // eńau corrupted by Latin-1 decoding
      expect(TextEncodingUtils.cleanMojibake('eÅ•au'), 'eńau');
      expect(TextEncodingUtils.cleanMojibake('eÅ\u0084au'), 'eńau');

      // Japanese corrupted by Latin-1 decoding
      const jpOriginal = 'さくら';
      final jpMojibake = latin1.decode(utf8.encode(jpOriginal));
      expect(TextEncodingUtils.cleanMojibake(jpMojibake), jpOriginal);

      // Clean string remains untouched
      expect(TextEncodingUtils.cleanMojibake('Ariana Grande'), 'Ariana Grande');
      expect(TextEncodingUtils.cleanMojibake('Teman Bahagia'), 'Teman Bahagia');
    });
  });

  group('TrendingTrack 2-Row Plays Tests', () {
    test('formattedPlaysNumber formats millions and thousands cleanly', () {
      const t1 = TrendingTrack(
        rank: 1,
        trend: '=',
        artist: 'eńau',
        title: 'Sesi Potret',
        plays: '1,270,000',
        query: 'eńau - Sesi Potret',
      );
      expect(t1.formattedPlaysNumber, '1.27M');

      const t2 = TrendingTrack(
        rank: 5,
        trend: '=',
        artist: 'Gloria Jessica',
        title: 'Terbelah',
        plays: '946,000',
        query: 'Gloria Jessica - Terbelah',
      );
      expect(t2.formattedPlaysNumber, '946K');

      const t3 = TrendingTrack(
        rank: 10,
        trend: '=',
        artist: 'Artist',
        title: 'Song',
        plays: '520',
        query: 'Artist - Song',
      );
      expect(t3.formattedPlaysNumber, '520');
    });
  });

  group('HifiMatcher International Support Tests', () {
    test('cleanTitle preserves Japanese, Korean, Arabic, and Thai characters', () {
      final matcher = HifiMatcher();
      expect(matcher.cleanTitle('さくら (Official Music Video)'), 'さくら');
      expect(matcher.cleanTitle('Ditto [MV]'), 'Ditto');
      expect(matcher.cleanTitle('تملي معاk (Audio)'), 'تملي معاk');
      expect(matcher.cleanTitle('โต๊ะริม - Official Video'), 'โต๊ะริม');
    });
  });
}
