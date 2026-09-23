import 'dart:async';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/network/jarvis_api_service.dart';

enum JarvisMusicStatus {
  idle,
  searching,
  playing,
  paused,
  error,
}

final class JarvisMusicState {
  const JarvisMusicState({
    required this.status,
    this.track,
    this.errorMessage,
  });

  const JarvisMusicState.initial()
      : status = JarvisMusicStatus.idle,
        track = null,
        errorMessage = null;

  final JarvisMusicStatus status;
  final JarvisMusicTrack? track;
  final String? errorMessage;

  bool get hasTrack => track != null;
}

class JarvisMusicService {
  JarvisMusicService({
    required JarvisApiService apiService,
  }) : _apiService = apiService;

  final JarvisApiService _apiService;

  final YoutubePlayerController controller =
      YoutubePlayerController(
    params: const YoutubePlayerParams(
      showControls: true,
      showFullscreenButton: true,
      mute: false,
      playsInline: true,
      strictRelatedVideos: true,
      privacyEnhancedMode: true,
    ),
  );

  final StreamController<JarvisMusicState>
      _stateController =
      StreamController<JarvisMusicState>
          .broadcast();

  JarvisMusicState _state =
      const JarvisMusicState.initial();
  bool _disposed = false;

  Stream<JarvisMusicState> get stateStream =>
      _stateController.stream;

  JarvisMusicState get state => _state;

  Future<JarvisMusicTrack> searchAndPlay(
    String query,
  ) async {
    _ensureActive();

    _emit(
      JarvisMusicState(
        status: JarvisMusicStatus.searching,
        track: _state.track,
      ),
    );

    try {
      final JarvisMusicTrack track =
          await _apiService.searchMusic(query);

      await controller.loadVideoById(
        videoId: track.videoId,
      );

      _emit(
        JarvisMusicState(
          status: JarvisMusicStatus.playing,
          track: track,
        ),
      );

      return track;
    } on Object catch (error) {
      _emit(
        JarvisMusicState(
          status: JarvisMusicStatus.error,
          track: _state.track,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> play() async {
    _ensureActive();

    if (_state.track == null) {
      return;
    }

    await controller.play();

    _emit(
      JarvisMusicState(
        status: JarvisMusicStatus.playing,
        track: _state.track,
      ),
    );
  }

  Future<void> pause() async {
    _ensureActive();

    if (_state.track == null) {
      return;
    }

    await controller.pause();

    _emit(
      JarvisMusicState(
        status: JarvisMusicStatus.paused,
        track: _state.track,
      ),
    );
  }

  Future<void> clear() async {
    _ensureActive();

    if (_state.track != null) {
      await controller.pause();
    }

    _emit(
      const JarvisMusicState.initial(),
    );
  }

  void _emit(JarvisMusicState next) {
    if (_disposed) {
      return;
    }

    _state = next;

    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError(
        'JarvisMusicService has been disposed.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    try {
      await controller.close();
    } on Object {
      // Best-effort player cleanup.
    }

    await _stateController.close();
  }
}
