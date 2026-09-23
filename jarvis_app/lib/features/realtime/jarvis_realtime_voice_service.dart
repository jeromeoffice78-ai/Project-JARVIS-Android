import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../core/network/jarvis_api_service.dart';

enum JarvisRealtimeVoiceStatus {
  idle,
  connecting,
  connected,
  stopping,
  error,
}

final class JarvisRealtimeVoiceState {
  const JarvisRealtimeVoiceState({
    required this.status,
    required this.transcript,
    this.errorMessage,
  });

  const JarvisRealtimeVoiceState.initial()
      : status = JarvisRealtimeVoiceStatus.idle,
        transcript = '',
        errorMessage = null;

  final JarvisRealtimeVoiceStatus status;
  final String transcript;
  final String? errorMessage;

  bool get isConnected =>
      status ==
      JarvisRealtimeVoiceStatus.connected;
}

class JarvisRealtimeVoiceService {
  JarvisRealtimeVoiceService({
    required JarvisApiService apiService,
    http.Client? httpClient,
  })  : _apiService = apiService,
        _httpClient = httpClient ?? http.Client();

  final JarvisApiService _apiService;
  final http.Client _httpClient;

  final StreamController<JarvisRealtimeVoiceState>
      _stateController =
      StreamController<JarvisRealtimeVoiceState>
          .broadcast();

  JarvisRealtimeVoiceState _state =
      const JarvisRealtimeVoiceState.initial();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  bool _disposed = false;

  Stream<JarvisRealtimeVoiceState> get stateStream =>
      _stateController.stream;

  JarvisRealtimeVoiceState get state => _state;

  Future<void> start() async {
    if (_disposed ||
        _state.status ==
            JarvisRealtimeVoiceStatus.connecting ||
        _state.isConnected) {
      return;
    }

    _emit(
      const JarvisRealtimeVoiceState(
        status:
            JarvisRealtimeVoiceStatus.connecting,
        transcript: '',
      ),
    );

    try {
      final String ephemeralSecret =
          await _apiService
              .createRealtimeClientSecret();

      await Helper
          .setSpeakerphoneOnButPreferBluetooth();

      final RTCPeerConnection pc =
          await createPeerConnection(
        <String, dynamic>{},
      );
      _peerConnection = pc;

      pc.onConnectionState =
          (RTCPeerConnectionState state) {
        if (_disposed) {
          return;
        }

        if (state ==
            RTCPeerConnectionState
                .RTCPeerConnectionStateConnected) {
          _emit(
            JarvisRealtimeVoiceState(
              status:
                  JarvisRealtimeVoiceStatus
                      .connected,
              transcript: _state.transcript,
            ),
          );
        } else if (state ==
                RTCPeerConnectionState
                    .RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState
                    .RTCPeerConnectionStateDisconnected) {
          _emit(
            JarvisRealtimeVoiceState(
              status:
                  JarvisRealtimeVoiceStatus.error,
              transcript: _state.transcript,
              errorMessage:
                  'Realtime voice connection was lost.',
            ),
          );
        }
      };

      final MediaStream stream =
          await navigator.mediaDevices
              .getUserMedia(
        <String, dynamic>{
          'audio': true,
          'video': false,
        },
      );
      _localStream = stream;

      for (final MediaStreamTrack track
          in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }

      final RTCDataChannelInit init =
          RTCDataChannelInit()
            ..ordered = true;

      final RTCDataChannel dataChannel =
          await pc.createDataChannel(
        'oai-events',
        init,
      );
      _dataChannel = dataChannel;
      dataChannel.onMessage =
          _handleDataChannelMessage;

      final RTCSessionDescription offer =
          await pc.createOffer(
        <String, dynamic>{
          'offerToReceiveAudio': true,
        },
      );

      await pc.setLocalDescription(offer);

      final String sdp = offer.sdp ?? '';
      if (sdp.isEmpty) {
        throw StateError(
          'WebRTC created no SDP offer.',
        );
      }

      final http.Response response =
          await _httpClient
              .post(
                Uri.parse(
                  'https://api.openai.com/v1/realtime/calls',
                ),
                headers: <String, String>{
                  'Authorization':
                      'Bearer $ephemeralSecret',
                  'Content-Type':
                      'application/sdp',
                },
                body: sdp,
              )
              .timeout(
                const Duration(seconds: 25),
              );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw StateError(
          'Realtime WebRTC setup failed with HTTP ${response.statusCode}.',
        );
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(
          response.body,
          'answer',
        ),
      );

      _emit(
        JarvisRealtimeVoiceState(
          status:
              JarvisRealtimeVoiceStatus.connected,
          transcript: _state.transcript,
        ),
      );
    } on Object catch (error) {
      await _closeTransport();

      _emit(
        JarvisRealtimeVoiceState(
          status: JarvisRealtimeVoiceStatus.error,
          transcript: _state.transcript,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void _handleDataChannelMessage(
    RTCDataChannelMessage message,
  ) {
    if (_disposed || message.isBinary) {
      return;
    }

    try {
      final Object? decoded =
          jsonDecode(message.text);
      if (decoded is! Map) {
        return;
      }

      final Map<String, dynamic> event =
          Map<String, dynamic>.from(decoded);
      final String type =
          event['type']?.toString() ?? '';

      String? delta;
      if (type ==
              'response.output_audio_transcript.delta' ||
          type ==
              'response.output_text.delta') {
        delta = event['delta']?.toString();
      }

      if (delta != null && delta.isNotEmpty) {
        _emit(
          JarvisRealtimeVoiceState(
            status: _state.isConnected
                ? JarvisRealtimeVoiceStatus.connected
                : _state.status,
            transcript:
                _state.transcript + delta,
          ),
        );
      }

      if (type == 'error') {
        final Object? rawError =
            event['error'];
        final String errorText =
            rawError is Map
                ? rawError['message']?.toString() ??
                    'Realtime voice error.'
                : 'Realtime voice error.';

        _emit(
          JarvisRealtimeVoiceState(
            status: JarvisRealtimeVoiceStatus.error,
            transcript: _state.transcript,
            errorMessage: errorText,
          ),
        );
      }
    } on FormatException {
      // Ignore malformed/non-JSON data channel events.
    }
  }

  Future<void> mute(bool muted) async {
    final MediaStream? stream = _localStream;
    if (stream == null) {
      return;
    }

    for (final MediaStreamTrack track
        in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    _emit(
      JarvisRealtimeVoiceState(
        status: JarvisRealtimeVoiceStatus.stopping,
        transcript: _state.transcript,
      ),
    );

    await _closeTransport();

    _emit(
      const JarvisRealtimeVoiceState.initial(),
    );
  }

  Future<void> _closeTransport() async {
    final RTCDataChannel? channel =
        _dataChannel;
    _dataChannel = null;

    if (channel != null) {
      try {
        await channel.close();
      } on Object {
        // Continue shutdown.
      }
    }

    final MediaStream? stream =
        _localStream;
    _localStream = null;

    if (stream != null) {
      for (final MediaStreamTrack track
          in stream.getTracks()) {
        try {
          await track.stop();
        } on Object {
          // Continue shutdown.
        }
      }

      try {
        await stream.dispose();
      } on Object {
        // Continue shutdown.
      }
    }

    final RTCPeerConnection? pc =
        _peerConnection;
    _peerConnection = null;

    if (pc != null) {
      try {
        await pc.close();
      } on Object {
        // Continue shutdown.
      }

      try {
        await pc.dispose();
      } on Object {
        // Continue shutdown.
      }
    }

    try {
      await Helper
          .clearAndroidCommunicationDevice();
    } on Object {
      // Android-only cleanup is best effort.
    }
  }

  void _emit(JarvisRealtimeVoiceState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await _closeTransport();
    _disposed = true;
    _httpClient.close();
    await _stateController.close();
  }
}
