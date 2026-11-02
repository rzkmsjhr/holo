import 'dart:async';

class YouTubeIframeBridge {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<int> _stateController =
      StreamController<int>.broadcast();
  final StreamController<int> _errorController =
      StreamController<int>.broadcast();

  void Function(String message)? onLog;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<int> get stateStream => _stateController.stream;
  Stream<int> get errorStream => _errorController.stream;

  bool get isSupported => false;
  bool get isActive => false;
  String? get currentVideoId => null;

  void loadVideo(String videoId, {int startSeconds = 0, double volume = 1.0}) {}
  void play() {}
  void pause() {}
  void stop() {}
  void seekTo(Duration position) {}
  void setVolume(double volume) {}

  void dispose() {
    _positionController.close();
    _durationController.close();
    _stateController.close();
    _errorController.close();
  }
}
