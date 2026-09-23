import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../core/network/providers.dart';
import '../devices/jarvis_cloud_device_network.dart';
import 'jarvis_avatar_behavior.dart';
import '../realtime/jarvis_realtime_voice_screen.dart';
import '../realtime/jarvis_realtime_voice_service.dart';
import '../voice/jarvis_voice_screen.dart';

class JarvisPresenceScreen
    extends ConsumerWidget {
  const JarvisPresenceScreen({super.key});

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final AsyncValue<JarvisRealtimeVoiceState>
        asyncVoice = ref.watch(
      jarvisRealtimeVoiceStateProvider,
    );

    final JarvisRealtimeVoiceState voice =
        asyncVoice.valueOrNull ??
            const JarvisRealtimeVoiceState.initial();

    final JarvisAvatarBehavior behavior =
        JarvisAvatarBehavior.fromVoice(voice);

    final JarvisCloudDeviceNetwork cloud =
        ref.watch(
      jarvisCloudDeviceNetworkProvider,
    );

    final AsyncValue<JarvisCloudDeviceState>
        asyncCloud = ref.watch(
      jarvisCloudDeviceStateProvider,
    );

    final JarvisCloudDeviceState cloudState =
        asyncCloud.valueOrNull ??
            cloud.state;

    JarvisCloudDevice? activeDevice;
    for (final JarvisCloudDevice device
        in cloudState.devices) {
      if (device.activeAvatar) {
        activeDevice = device;
        break;
      }
    }

    final bool noAssignedDevice =
        activeDevice == null;

    final bool jarvisHere =
        noAssignedDevice ||
        activeDevice?.deviceId ==
            cloudState.deviceId ||
        cloudState.activeAvatar;

    final String activeDeviceName =
        activeDevice?.deviceName ?? '';

    final String stateLabel =
        switch (voice.status) {
      JarvisRealtimeVoiceStatus.idle =>
        'STANDING BY',
      JarvisRealtimeVoiceStatus.connecting =>
        'CONNECTING',
      JarvisRealtimeVoiceStatus.connected =>
        'LISTENING / SPEAKING',
      JarvisRealtimeVoiceStatus.stopping =>
        'ENDING SESSION',
      JarvisRealtimeVoiceStatus.error =>
        'VOICE ATTENTION',
    };

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'JARVIS 3D Presence',
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                AnimatedSlide(
                  duration:
                      const Duration(
                    milliseconds: 850,
                  ),
                  curve: Curves.easeInOutCubic,
                  offset: jarvisHere
                      ? Offset.zero
                      : const Offset(1.15, 0),
                  child: AnimatedOpacity(
                    duration:
                        const Duration(
                      milliseconds: 550,
                    ),
                    opacity:
                        jarvisHere ? 1 : 0,
                    child:
                        _JarvisAnimatedPresence(
                      behavior: behavior,
                      voice: voice,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin:
                            Alignment.topCenter,
                        end:
                            Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          Colors.black
                              .withValues(
                            alpha: 0.72,
                          ),
                        ],
                        stops:
                            const <double>[
                          0.55,
                          1,
                        ],
                      ),
                    ),
                  ),
                ),
                if (jarvisHere)
                  Positioned(
                    top: 18,
                    left: 18,
                    child: _BehaviorBadge(
                      behavior: behavior,
                    ),
                  ),
                if (!jarvisHere)
                  Center(
                    child: Card(
                      color: Colors.black
                          .withValues(
                        alpha: 0.78,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .all(18),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: <Widget>[
                            const Icon(
                              Icons
                                  .devices_other,
                              color: Colors
                                  .lightBlueAccent,
                              size: 36,
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            Text(
                              activeDeviceName
                                      .isEmpty
                                  ? 'Jarvis is active on another device'
                                  : 'Jarvis moved to ' +
                                      activeDeviceName,
                              textAlign:
                                  TextAlign
                                      .center,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                            const SizedBox(
                              height: 12,
                            ),
                            FilledButton.icon(
                              onPressed:
                                  cloudState
                                          .deviceId
                                          .isEmpty
                                      ? null
                                      : () async {
                                          try {
                                            await cloud
                                                .handoffJarvisTo(
                                              cloudState
                                                  .deviceId,
                                            );
                                          } on Object {
                                            // Network state exposes
                                            // the failure message.
                                          }
                                        },
                              icon:
                                  const Icon(
                                Icons
                                    .login,
                              ),
                              label:
                                  const Text(
                                'Bring Jarvis Here',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Card(
                    color: Colors.black
                        .withValues(alpha: 0.68),
                    child: Padding(
                      padding:
                          const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: <Widget>[
                              _StatusDot(
                                active:
                                    voice.isConnected,
                              ),
                              const SizedBox(
                                width: 8,
                              ),
                              Text(
                                stateLabel,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontWeight:
                                      FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          if (voice.transcript
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 10,
                            ),
                            Text(
                              voice.transcript,
                              maxLines: 3,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            width: double.infinity,
            padding:
                const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              20,
            ),
            child: Column(
              children: <Widget>[
                Text(
                  jarvisHere
                      ? 'JARVIS ONLINE'
                      : 'JARVIS REMOTE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  jarvisHere
                      ? 'Standalone 3D companion • voice • vision • memory • autonomous tools'
                      : (activeDeviceName.isEmpty
                          ? 'Jarvis is active on another cloud-connected device'
                          : 'Active on ' +
                              activeDeviceName +
                              ' through the Jarvis cloud network'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment:
                      WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (BuildContext
                                        context) =>
                                    const JarvisRealtimeVoiceScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.graphic_eq,
                      ),
                      label: const Text(
                        'Live Voice',
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton
                          .styleFrom(
                        foregroundColor:
                            Colors.white,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (BuildContext
                                        context) =>
                                    const JarvisVoiceScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.mic_none,
                      ),
                      label: const Text(
                        'Voice Hub',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Drag to rotate • pinch to zoom • rigged animation plays automatically',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.active,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 250),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? Colors.greenAccent
            : Colors.lightBlueAccent,
        boxShadow: <BoxShadow>[
          BoxShadow(
            blurRadius: active ? 12 : 6,
            color: active
                ? Colors.greenAccent
                : Colors.lightBlueAccent,
          ),
        ],
      ),
    );
  }
}


class _JarvisAnimatedPresence
    extends StatefulWidget {
  const _JarvisAnimatedPresence({
    required this.behavior,
    required this.voice,
  });

  final JarvisAvatarBehavior behavior;
  final JarvisRealtimeVoiceState voice;

  @override
  State<_JarvisAnimatedPresence> createState() =>
      _JarvisAnimatedPresenceState();
}

class _JarvisAnimatedPresenceState
    extends State<_JarvisAnimatedPresence> {
  Timer? _motionTimer;
  Alignment _alignment = Alignment.center;

  @override
  void initState() {
    super.initState();
    _configureMotion();
  }

  @override
  void didUpdateWidget(
    covariant _JarvisAnimatedPresence oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.behavior.motion !=
            widget.behavior.motion ||
        oldWidget.behavior.energy !=
            widget.behavior.energy) {
      _configureMotion();
    }
  }

  void _configureMotion() {
    _motionTimer?.cancel();
    _motionTimer = null;

    switch (widget.behavior.motion) {
      case JarvisAvatarMotion.pace:
        _alignment = const Alignment(-0.42, 0);
        _motionTimer = Timer.periodic(
          const Duration(milliseconds: 2200),
          (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _alignment = _alignment.x < 0
                  ? const Alignment(0.42, 0)
                  : const Alignment(-0.42, 0);
            });
          },
        );
      case JarvisAvatarMotion.approach:
        _alignment = const Alignment(0, 0.12);
      case JarvisAvatarMotion.breathe:
      case JarvisAvatarMotion.still:
        _alignment = Alignment.center;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool speaking =
        widget.voice.activity ==
            JarvisConversationActivity.speaking;
    final double scale = speaking
        ? 1.03 + (widget.behavior.energy * 0.04)
        : widget.behavior.motion ==
                JarvisAvatarMotion.approach
            ? 1.08
            : 1.0;

    return AnimatedAlign(
      duration: Duration(
        milliseconds:
            widget.behavior.motion ==
                    JarvisAvatarMotion.pace
                ? 2100
                : 650,
      ),
      curve: Curves.easeInOutCubic,
      alignment: _alignment,
      child: AnimatedScale(
        duration:
            const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: const SizedBox(
          width: 430,
          height: 560,
          child: ModelViewer(
            src:
                'assets/models/CesiumMan.glb',
            alt:
                'Animated 3D Jarvis humanoid',
            autoPlay: true,
            autoRotate: false,
            cameraControls: true,
            disableZoom: false,
            backgroundColor:
                Colors.transparent,
            loading: Loading.eager,
            reveal: Reveal.auto,
            interactionPrompt:
                InteractionPrompt.none,
            cameraOrbit:
                '0deg 75deg 2.2m',
          ),
        ),
      ),
    );
  }
}

class _BehaviorBadge extends StatelessWidget {
  const _BehaviorBadge({
    required this.behavior,
  });

  final JarvisAvatarBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 280),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(
          alpha: 0.68,
        ),
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color: Colors.lightBlueAccent
              .withValues(
            alpha: 0.65,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _expressionIcon(
              behavior.expression,
            ),
            size: 18,
            color: Colors.lightBlueAccent,
          ),
          const SizedBox(width: 8),
          Text(
            behavior.label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  IconData _expressionIcon(
    JarvisAvatarExpression expression,
  ) {
    switch (expression) {
      case JarvisAvatarExpression.attentive:
        return Icons.hearing;
      case JarvisAvatarExpression.thinking:
        return Icons.psychology;
      case JarvisAvatarExpression.speaking:
        return Icons.record_voice_over;
      case JarvisAvatarExpression.warm:
        return Icons.sentiment_satisfied_alt;
      case JarvisAvatarExpression.serious:
        return Icons.sentiment_neutral;
      case JarvisAvatarExpression.energetic:
        return Icons.bolt;
      case JarvisAvatarExpression.intense:
        return Icons.priority_high;
      case JarvisAvatarExpression.confident:
        return Icons.face;
      case JarvisAvatarExpression.neutral:
        return Icons.face_retouching_natural;
    }
  }
}
