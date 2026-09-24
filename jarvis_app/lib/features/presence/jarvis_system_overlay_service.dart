import 'package:flutter/services.dart';

import '../realtime/jarvis_realtime_voice_service.dart';

final class JarvisSystemOverlayStatus {
  const JarvisSystemOverlayStatus({
    required this.permissionGranted,
    required this.running,
  });

  final bool permissionGranted;
  final bool running;
}

class JarvisSystemOverlayService {
  const JarvisSystemOverlayService();

  static const MethodChannel _channel =
      MethodChannel('jarvis.overlay');

  Future<JarvisSystemOverlayStatus>
      status() async {
    try {
      final bool permission =
          await _channel.invokeMethod<bool>(
                'canDrawOverlays',
              ) ??
              false;

      final bool running =
          await _channel.invokeMethod<bool>(
                'isRunning',
              ) ??
              false;

      return JarvisSystemOverlayStatus(
        permissionGranted: permission,
        running: running,
      );
    } on PlatformException {
      return const JarvisSystemOverlayStatus(
        permissionGranted: false,
        running: false,
      );
    } on MissingPluginException {
      return const JarvisSystemOverlayStatus(
        permissionGranted: false,
        running: false,
      );
    }
  }

  Future<bool> openPermissionSettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'openOverlaySettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> start({
    required JarvisRealtimeVoiceState voiceState,
    required bool active,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'startOverlay',
            <String, Object?>{
              'state': avatarState(
                voiceState: voiceState,
                active: active,
              ),
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>(
            'stopOverlay',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> updateAvatarState({
    required JarvisRealtimeVoiceState voiceState,
    required bool active,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'updateState',
            <String, Object?>{
              'state': avatarState(
                voiceState: voiceState,
                active: active,
              ),
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Map<String, Object?> avatarState({
    required JarvisRealtimeVoiceState voiceState,
    required bool active,
  }) {
    return <String, Object?>{
      'active': active,
      'activity': voiceState.activity.name,
      'mood': voiceState.mood,
      'connected': voiceState.isConnected,
      'companion': voiceState.companionMode,
      'transcript': voiceState.transcript,
      'audioLevel': voiceState.remoteAudioLevel,
      'audioLevelAvailable':
          voiceState.remoteAudioLevelAvailable,
    };
  }
}
