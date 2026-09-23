import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../core/network/providers.dart';
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
                const ModelViewer(
                  src:
                      'assets/models/CesiumMan.glb',
                  alt:
                      'Animated 3D Jarvis humanoid',
                  autoPlay: true,
                  autoRotate: true,
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
                const Text(
                  'JARVIS ONLINE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Standalone 3D companion • voice • vision • memory • autonomous tools',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
