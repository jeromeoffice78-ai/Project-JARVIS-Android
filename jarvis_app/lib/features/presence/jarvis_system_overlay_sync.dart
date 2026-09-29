import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../devices/jarvis_cloud_device_network.dart';
import '../realtime/jarvis_realtime_voice_service.dart';
import 'jarvis_system_overlay_service.dart';

class JarvisSystemOverlaySync
    extends ConsumerStatefulWidget {
  const JarvisSystemOverlaySync({
    super.key,
  });

  @override
  ConsumerState<JarvisSystemOverlaySync>
      createState() =>
          _JarvisSystemOverlaySyncState();
}

class _JarvisSystemOverlaySyncState
    extends ConsumerState<JarvisSystemOverlaySync>
    with WidgetsBindingObserver {
  static const JarvisSystemOverlayService
      _overlay =
      JarvisSystemOverlayService();

  String _lastFingerprint = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A dedicated Jarvis screen renders the character itself. Do not keep
    // a second GLB renderer on top of it through Android's system overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_overlay.setAppForeground(true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_overlay.setAppForeground(true));
    } else if (state == AppLifecycleState.paused) {
      unawaited(_overlay.setAppForeground(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<JarvisRealtimeVoiceState>
        voiceAsync = ref.watch(
      jarvisRealtimeVoiceStateProvider,
    );

    final JarvisRealtimeVoiceState voice =
        voiceAsync.valueOrNull ??
            const JarvisRealtimeVoiceState.initial();

    final JarvisCloudDeviceNetwork cloud =
        ref.watch(
      jarvisCloudDeviceNetworkProvider,
    );

    final AsyncValue<JarvisCloudDeviceState>
        cloudAsync = ref.watch(
      jarvisCloudDeviceStateProvider,
    );

    final JarvisCloudDeviceState cloudState =
        cloudAsync.valueOrNull ??
            cloud.state;

    JarvisCloudDevice? activeDevice;
    for (final JarvisCloudDevice device
        in cloudState.devices) {
      if (device.activeAvatar) {
        activeDevice = device;
        break;
      }
    }

    final bool jarvisHere =
        activeDevice == null ||
        activeDevice.deviceId ==
            cloudState.deviceId ||
        cloudState.activeAvatar;

    final String fingerprint = <Object?>[
      jarvisHere,
      voice.status.name,
      voice.activity.name,
      voice.mood,
      voice.companionMode,
      voice.transcript,
      voice.remoteAudioLevel
          .toStringAsFixed(3),
      voice.remoteAudioLevelAvailable,
    ].join('|');

    if (fingerprint != _lastFingerprint) {
      _lastFingerprint = fingerprint;

      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        unawaited(
          _overlay.updateAvatarState(
            voiceState: voice,
            active: jarvisHere,
          ),
        );
      });
    }

    return const SizedBox.shrink();
  }
}
