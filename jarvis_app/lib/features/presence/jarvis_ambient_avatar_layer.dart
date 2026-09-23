import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../devices/jarvis_cloud_device_network.dart';
import '../realtime/jarvis_realtime_voice_service.dart';
import 'jarvis_human_avatar_view.dart';

class JarvisAmbientAvatarLayer
    extends ConsumerStatefulWidget {
  const JarvisAmbientAvatarLayer({
    super.key,
  });

  @override
  ConsumerState<JarvisAmbientAvatarLayer>
      createState() =>
          _JarvisAmbientAvatarLayerState();
}

class _JarvisAmbientAvatarLayerState
    extends ConsumerState<JarvisAmbientAvatarLayer> {
  Timer? _movementTimer;
  int _positionIndex = 0;

  @override
  void initState() {
    super.initState();

    _movementTimer = Timer.periodic(
      const Duration(seconds: 9),
      (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _positionIndex =
              (_positionIndex + 1) % 5;
        });
      },
    );
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    _movementTimer = null;
    super.dispose();
  }

  Offset _targetFor(
    BoxConstraints constraints,
  ) {
    const double avatarWidth = 155;
    const double avatarHeight = 270;
    const double margin = 8;

    final double maxX =
        (constraints.maxWidth -
                avatarWidth -
                margin)
            .clamp(
              margin,
              double.infinity,
            );

    final double maxY =
        (constraints.maxHeight -
                avatarHeight -
                margin)
            .clamp(
              margin,
              double.infinity,
            );

    final List<Offset> targets =
        <Offset>[
      Offset(maxX, maxY),
      Offset(margin, maxY),
      Offset(
        (constraints.maxWidth -
                avatarWidth) /
            2,
        maxY,
      ),
      Offset(
        maxX,
        (maxY * 0.58).clamp(
          margin,
          maxY,
        ),
      ),
      Offset(
        margin,
        (maxY * 0.72).clamp(
          margin,
          maxY,
        ),
      ),
    ];

    return targets[
        _positionIndex % targets.length];
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

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (
          BuildContext context,
          BoxConstraints constraints,
        ) {
          final Offset target =
              _targetFor(constraints);

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AnimatedPositioned(
                duration:
                    const Duration(
                  milliseconds: 2100,
                ),
                curve:
                    Curves.easeInOutCubic,
                left: target.dx,
                top: target.dy,
                width: 155,
                height: 270,
                child: AnimatedOpacity(
                  duration:
                      const Duration(
                    milliseconds: 450,
                  ),
                  opacity:
                      jarvisHere ? 1 : 0,
                  child: DecoratedBox(
                    decoration:
                        BoxDecoration(
                      borderRadius:
                          BorderRadius
                              .circular(18),
                      gradient:
                          LinearGradient(
                        begin:
                            Alignment.topCenter,
                        end:
                            Alignment
                                .bottomCenter,
                        colors:
                            <Color>[
                          Colors.transparent,
                          Colors.black
                              .withValues(
                            alpha: 0.18,
                          ),
                        ],
                      ),
                    ),
                    child:
                        JarvisHumanAvatarView(
                      voiceState: voice,
                      active: jarvisHere,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
