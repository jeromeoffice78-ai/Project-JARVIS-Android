import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../chat/jarvis_chat_controller.dart';
import 'jarvis_voice_controller.dart';
import 'jarvis_voice_service.dart';

class JarvisVoiceScreen extends ConsumerStatefulWidget {
  const JarvisVoiceScreen({super.key});

  @override
  ConsumerState<JarvisVoiceScreen> createState() =>
      _JarvisVoiceScreenState();
}

class _JarvisVoiceScreenState
    extends ConsumerState<JarvisVoiceScreen> {
  bool _handsFree = false;
  bool _wakeWord = false;
  bool _spokenReplies = true;
  bool _loadingDevices = false;
  List<String> _devices = const <String>[];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refreshDevices);
  }

  Future<void> _refreshDevices() async {
    if (!mounted) return;
    setState(() => _loadingDevices = true);
    try {
      final List<String> devices = await ref
          .read(jarvisVoiceServiceProvider)
          .audioDeviceSummary();
      if (mounted) setState(() => _devices = devices);
    } on Object {
      if (mounted) setState(() => _devices = const <String>[]);
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final JarvisVoiceService service =
        ref.watch(jarvisVoiceServiceProvider);
    final JarvisVoiceController controller =
        ref.watch(jarvisVoiceControllerProvider);
    final JarvisChatController chat =
        ref.watch(jarvisChatControllerProvider);

    return StreamBuilder<JarvisVoiceState>(
      stream: service.stateStream,
      initialData: service.state,
      builder: (context, stateSnapshot) {
        final JarvisVoiceState voiceState =
            stateSnapshot.data ?? JarvisVoiceState.inactive;

        return StreamBuilder<String>(
          stream: service.transcriptStream,
          initialData: service.currentTranscript,
          builder: (context, transcriptSnapshot) {
            final String transcript = transcriptSnapshot.data ?? '';

            return ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                _StatusCard(state: voiceState),
                const SizedBox(height: 18),
                Center(
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (voiceState == JarvisVoiceState.speaking) {
                        unawaited(controller.interruptAndListen());
                      } else if (voiceState == JarvisVoiceState.listening) {
                        unawaited(controller.stopPushToTalk());
                      } else {
                        unawaited(controller.startPushToTalk());
                      }
                    },
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: Icon(
                        voiceState == JarvisVoiceState.listening
                            ? Icons.stop
                            : Icons.mic,
                        size: 58,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      transcript.trim().isEmpty
                          ? 'Tap the microphone and speak.'
                          : transcript,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        value: _handsFree,
                        onChanged: (bool enabled) {
                          setState(() {
                            _handsFree = enabled;
                            if (enabled) _wakeWord = false;
                          });
                          controller.setHandsFree(enabled);
                        },
                        title: const Text('Conversation Mode'),
                        subtitle: const Text(
                          'Listen again after every spoken Jarvis reply.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _wakeWord,
                        onChanged: (bool enabled) {
                          setState(() {
                            _wakeWord = enabled;
                            if (enabled) _handsFree = false;
                          });
                          controller.setWakeWordMode(enabled);
                        },
                        title: const Text('Wake Word Mode'),
                        subtitle: const Text(
                          'While the app is open, listen for “Jarvis”.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _spokenReplies,
                        onChanged: (bool enabled) {
                          setState(() => _spokenReplies = enabled);
                          controller.setSpokenReplies(enabled);
                        },
                        title: const Text('Spoken Replies'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    controller.submitVoiceCommand(
                      'Using the latest camera frame, tell me what I am looking at right now.',
                    );
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('Ask Jarvis What You See'),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.bluetooth_audio),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Audio Devices',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              onPressed: _loadingDevices ? null : _refreshDevices,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (_loadingDevices) const LinearProgressIndicator(),
                        if (!_loadingDevices && _devices.isEmpty)
                          const Text('No audio-route details reported.'),
                        for (final String device in _devices)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.headphones),
                            title: Text(device),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<JarvisChatState>(
                  stream: chat.stateStream,
                  initialData: chat.state,
                  builder: (context, chatSnapshot) {
                    final JarvisChatState state =
                        chatSnapshot.data ?? chat.state;
                    if (state.responseText.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(state.responseText),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Voice and wake-word listening are user-initiated and operate while the app is active.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final JarvisVoiceState state;

  @override
  Widget build(BuildContext context) {
    final String label = switch (state) {
      JarvisVoiceState.inactive => 'VOICE OFF',
      JarvisVoiceState.unavailable => 'VOICE UNAVAILABLE',
      JarvisVoiceState.initializing => 'INITIALIZING VOICE',
      JarvisVoiceState.idle => 'VOICE READY',
      JarvisVoiceState.listening => 'LISTENING',
      JarvisVoiceState.speaking => 'JARVIS IS SPEAKING',
      JarvisVoiceState.error => 'VOICE ERROR',
    };

    return Card(
      child: ListTile(
        leading: const Icon(Icons.record_voice_over),
        title: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
