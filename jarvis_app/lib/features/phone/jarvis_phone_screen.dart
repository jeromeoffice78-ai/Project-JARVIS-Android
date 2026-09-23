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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
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
