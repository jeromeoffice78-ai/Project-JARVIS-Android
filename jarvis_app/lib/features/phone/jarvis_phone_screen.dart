import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/jarvis_api_service.dart';
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
  JarvisPhoneReceptionistStatus? _cloudStatus;
  List<JarvisPhoneReceptionistMessage>
      _cloudMessages =
      const <JarvisPhoneReceptionistMessage>[];
  String? _cloudError;

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

    JarvisPhoneReceptionistStatus? cloudStatus;
    List<JarvisPhoneReceptionistMessage>
        cloudMessages =
        const <JarvisPhoneReceptionistMessage>[];
    String? cloudError;

    try {
      final api = ref.read(
        jarvisApiServiceProvider,
      );
      cloudStatus =
          await api.phoneReceptionistStatus();
      cloudMessages =
          await api.phoneReceptionistMessages();
    } on Object catch (error) {
      cloudError = error.toString();
    }

    if (!mounted) return;

    setState(() {
      _isDefaultDialer = defaultDialer;
      _autoAnswer = autoAnswer;
      _messages = messages;
      _cloudStatus = cloudStatus;
      _cloudMessages = cloudMessages;
      _cloudError = cloudError;
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
                      _cloudStatus?.configured == true
                          ? Icons.support_agent
                          : Icons.cloud_off,
                    ),
                    title: const Text(
                      'Spoken AI Cellular Receptionist',
                    ),
                    subtitle: Text(
                      _cloudStatus == null
                          ? (_cloudError ??
                              'Checking the cloud receptionist...')
                          : (_cloudStatus!.configured
                              ? ('OpenAI SIP receptionist ready'
                                  + (_cloudStatus!.phoneNumber.isEmpty
                                      ? ''
                                      : ' • ' + _cloudStatus!.phoneNumber)
                                  + ' • active calls: '
                                  + _cloudStatus!.activeCalls.toString())
                              : 'Backend is deployed, but SIP/webhook activation is not complete.'),
                    ),
                    trailing:
                        _cloudStatus?.configured == true
                            ? const Icon(
                                Icons.check_circle,
                              )
                            : const Icon(
                                Icons.warning_amber,
                              ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_cloudMessages.isNotEmpty) ...[
                  Text(
                    'AI receptionist messages',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._cloudMessages.map(
                    (JarvisPhoneReceptionistMessage item) =>
                        Card(
                      child: ExpansionTile(
                        leading: Icon(
                          item.urgent
                              ? Icons.priority_high
                              : Icons.voicemail_outlined,
                        ),
                        title: Text(
                          item.callerName.isNotEmpty
                              ? item.callerName
                              : (item.callbackNumber.isNotEmpty
                                  ? item.callbackNumber
                                  : (item.fromNumber.isNotEmpty
                                      ? item.fromNumber
                                      : 'Unknown caller')),
                        ),
                        subtitle: Text(
                          (item.urgent ? 'URGENT • ' : '') +
                              (item.summary.isEmpty
                                  ? item.status
                                  : item.summary),
                        ),
                        children: <Widget>[
                          if (item.callbackNumber.isNotEmpty)
                            ListTile(
                              leading:
                                  const Icon(Icons.call),
                              title: const Text(
                                'Callback number',
                              ),
                              subtitle: Text(
                                item.callbackNumber,
                              ),
                            ),
                          if (item.transcript.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                12,
                              ),
                              child: Align(
                                alignment:
                                    Alignment.centerLeft,
                                child: SelectableText(
                                  'Caller:\n' +
                                      item.transcript,
                                ),
                              ),
                            ),
                          if (item.assistantTranscript.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              child: Align(
                                alignment:
                                    Alignment.centerLeft,
                                child: SelectableText(
                                  'JARVIS:\n' +
                                      item.assistantTranscript,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                      'Local Android dialer controls and the cloud receptionist are separate. '
                      'The cloud receptionist handles full two-way spoken AI calls through SIP, '
                      'then stores the caller message and transcript for Jarvis.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
