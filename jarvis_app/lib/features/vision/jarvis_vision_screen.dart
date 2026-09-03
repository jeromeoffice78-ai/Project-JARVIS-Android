import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../chat/jarvis_chat_controller.dart';
import 'jarvis_vision_service.dart';

class JarvisVisionScreen extends ConsumerStatefulWidget {
  const JarvisVisionScreen({super.key});

  @override
  ConsumerState<JarvisVisionScreen> createState() =>
      _JarvisVisionScreenState();
}

class _JarvisVisionScreenState
    extends ConsumerState<JarvisVisionScreen> {
  String? _lastError;

  @override
  Widget build(BuildContext context) {
    final JarvisVisionService vision =
        ref.watch(jarvisVisionServiceProvider);

    return StreamBuilder<JarvisVisionState>(
      stream: vision.stateStream,
      initialData: vision.state,
      builder: (context, stateSnapshot) {
        final JarvisVisionState state =
            stateSnapshot.data ??
                JarvisVisionState.inactive;

        return StreamBuilder<int>(
          stream: vision.faceCountStream,
          initialData: 0,
          builder: (context, faceSnapshot) {
            final int faceCount =
                faceSnapshot.data ?? 0;

            return StreamBuilder<String?>(
              stream: vision.errorStream,
              initialData: _lastError,
              builder: (
                context,
                errorSnapshot,
              ) {
                final String? error =
                    errorSnapshot.data;

                _lastError = error;

                return ListView(
                  padding:
                      const EdgeInsets.all(16),
                  children: <Widget>[
                    _VisionStatusBanner(
                      state: state,
                    ),
                    const SizedBox(height: 14),
                    _CameraPanel(
                      controller:
                          vision.cameraController,
                      state: state,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        if (state !=
                                JarvisVisionState
                                    .active &&
                            state !=
                                JarvisVisionState
                                    .initializing)
                          FilledButton.icon(
                            onPressed: () async {
                              await vision.start();

                              if (mounted) {
                                setState(() {});
                              }
                            },
                            icon: const Icon(
                              Icons.videocam,
                            ),
                            label: const Text(
                              'Start Vision',
                            ),
                          ),
                        if (state ==
                            JarvisVisionState
                                .active)
                          FilledButton.icon(
                            style:
                                FilledButton
                                    .styleFrom(
                              backgroundColor:
                                  Colors
                                      .redAccent,
                            ),
                            onPressed: () async {
                              await vision.stop();

                              if (mounted) {
                                setState(() {});
                              }
                            },
                            icon: const Icon(
                              Icons
                                  .visibility_off,
                            ),
                            label: const Text(
                              'Stop Vision',
                            ),
                          ),
                        if (state ==
                            JarvisVisionState
                                .active)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await vision
                                  .switchCamera();

                              if (mounted) {
                                setState(() {});
                              }
                            },
                            icon: const Icon(
                              Icons.cameraswitch,
                            ),
                            label: const Text(
                              'Switch Camera',
                            ),
                          ),
                        if (state ==
                            JarvisVisionState
                                .active)
                          FilledButton
                              .tonalIcon(
                            onPressed: () async {
                              await vision
                                  .refreshFrameNow();

                              final JarvisChatController
                                  chat =
                                  ref.read(
                                jarvisChatControllerProvider,
                              );

                              chat.askJarvis(
                                'Using the latest camera frame, '
                                'tell me what I am looking at right now. '
                                'Describe important objects, visible text, '
                                'surroundings, and any obvious hazards.',
                              );

                              if (!context.mounted) {
                                return;
                              }

                              ScaffoldMessenger
                                  .of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Visual analysis sent to Jarvis chat.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.auto_awesome,
                            ),
                            label: const Text(
                              'What Do You See?',
                            ),
                          ),
                      ],
                    ),
                    if (state ==
                        JarvisVisionState.active) ...[
                      const SizedBox(height: 14),
                      Card(
                        child: ListTile(
                          leading: Icon(
                            faceCount > 0
                                ? Icons.face
                                : Icons
                                    .face_retouching_off,
                          ),
                          title: Text(
                            faceCount == 1
                                ? '1 person detected'
                                : '$faceCount people detected',
                          ),
                          subtitle: Text(
                            faceCount > 0
                                ? 'Open People Memory and confirm who is present.'
                                : 'No face currently detected in the latest frame.',
                          ),
                        ),
                      ),
                    ],
                    if (error != null &&
                        error.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons
                                .warning_amber_rounded,
                            color: Colors
                                .orangeAccent,
                          ),
                          title: const Text(
                            'Vision Warning',
                          ),
                          subtitle:
                              Text(error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Card(
                      child: Padding(
                        padding:
                            EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: <Widget>[
                            Text(
                              'How Camera Vision Works',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'While Vision is active, Jarvis refreshes a '
                              'short-lived camera frame on the backend. '
                              'Fresh frames can be attached to AI turns. '
                              'Face detection runs locally only to determine '
                              'whether people are present. Identity comes '
                              'only from your explicit People Memory confirmation. '
                              'Stopping Vision clears the backend frame.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VisionStatusBanner
    extends StatelessWidget {
  const _VisionStatusBanner({
    required this.state,
  });

  final JarvisVisionState state;

  @override
  Widget build(BuildContext context) {
    final (
      String label,
      Color color,
      IconData icon,
    ) = switch (state) {
      JarvisVisionState.active => (
          'CAMERA VISION ACTIVE',
          Colors.greenAccent,
          Icons.visibility,
        ),
      JarvisVisionState.initializing => (
          'INITIALIZING CAMERA',
          Colors.amberAccent,
          Icons.hourglass_top,
        ),
      JarvisVisionState.error => (
          'CAMERA VISION ERROR',
          Colors.redAccent,
          Icons.error_outline,
        ),
      JarvisVisionState.inactive => (
          'CAMERA VISION OFF',
          Colors.white54,
          Icons.visibility_off,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(14),
        color: color.withValues(
          alpha: 0.08,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight:
                    FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.controller,
    required this.state,
  });

  final CameraController? controller;
  final JarvisVisionState state;

  @override
  Widget build(BuildContext context) {
    final CameraController? active =
        controller;

    if (state ==
        JarvisVisionState.initializing) {
      return const AspectRatio(
        aspectRatio: 4 / 3,
        child: Card(
          child: Center(
            child:
                CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (state !=
            JarvisVisionState.active ||
        active == null ||
        !active.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 4 / 3,
        child: Card(
          child: Center(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.videocam_off_outlined,
                  size: 52,
                ),
                SizedBox(height: 12),
                Text(
                  'Camera vision is off.',
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio:
            active.value.aspectRatio,
        child: CameraPreview(active),
      ),
    );
  }
}
