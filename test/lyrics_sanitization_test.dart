import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_audio/services/lyrics_service.dart';

void main() {
  group('Universal Lyrics Sanitization Tests', () {
    test('Cleans Indonesian ASR descriptors (inline, leading, and trailing)', () {
      expect(
        LyricsService.normalizeLyricText('Cinta [musik] memang misteri.'),
        equals('Cinta memang misteri.'),
      );

      expect(
        LyricsService.normalizeLyricText('Aku [musik] dicintai. [bernyanyi]'),
        equals('Aku dicintai.'),
      );

      expect(
        LyricsService.normalizeLyricText('Terkadang [musik]'),
        equals('Terkadang'),
      );

      expect(
        LyricsService.normalizeLyricText('Membuat [musik] cintamu'),
        equals('Membuat cintamu'),
      );

      expect(
        LyricsService.normalizeLyricText('[musik]'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('[bernyanyi]'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('  [tepuk tangan]  '),
        equals(''),
      );
    });

    test('Cleans English and international ASR descriptors and section headers', () {
      expect(
        LyricsService.normalizeLyricText('[Music]'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('[Applause]'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('♪ One more time, we gonna celebrate ♪'),
        equals('One more time, we gonna celebrate'),
      );

      expect(
        LyricsService.normalizeLyricText('Bailando [música] en la noche [cantando]'),
        equals('Bailando en la noche'),
      );

      expect(
        LyricsService.normalizeLyricText('【サビ】君が好き'),
        equals('君が好き'),
      );

      expect(
        LyricsService.normalizeLyricText('[Verse 1: Pamungkas] To the bone'),
        equals('To the bone'),
      );
    });

    test('Preserves legitimate backing vocals while removing parenthesized audio cues', () {
      // Legitimate backing vocals must be preserved
      expect(
        LyricsService.normalizeLyricText('I need you (I need you)'),
        equals('I need you (I need you)'),
      );

      expect(
        LyricsService.normalizeLyricText('Terbelah jadi dua (dua)'),
        equals('Terbelah jadi dua (dua)'),
      );

      expect(
        LyricsService.normalizeLyricText('Never gonna let you go (oh-woah)'),
        equals('Never gonna let you go (oh-woah)'),
      );

      // Non-vocal parenthesized descriptors must be removed
      expect(
        LyricsService.normalizeLyricText('(Instrumental)'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('(musik)'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('(guitar solo)'),
        equals(''),
      );

      expect(
        LyricsService.normalizeLyricText('Solo guitar (guitar solo) begins'),
        equals('Solo guitar begins'),
      );
    });

    test('Decodes HTML entities and strips subtitle styling tags', () {
      expect(
        LyricsService.normalizeLyricText('&quot;Cinta&quot; &amp; &lt;Rindu&gt;'),
        equals('"Cinta" & <Rindu>'),
      );

      expect(
        LyricsService.normalizeLyricText('<c.white>Line with styling</c>'),
        equals('Line with styling'),
      );

      expect(
        LyricsService.normalizeLyricText(r'{\an8}Positioned subtitle'),
        equals('Positioned subtitle'),
      );
    });

    test('Auto-heals corrupted legacy cached lyrics on deserialization from disk', () async {
      // Simulate previously cached Indonesian lyrics that had [musik] and [bernyanyi] stored
      final legacyCorruptedCache = [
        {'ms': 12000, 'text': 'Cinta [musik] memang misteri.'},
        {'ms': 15500, 'text': '[musik]'},
        {'ms': 18000, 'text': 'Aku [musik] dicintai. [bernyanyi]'},
        {'ms': 22000, 'text': 'Juga disakiti.'},
      ];

      SharedPreferences.setMockInitialValues({
        'lyrics_cache_v1_terbelah jadi dua|gloria jessica': jsonEncode(legacyCorruptedCache),
      });

      final service = LyricsService();
      final result = await service.fetchLyrics(
        trackName: 'Terbelah Jadi Dua',
        artistName: 'Gloria Jessica',
      );

      // Verify lines were cleansed and standalone [musik] was pruned
      expect(result.length, equals(3));
      expect(result[0].text, equals('Cinta memang misteri.'));
      expect(result[1].text, equals('Aku dicintai.'));
      expect(result[2].text, equals('Juga disakiti.'));
    });
  });
}
