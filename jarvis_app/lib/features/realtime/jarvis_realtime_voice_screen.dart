import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_realtime_voice_service.dart';

class JarvisRealtimeVoiceScreen
    extends ConsumerStatefulWidget {
  const JarvisRealtimeVoiceScreen({
    super.key,
  });

  @override
  ConsumerState<JarvisRealtimeVoiceScreen>
      createState() =>
          _JarvisRealtimeVoiceScreenState();
}

class _JarvisRealtimeVoiceScreenState
    extends ConsumerState<
        JarvisRealtimeVoiceScreen> {
  bool _muted = false;

  @override
  Widget build(BuildContext context) {
    final JarvisRealtimeVoiceService service =
        ref.watch(
      jarvisRealtimeVoiceServiceProvider,
    );

    final AsyncValue<JarvisRealtimeVoiceState>
        asyncState = ref.watch(
      jarvisRealtimeVoiceStateProvider,
    );

    final JarvisRealtimeVoiceState state =
        asyncState.valueOrNull ??
            service.state;

    final bool busy =
        state.status ==
            JarvisRealtimeVoiceStatus
                .connecting ||
        state.status ==
            JarvisRealtimeVoiceStatus
                .stopping;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'JARVIS Live Voice',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  AnimatedContainer(
                    duration:
                        const Duration(
                      milliseconds: 300,
                    ),
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 3,
                        color: state.isConnected
                            ? Colors.greenAccent
                            : Theme.of(context)
                                .colorScheme
                                .primary,
                      ),
                    ),
                    child: Icon(
                      state.isConnected
                          ? Icons
                              .graphic_eq
                          : Icons
                              .mic_none,
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    switch (state.status) {
                      JarvisRealtimeVoiceStatus
                            .idle =>
                        'Ready',
                      JarvisRealtimeVoiceStatus
                            .connecting =>
                        'Connecting to Jarvis...',
                      JarvisRealtimeVoiceStatus
                            .connected =>
                        'Live conversation active',
                      JarvisRealtimeVoiceStatus
                            .stopping =>
                        'Ending session...',
                      JarvisRealtimeVoiceStatus
                            .error =>
                        'Connection error',
                    },
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Direct speech-to-speech conversation with interruption support and Bluetooth audio preference.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment:
                        WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed:
                            busy ||
                                    state
                                        .isConnected
                                ? null
                                : service.start,
                        icon: const Icon(
                          Icons
                              .play_arrow,
                        ),
                        label: const Text(
                          'Start Live Voice',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            state.isConnected
                                ? () async {
                                    final bool next =
                                        !_muted;
                                    await service
                                        .mute(
                                      next,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _muted =
                                            next;
                                      });
                                    }
                                  }
                                : null,
                        icon: Icon(
                          _muted
                              ? Icons
                                  .mic_off
                              : Icons.mic,
                        ),
                        label: Text(
                          _muted
                              ? 'Unmute'
                              : 'Mute',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            state.status ==
                                    JarvisRealtimeVoiceStatus
                                        .idle
                                ? null
                                : service.stop,
                        icon: const Icon(
                          Icons.stop,
                        ),
                        label: const Text(
                          'End',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Live transcript',
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: SelectableText(
                state.transcript.isEmpty
                    ? 'Jarvis transcript will appear here while he speaks.'
                    : state.transcript,
              ),
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons
                      .warning_amber_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .error,
                ),
                title:
                    const Text('Voice error'),
                subtitle: Text(
                  state.errorMessage!,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
