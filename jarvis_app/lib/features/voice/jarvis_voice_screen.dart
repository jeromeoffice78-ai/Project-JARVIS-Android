import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../chat/jarvis_chat_controller.dart';
import '../realtime/jarvis_realtime_voice_screen.dart';
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
  bool _testingSpeaker = false;
  bool _testingMicrophone = false;
  String? _testResult;
  final TextEditingController
      _wakePassController =
      TextEditingController(
    text: JarvisVoiceController.defaultWakePass,
  );
  List<String> _devices = const <String>[];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refreshDevices);
  }

  Future<void> _testSpeaker(JarvisVoiceService service) async {
    if (_testingSpeaker) return;
    setState(() {
      _testingSpeaker = true;
      _testResult = 'Testing Jarvis on the selected audio output...';
    });
    try {
      await service.speak(
        'Hello. I am Jarvis. This is your local speaker test.',
      );
      if (!mounted) return;
      setState(() {
        _testResult = service.lastError ??
            'Speaker test finished. Did you hear the voice? '
                'If not, check media volume and Bluetooth output.';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _testResult = 'Speaker test failed: $error');
      }
    } finally {
      if (mounted) setState(() => _testingSpeaker = false);
    }
  }

  Future<void> _testMicrophone(
    JarvisVoiceController controller,
    JarvisVoiceService service,
  ) async {
    if (_testingMicrophone) return;
    setState(() {
      _testingMicrophone = true;
      _testResult = 'Checking Android speech recognition and microphone...';
    });
    try {
      final bool ready = await controller.initialize();
      if (!ready) {
        if (mounted) {
          setState(() {
            _testResult = service.lastError ??
                'Microphone or speech recognition is unavailable. '
                    'In Android Settings, grant Jarvis Microphone permission '
                    'and check that a speech-recognition service is installed.';
          });
        }
        return;
      }
      await controller.startPushToTalk();
      if (!mounted) return;
      setState(() {
        _testResult = service.isListening
            ? 'Microphone active. Speak now, then tap STOP on the large '
                'microphone. Your recognized words appear below.'
            : (service.lastError ??
                'Microphone did not begin listening. '
                    'Check Jarvis Microphone permission.');
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _testResult = 'Microphone test failed: $error');
      }
    } finally {
      if (mounted) setState(() => _testingMicrophone = false);
    }
  }

  Future<void> _saveWakePass(
    JarvisVoiceController controller,
  ) async {
    try {
      await controller.setWakePass(
        _wakePassController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Wake pass saved: "' +
                controller.wakePass +
                '"',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Wake pass could not be saved: ' +
                error.toString(),
          ),
        ),
      );
    }
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
  void dispose() {
    _wakePassController.dispose();
    super.dispose();
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
                StreamBuilder<String?>(
                  stream: service.errorStream,
                  initialData: service.lastError,
                  builder: (context, errorSnapshot) {
                    final String? diagnostic =
                        errorSnapshot.data ?? service.lastError;
                    if (diagnostic == null || diagnostic.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      color: const Color(0xFF362611),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          'VOICE DIAGNOSTIC: $diagnostic\n\n'
                          'If microphone access was denied, open Android '
                          'Settings → Apps → JARVIS AI Assistant → '
                          'Permissions → Microphone → Allow while using.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          'TEST JARVIS VOICE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Test your speaker and microphone separately. '
                          'This identifies why Jarvis may not respond.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _testingSpeaker
                                  ? null
                                  : () => unawaited(_testSpeaker(service)),
                              icon: const Icon(Icons.volume_up),
                              label: const Text('TEST SPEAKER'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _testingMicrophone
                                  ? null
                                  : () => unawaited(
                                        _testMicrophone(controller, service),
                                      ),
                              icon: const Icon(Icons.mic),
                              label: const Text('TEST MICROPHONE'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final String? request =
                                    controller.submitVoiceCommand(
                                  'Reply with a short confirmation that '
                                  'the Jarvis command and voice test works.',
                                );
                                setState(() {
                                  _testResult = request == null
                                      ? 'Command could not be submitted.'
                                      : 'Command submitted. Check the text '
                                          'response below; spoken replies '
                                          'should read it aloud.';
                                });
                              },
                              icon: const Icon(Icons.chat_outlined),
                              label: const Text('TEST COMMAND'),
                            ),
                          ],
                        ),
                        if (_testResult != null) ...<Widget>[
                          const SizedBox(height: 10),
                          SelectableText(_testResult!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.graphic_eq,
                    ),
                    title: const Text(
                      'Live Frontier Voice',
                    ),
                    subtitle: const Text(
                      'Direct speech-to-speech Jarvis with realtime turn-taking, interruptions, and Bluetooth audio preference.',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (BuildContext context) =>
                                  const JarvisRealtimeVoiceScreen(),
                        ),
                      );
                    },
                  ),
                ),
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
                        subtitle: Text(
                          'Listen for "' +
                              controller.wakePass +
                              '".',
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding:
                            const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Wake Pass',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller:
                                  _wakePassController,
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Wake phrase',
                                hintText:
                                    'Hey Jarvis',
                              ),
                              textInputAction:
                                  TextInputAction.done,
                              onSubmitted: (_) =>
                                  _saveWakePass(
                                controller,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _saveWakePass(
                                controller,
                              ),
                              icon: const Icon(
                                Icons.key_outlined,
                              ),
                              label: const Text(
                                'Save Wake Pass',
                              ),
                            ),
                          ],
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
                    if (state.responseText.trim().isEmpty &&
                        (state.errorMessage == null ||
                            state.errorMessage!.trim().isEmpty)) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          state.errorMessage?.trim().isNotEmpty == true
                              ? 'JARVIS COMMAND ERROR: ${state.errorMessage}'
                              : state.responseText,
                        ),
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
