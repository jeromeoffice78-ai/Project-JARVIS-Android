import 'dart:async';

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
  JarvisWatchPhoneStatus? _watchPhoneStatus;
  List<JarvisWatchPhoneMessage> _watchMessages =
      const <JarvisWatchPhoneMessage>[];
  String? _watchPhoneError;
  Timer? _watchPhoneTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _watchPhoneTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshWatchPhone()),
    );
  }

  @override
  void dispose() {
    _watchPhoneTimer?.cancel();
    _watchPhoneTimer = null;
    _greetingController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final JarvisPhoneService phone =
        ref.read(jarvisPhoneServiceProvider);

    final Future<bool> defaultDialerFuture =
        phone.isDefaultDialer();
    final Future<bool> autoAnswerFuture =
        phone.getAutoAnswer();
    final Future<String> greetingFuture =
        phone.getGreeting();
    final Future<List<JarvisCallMessage>>
        messagesFuture = phone.listCallMessages();

    await _refreshWatchPhone();

    final bool defaultDialer =
        await defaultDialerFuture;
    final bool autoAnswer =
        await autoAnswerFuture;
    final String greeting =
        await greetingFuture;
    final List<JarvisCallMessage> messages =
        await messagesFuture;

    if (!mounted) return;

    setState(() {
      _isDefaultDialer = defaultDialer;
      _autoAnswer = autoAnswer;
      _messages = messages;
      _greetingController.text = greeting;
      _loading = false;
    });
  }

  Future<void> _refreshWatchPhone() async {
    final JarvisApiService api =
        ref.read(jarvisApiServiceProvider);

    try {
      final JarvisWatchPhoneStatus status =
          await api.watchPhoneStatus();
      final List<JarvisWatchPhoneMessage>
          messages =
          await api.watchPhoneMessages();

      if (!mounted) {
        return;
      }

      setState(() {
        _watchPhoneStatus = status;
        _watchMessages = messages;
        _watchPhoneError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _watchPhoneError = error.toString();
      });
    }
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
                      _watchPhoneStatus?.active == true
                          ? Icons.support_agent
                          : Icons.phone_disabled,
                    ),
                    title: const Text(
                      'Watch Bridge Vapi Line',
                    ),
                    subtitle: Text(
                      _watchPhoneStatus == null
                          ? (_watchPhoneError ??
                              'Checking the existing JARVIS receptionist line...')
                          : '${_watchPhoneStatus!.phoneNumber}\n${_watchPhoneStatus!.assistantName} • ${_watchPhoneStatus!.provider.toUpperCase()}',
                    ),
                    trailing:
                        _watchPhoneStatus?.active == true
                            ? const Icon(
                                Icons.check_circle,
                              )
                            : IconButton(
                                tooltip: 'Refresh cloud phone',
                                onPressed:
                                    _refreshWatchPhone,
                                icon: const Icon(
                                  Icons.refresh,
                                ),
                              ),
                    isThreeLine:
                        _watchPhoneStatus != null,
                  ),
                ),
                const SizedBox(height: 12),
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
                        'Watch Bridge call messages',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh Watch Bridge messages',
                      onPressed: _refreshWatchPhone,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_watchMessages.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.voicemail_outlined,
                      ),
                      title: const Text(
                        'No Watch Bridge messages loaded',
                      ),
                      subtitle: Text(
                        _watchPhoneError ??
                            'Messages from the existing JARVIS Vapi line will appear here.',
                      ),
                    ),
                  )
                else
                  ..._watchMessages.map(
                    (JarvisWatchPhoneMessage item) =>
                        Card(
                      child: ExpansionTile(
                        leading: Icon(
                          item.urgent
                              ? Icons.priority_high
                              : Icons.phone_callback,
                        ),
                        title: Text(
                          item.callerName.isNotEmpty
                              ? item.callerName
                              : (item.callbackNumber.isNotEmpty
                                  ? item.callbackNumber
                                  : (item.callerPhone.isNotEmpty
                                      ? item.callerPhone
                                      : 'Unknown caller')),
                        ),
                        subtitle: Text(
                          '${item.urgent ? 'URGENT • ' : ''}${item.summary.isEmpty ? 'Call completed.' : item.summary}',
                        ),
                        children: <Widget>[
                          if (item.callbackNumber.isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.call),
                              title: const Text('Callback number'),
                              subtitle: Text(item.callbackNumber),
                            ),
                          if (item.transcript.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              child: SelectableText(
                                item.transcript,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Local Android call activity',
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
                      'The Watch Bridge Vapi line handles spoken AI receptionist conversations and call-message transcripts. Android local dialer controls remain separate because Android does not let a normal third-party app capture both sides of ordinary cellular-call audio.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
