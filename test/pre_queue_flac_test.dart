import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_audio/models/daily_mix.dart';
import 'package:pulse_audio/models/track.dart';
import 'package:pulse_audio/providers/player_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'init':
            final id = methodCall.arguments['id'] as String?;
            if (id != null) {
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
                MethodChannel('com.ryanheise.just_audio.methods.$id'),
                (MethodCall playerCall) async {
                  switch (playerCall.method) {
                    case 'load':
                      return {'duration': 100000000};
                    default:
                      return <String, dynamic>{};
                  }
                },
              );
            }
            return <String, dynamic>{};
          case 'disposeAllPlayers':
            return <String, dynamic>{};
          default:
            return <String, dynamic>{};
        }
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async {
        return <String, dynamic>{};
      },
    );
  });

  group('Pre-Queue FLAC Resolution Gate Tests', () {
    late PlayerProvider player;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'holo_hifi_cache_v2': jsonEncode({
          'cached_track_1': {
            'id': 'cached_track_1',
            'title': 'To the Bone',
            'artist': 'Pamungkas',
            'album': 'Flying Solo',
            'durationSeconds': 345,
            'thumbnailUrl': 'https://i.ytimg.com/vi/cached_track_1/hqdefault.jpg',
            'flacStreamUrl': 'https://hifi.cdn.net/stream/pamungkas_to_the_bone.flac',
            'audioSource': 'kuwo',
            'audioFormat': 'FLAC Lossless 24-bit/96kHz',
            'isLossless': true,
          },
          'cached_track_2': {
            'id': 'cached_track_2',
            'title': 'About You',
            'artist': 'The 1975',
            'album': 'Being Funny In A Foreign Language',
            'durationSeconds': 326,
            'thumbnailUrl': 'https://i.ytimg.com/vi/cached_track_2/hqdefault.jpg',
            'flacStreamUrl': 'https://hifi.cdn.net/stream/the1975_about_you.flac',
            'audioSource': 'monochrome',
            'audioFormat': 'FLAC Lossless 16-bit/44.1kHz',
            'isLossless': true,
          },
        }),
      });
      player = PlayerProvider();
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('getCachedHiFi recognizes pre-cached FLAC tracks synchronously', () {
      final raw = Track(
        id: 'cached_track_1',
        title: 'To the Bone',
        artist: 'Pamungkas',
        album: 'Flying Solo',
        durationSeconds: 345,
        thumbnailUrl: '',
      );
      final cached = player.getCachedHiFi(raw);
      expect(cached, isNotNull);
      expect(cached!.isLossless, isTrue);
      expect(cached.flacStreamUrl, contains('pamungkas_to_the_bone.flac'));
    });

    test('addToQueue checks FLAC availability before inserting track into queue', () async {
      final raw = Track(
        id: 'cached_track_1',
        title: 'To the Bone',
        artist: 'Pamungkas',
        album: 'Flying Solo',
        durationSeconds: 345,
        thumbnailUrl: '',
      );

      await player.addToQueue(raw);

      expect(player.queue.length, equals(1));
      final queued = player.queue.first;
      expect(queued.isLossless, isTrue);
      expect(queued.audioSource, equals('kuwo'));
      expect(queued.flacStreamUrl, isNotNull);
    });

    test('playNext checks FLAC availability before inserting track into queue', () async {
      final raw1 = Track(
        id: 'cached_track_1',
        title: 'To the Bone',
        artist: 'Pamungkas',
        album: 'Flying Solo',
        durationSeconds: 345,
        thumbnailUrl: '',
      );
      final raw2 = Track(
        id: 'cached_track_2',
        title: 'About You',
        artist: 'The 1975',
        album: 'Being Funny In A Foreign Language',
        durationSeconds: 326,
        thumbnailUrl: '',
      );

      await player.addToQueue(raw1);
      await player.playNext(raw2);

      expect(player.queue.length, equals(2));
      final nextTrack = player.queue[1];
      expect(nextTrack.title, equals('About You'));
      expect(nextTrack.isLossless, isTrue);
      expect(nextTrack.audioSource, equals('monochrome'));
      expect(nextTrack.flacStreamUrl, isNotNull);
    });

    test('playDailyMix resolves starting track to FLAC and adds to queue', () async {
      final mix = DailyMix(
        id: 'mix_test',
        title: 'Daily Mix 1',
        subtitle: 'Pamungkas, The 1975',
        badge: 'MIX 1',
        coverUrl: '',
        gradientColors: const [],
        tracks: [
          Track(
            id: 'cached_track_1',
            title: 'To the Bone',
            artist: 'Pamungkas',
            album: 'Flying Solo',
            durationSeconds: 345,
            thumbnailUrl: '',
          ),
          Track(
            id: 'cached_track_2',
            title: 'About You',
            artist: 'The 1975',
            album: 'Being Funny In A Foreign Language',
            durationSeconds: 326,
            thumbnailUrl: '',
          ),
        ],
      );

      player.playDailyMix(mix, 0);

      // Wait for async load to populate queue
      await Future.delayed(const Duration(milliseconds: 150));

      expect(player.queue.isNotEmpty, isTrue);
      expect(player.queue.first.isLossless, isTrue);
      expect(player.queue.first.audioSource, equals('kuwo'));
    });
  });
}
