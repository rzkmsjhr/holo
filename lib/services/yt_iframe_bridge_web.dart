// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

class YouTubeIframeBridge {
  static const String _workerEmbedBaseUrl =
      'https://nadanada-yt.kdmp.workers.dev/embed';

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<int> _stateController =
      StreamController<int>.broadcast();
  final StreamController<int> _errorController =
      StreamController<int>.broadcast();

  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  bool _isReady = false;
  bool _isActive = false;
  String? _currentVideoId;
  String? _pendingVideoId;
  int _pendingStartSeconds = 0;
  double _volume = 1.0;

  void Function(String message)? onLog;

  void _log(String msg) {
    onLog?.call('[YT-IframeBridge] $msg');
  }

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<int> get stateStream => _stateController.stream;
  Stream<int> get errorStream => _errorController.stream;

  bool get isSupported => true;
  bool get isActive => _isActive;
  String? get currentVideoId => _currentVideoId;

  void _ensureListener() {
    if (_messageSub != null) return;
    _messageSub = html.window.onMessage.listen((html.MessageEvent event) {
      if (!_isActive) return;
      final raw = event.data;
      if (raw == null) return;

      Map<dynamic, dynamic>? data;
      if (raw is Map) {
        data = raw;
      } else if (raw is String && raw.startsWith('{')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            data = decoded;
          }
        } catch (_) {}
      }
      if (data == null) return;

      final type = data['type']?.toString();
      if (type == null || !type.startsWith('yt-proxy-')) return;

      switch (type) {
        case 'yt-proxy-ready':
          _isReady = true;
          _log('Worker iframe ready (videoId: $_currentVideoId)');
          final volInt = (_volume * 100).round().clamp(0, 100);
          _sendCommand({'command': 'setVolume', 'value': volInt});
          _sendCommand({'command': 'unmute'});
          if (_pendingVideoId != null && _pendingVideoId != _currentVideoId) {
            final nextVid = _pendingVideoId!;
            _currentVideoId = nextVid;
            _pendingVideoId = null;
            _sendCommand({
              'command': 'loadVideoById',
              'videoId': nextVid,
              'startSeconds': _pendingStartSeconds,
            });
          }
          _sendCommand({'command': 'play'});
          break;

        case 'yt-proxy-time':
          final cur = data['currentTime'];
          final dur = data['duration'];
          if (cur is num && !cur.isNaN && cur >= 0) {
            _positionController.add(
              Duration(milliseconds: (cur * 1000).round()),
            );
          }
          if (dur is num && !dur.isNaN && dur > 0) {
            _durationController.add(
              Duration(milliseconds: (dur * 1000).round()),
            );
          }
          break;

        case 'yt-proxy-state':
          final st = data['data'];
          if (st is num) {
            final stateCode = st.toInt();
            _log('Player state changed: $stateCode');
            _stateController.add(stateCode);
          }
          break;

        case 'yt-proxy-error':
          final err = data['data'];
          final errCode = err is num ? err.toInt() : -1;
          _log('Player reported error code: $errCode for videoId: $_currentVideoId');
          _errorController.add(errCode);
          break;
      }
    });
  }

  void _sendCommand(Map<String, dynamic> payload) {
    try {
      _iframe?.contentWindow?.postMessage(payload, '*');
    } catch (e) {
      _log('Failed to postMessage ${payload['command']}: $e');
    }
  }

  void loadVideo(String videoId, {int startSeconds = 0, double volume = 1.0}) {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return;

    _ensureListener();
    _isActive = true;
    _volume = volume.clamp(0.0, 1.0);
    final volInt = (_volume * 100).round().clamp(0, 100);

    if (_iframe == null) {
      _currentVideoId = cleanId;
      _pendingVideoId = null;
      _isReady = false;

      final srcUrl =
          '$_workerEmbedBaseUrl?v=${Uri.encodeComponent(cleanId)}&start=$startSeconds&volume=$volInt';
      _log('Mounting Cloudflare Worker YouTube iframe: $srcUrl');

      final iframe = html.IFrameElement()
        ..id = 'holo-yt-proxy-iframe'
        ..src = srcUrl
        ..allow = 'autoplay; encrypted-media'
        ..referrerPolicy = 'strict-origin-when-cross-origin'
        ..style.position = 'fixed'
        ..style.width = '1px'
        ..style.height = '1px'
        ..style.bottom = '0'
        ..style.right = '0'
        ..style.opacity = '0.01'
        ..style.pointerEvents = 'none'
        ..style.border = 'none'
        ..style.zIndex = '-1';

      html.document.body?.append(iframe);
      _iframe = iframe;
      // Emit buffering state (3) immediately while iframe initializes
      _stateController.add(3);
      return;
    }

    if (_isReady) {
      _currentVideoId = cleanId;
      _pendingVideoId = null;
      _log('Loading video via postMessage: $cleanId (start: ${startSeconds}s)');
      _stateController.add(3);
      _sendCommand({
        'command': 'loadVideoById',
        'videoId': cleanId,
        'startSeconds': startSeconds,
      });
      _sendCommand({'command': 'setVolume', 'value': volInt});
      _sendCommand({'command': 'unmute'});
      _sendCommand({'command': 'play'});
    } else {
      _currentVideoId = cleanId;
      _pendingVideoId = cleanId;
      _pendingStartSeconds = startSeconds;
      final srcUrl =
          '$_workerEmbedBaseUrl?v=${Uri.encodeComponent(cleanId)}&start=$startSeconds&volume=$volInt';
      _log('Updating iframe src before ready: $srcUrl');
      _iframe!.src = srcUrl;
      _stateController.add(3);
    }
  }

  void play() {
    if (!_isActive) return;
    _sendCommand({'command': 'unmute'});
    _sendCommand({'command': 'play'});
  }

  void pause() {
    if (!_isActive) return;
    _sendCommand({'command': 'pause'});
  }

  void stop() {
    if (_iframe != null && _isReady) {
      _sendCommand({'command': 'pause'});
      _sendCommand({'command': 'stop'});
    }
    _isActive = false;
  }

  void seekTo(Duration position) {
    if (!_isActive) return;
    final secs = position.inMilliseconds / 1000.0;
    _sendCommand({'command': 'seekTo', 'value': secs});
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    if (!_isActive) return;
    final volInt = (_volume * 100).round().clamp(0, 100);
    _sendCommand({'command': 'setVolume', 'value': volInt});
  }

  void dispose() {
    stop();
    _messageSub?.cancel();
    _messageSub = null;
    _iframe?.remove();
    _iframe = null;
    _positionController.close();
    _durationController.close();
    _stateController.close();
    _errorController.close();
  }
}
