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

  String _activityLabel(
    JarvisRealtimeVoiceState state,
  ) {
    return switch (state.activity) {
      JarvisConversationActivity.idle =>
        'Standing by',
      JarvisConversationActivity.listening =>
        'Listening',
      JarvisConversationActivity.thinking =>
        'Thinking',
      JarvisConversationActivity.speaking =>
        'Speaking',
    };
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toUpperCase() +
        value.substring(1);
  }

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
                        _activityLabel(state),
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
                  Text(
                    state.speakerName.isEmpty
                        ? 'Live speech-to-speech conversation with automatic mood, voice, and companion behavior.'
                        : 'Talking with ${state.speakerName}. Jarvis is carrying that person\'s People Memory into the conversation.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment:
                        WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Chip(
                        avatar: const Icon(
                          Icons.record_voice_over_outlined,
                          size: 18,
                        ),
                        label: Text(
                          'Voice: ${_titleCase(state.currentVoice)}',
                        ),
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.mood,
                          size: 18,
                        ),
                        label: Text(
                          state.companionMode
                              ? 'Mood: Companion'
                              : 'Mood: ${_titleCase(state.mood)}',
                        ),
                      ),
                      if (state.speakerName.isNotEmpty)
                        Chip(
                          avatar: const Icon(
                            Icons.person_outline,
                            size: 18,
                          ),
                          label: Text(
                            state.speakerName,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: state.autoDirector,
                    onChanged: (bool enabled) {
                      service.setAutoDirector(
                        enabled,
                      );
                    },
                    title: const Text(
                      'Autonomous director',
                    ),
                    subtitle: const Text(
                      'Jarvis chooses voice and mood from the conversation automatically.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment:
                        WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed:
                            busy ||
                                    state.isConnected
                                ? null
                                : service.start,
                        icon: const Icon(
                          Icons.play_arrow,
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
                              ? Icons.mic_off
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
                  const SizedBox(height: 14),
                  Wrap(
                    alignment:
                        WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed:
                            state.isConnected
                                ? () => service.setMood(
                                      'companion',
                                      companionMode: true,
                                    )
                                : null,
                        icon: const Icon(
                          Icons.favorite_outline,
                        ),
                        label: const Text(
                          'Companion Mode',
                        ),
                      ),
                      PopupMenuButton<String>(
                        enabled:
                            state.isConnected,
                        tooltip:
                            'Choose Jarvis voice',
                        onSelected:
                            service.setVoice,
                        itemBuilder:
                            (BuildContext context) =>
                                JarvisRealtimeVoiceService
                                    .supportedVoices
                                    .map(
                                      (String voice) =>
                                          PopupMenuItem<String>(
                                        value: voice,
                                        child: Text(
                                          _titleCase(
                                            voice,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(
                                      growable: false,
                                    ),
                        child: const Chip(
                          avatar: Icon(
                            Icons.tune,
                            size: 18,
                          ),
                          label: Text(
                            'Voice options',
                          ),
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
            'Conversation',
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.userTranscript.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.person_outline,
                ),
                title: Text(
                  state.speakerName.isEmpty
                      ? 'You'
                      : state.speakerName,
                ),
                subtitle: SelectableText(
                  state.userTranscript,
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.smart_toy_outlined,
              ),
              title: const Text('Jarvis'),
              subtitle: SelectableText(
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
