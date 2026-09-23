import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_phone_service.dart';

class JarvisPhoneScreen
    extends ConsumerStatefulWidget {
  const JarvisPhoneScreen({super.key});

  @override
  ConsumerState<JarvisPhoneScreen>
      createState() => _JarvisPhoneScreenState();
}

class _JarvisPhoneScreenState
    extends ConsumerState<JarvisPhoneScreen> {
  final TextEditingController _greetingController =
      TextEditingController();

  bool _loading = true;
  bool _isDefaultDialer = false;
  bool _autoAnswer = false;
  List<JarvisCallMessage> _messages =
      const <JarvisCallMessage>[];
  JarvisActiveCall? _activeCall;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _callTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refreshActiveCall()),
    );
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _callTimer = null;
    _greetingController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final JarvisPhoneService phone =
        ref.read(jarvisPhoneServiceProvider);

    final bool defaultDialer =
        await phone.isDefaultDialer();
    final bool autoAnswer =
        await phone.getAutoAnswer();
    final String greeting =
        await phone.getGreeting();
    final List<JarvisCallMessage> messages =
        await phone.listCallMessages();

    if (!mounted) return;

    setState(() {
      _isDefaultDialer = defaultDialer;
      _autoAnswer = autoAnswer;
      _messages = messages;
      _greetingController.text = greeting;
      _loading = false;
    });
  }

  Future<void> _refreshActiveCall() async {
    final JarvisPhoneService phone =
        ref.read(jarvisPhoneServiceProvider);
    final JarvisActiveCall? call =
        await phone.getActiveCall();

    if (!mounted) return;

    if (_activeCall?.phoneNumber !=
            call?.phoneNumber ||
        _activeCall?.state != call?.state ||
        _activeCall?.isMuted != call?.isMuted ||
        _activeCall?.audioRoute !=
            call?.audioRoute) {
      setState(() {
        _activeCall = call;
      });
    }
  }

  Future<void> _runCallAction(
    Future<bool> Function() action,
  ) async {
    final bool ok = await action();
    await _refreshActiveCall();

    if (!mounted || ok) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Android could not complete that call action.',
        ),
      ),
    );
  }

  Future<void> _requestRole() async {
    final JarvisPhoneService phone =
        ref.read(jarvisPhoneServiceProvider);

    await phone.requestDefaultDialer();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Approve Jarvis as the default phone app in Android, then return here.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final JarvisPhoneService phone =
        ref.watch(jarvisPhoneServiceProvider);

    if (!phone.isSupported) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Jarvis Phone Receptionist is available on Android devices.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Jarvis Phone Receptionist',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (_activeCall != null) ...[
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.phone_in_talk,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: <Widget>[
                                    const Text(
                                      'Active call',
                                      style: TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      _activeCall!
                                          .phoneNumber,
                                    ),
                                    Text(
                                      '${_activeCall!.state.toUpperCase()} • ${_activeCall!.audioRoute}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              if (_activeCall!
                                  .isRinging)
                                FilledButton.icon(
                                  onPressed: () =>
                                      _runCallAction(
                                    phone
                                        .answerActiveCall,
                                  ),
                                  icon: const Icon(
                                    Icons.call,
                                  ),
                                  label: const Text(
                                    'Answer',
                                  ),
                                ),
                              if (_activeCall!
                                  .isRinging)
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _runCallAction(
                                    phone
                                        .rejectActiveCall,
                                  ),
                                  icon: const Icon(
                                    Icons.call_end,
                                  ),
                                  label: const Text(
                                    'Reject',
                                  ),
                                ),
                              if (!_activeCall!
                                  .isRinging)
                                FilledButton.icon(
                                  onPressed: () =>
                                      _runCallAction(
                                    phone
                                        .disconnectActiveCall,
                                  ),
                                  icon: const Icon(
                                    Icons.call_end,
                                  ),
                                  label: const Text(
                                    'End Call',
                                  ),
                                ),
                              FilterChip(
                                selected:
                                    _activeCall!
                                        .isMuted,
                                avatar: const Icon(
                                  Icons.mic_off,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Mute',
                                ),
                                onSelected:
                                    (bool value) =>
                                        _runCallAction(
                                  () => phone
                                      .setMuted(
                                    value,
                                  ),
                                ),
                              ),
                              FilterChip(
                                selected:
                                    _activeCall!
                                            .audioRoute ==
                                        'speaker',
                                avatar: const Icon(
                                  Icons.volume_up,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Speaker',
                                ),
                                onSelected:
                                    (bool value) =>
                                        _runCallAction(
                                  () => phone
                                      .setSpeaker(
                                    value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: ListTile(
                    leading: Icon(
                      _isDefaultDialer
                          ? Icons.phone_in_talk
                          : Icons.phone_disabled,
                    ),
                    title: Text(
                      _isDefaultDialer
                          ? 'Jarvis is the default phone app'
                          : 'Make Jarvis the default phone app',
                    ),
                    subtitle: const Text(
                      'Android requires the default dialer role before Jarvis can manage incoming cellular calls.',
                    ),
                    trailing: _isDefaultDialer
                        ? const Icon(
                            Icons.check_circle,
                          )
                        : FilledButton(
                            onPressed: _requestRole,
                            child:
                                const Text('Enable'),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _autoAnswer,
                  onChanged: !_isDefaultDialer
                      ? null
                      : (bool value) async {
                          await phone.setAutoAnswer(
                            value,
                          );
                          if (mounted) {
                            setState(() {
                              _autoAnswer = value;
                            });
                          }
                        },
                  title:
                      const Text('Auto-answer calls'),
                  subtitle: const Text(
                    'When enabled, Jarvis answers incoming calls through Android InCallService.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _greetingController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText:
                        'Receptionist greeting',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment:
                      Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await phone.setGreeting(
                        _greetingController.text,
                      );
                    },
                    icon: const Icon(Icons.save),
                    label:
                        const Text('Save Greeting'),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Call activity & messages',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: _messages.isEmpty
                          ? null
                          : () async {
                              await phone
                                  .clearCallMessages();
                              await _refresh();
                            },
                      child:
                          const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_messages.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.voicemail_outlined,
                      ),
                      title: Text(
                        'No call messages yet',
                      ),
                    ),
                  )
                else
                  ..._messages.map(
                    (JarvisCallMessage item) =>
                        Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.phone_callback,
                        ),
                        title: Text(
                          item.phoneNumber,
                        ),
                        subtitle: Text(
                          '${item.status} • ${item.timestamp.toLocal()}\n${item.message}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Android can let a default dialer answer and control calls, but normal third-party apps cannot capture both sides of cellular-call audio for AI transcription. Full spoken message-taking needs the Jarvis telephony bridge.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
