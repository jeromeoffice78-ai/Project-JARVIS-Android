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
  JarvisActiveCall? _activeCall;
  JarvisPhoneReceptionistStatus? _cloudStatus;
  List<JarvisPhoneReceptionistMessage>
      _cloudMessages =
      const <JarvisPhoneReceptionistMessage>[];
  String? _cloudError;
  JarvisCallerIntelligence? _callerIntelligence;
  bool _callerIntelligenceLoading = false;
  String? _callerIntelligenceError;
  String? _callerLookupNumber;
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

    JarvisPhoneReceptionistStatus? cloudStatus;
    List<JarvisPhoneReceptionistMessage>
        cloudMessages =
        const <JarvisPhoneReceptionistMessage>[];
    String? cloudError;

    try {
      final JarvisApiService api = ref.read(
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

  Future<void> _refreshActiveCall() async {
    final JarvisPhoneService phone =
        ref.read(jarvisPhoneServiceProvider);
    final JarvisActiveCall? call =
        await phone.getActiveCall();

    if (!mounted) return;

    final String? previousNumber =
        _activeCall?.phoneNumber;

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

    if (call == null) {
      if (previousNumber != null ||
          _callerIntelligence != null ||
          _callerIntelligenceError != null) {
        setState(() {
          _callerIntelligence = null;
          _callerIntelligenceError = null;
          _callerIntelligenceLoading = false;
          _callerLookupNumber = null;
        });
      }
      return;
    }

    final String number =
        call.phoneNumber.trim();

    if (number.isNotEmpty &&
        number != _callerLookupNumber) {
      unawaited(
        _lookupCallerIntelligence(number),
      );
    }
  }

  Future<void> _lookupCallerIntelligence(
    String number,
  ) async {
    final String normalized = number.trim();
    if (normalized.isEmpty) return;

    if (mounted) {
      setState(() {
        _callerLookupNumber = normalized;
        _callerIntelligenceLoading = true;
        _callerIntelligenceError = null;
        _callerIntelligence = null;
      });
    }

    try {
      final JarvisCallerIntelligence result =
          await ref
              .read(jarvisApiServiceProvider)
              .callerIntelligence(normalized);

      if (!mounted ||
          _callerLookupNumber != normalized) {
        return;
      }

      setState(() {
        _callerIntelligence = result;
        _callerIntelligenceLoading = false;
        _callerIntelligenceError =
            result.lookupError.isEmpty
                ? null
                : result.lookupError;
      });
    } on Object catch (error) {
      if (!mounted ||
          _callerLookupNumber != normalized) {
        return;
      }

      setState(() {
        _callerIntelligenceLoading = false;
        _callerIntelligenceError =
            error.toString();
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
                          const Divider(),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.manage_search,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'JARVIS Caller Intelligence',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_callerIntelligenceLoading)
                            const Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Identifying caller and carrier…',
                                  ),
                                ),
                              ],
                            )
                          else if (_callerIntelligence != null)
                            _CallerIntelligenceCard(
                              intelligence:
                                  _callerIntelligence!,
                            )
                          else if (_callerIntelligenceError !=
                              null)
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: <Widget>[
                                const Icon(
                                  Icons.info_outline,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _callerIntelligenceError!,
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
                              ? ((_cloudStatus!.provider == 'vapi'
                                      ? 'Vapi AI receptionist ready'
                                      : 'OpenAI SIP receptionist ready')
                                  + (_cloudStatus!.phoneNumber.isEmpty
                                      ? ''
                                      : ' • ' + _cloudStatus!.phoneNumber)
                                  + ' • active calls: '
                                  + _cloudStatus!.activeCalls.toString())
                              : 'Cloud receptionist transport is not currently active.'),
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
                      'Local Android call controls and the cloud receptionist are separate. '
                      'The cloud receptionist handles full two-way spoken AI calls through the '
                      'configured provider, then stores the caller message and transcript for Jarvis.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}


class _CallerIntelligenceCard
    extends StatelessWidget {
  const _CallerIntelligenceCard({
    required this.intelligence,
  });

  final JarvisCallerIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final String displayName =
        intelligence.callerName.isEmpty
            ? 'Name not returned by provider'
            : intelligence.callerName;

    final String network = <String>[
      intelligence.carrierName,
      intelligence.lineType,
    ].where((String value) => value.isNotEmpty)
        .join(' • ');

    final String location = <String>[
      intelligence.region,
      intelligence.countryCode,
    ].where((String value) => value.isNotEmpty)
        .join(' • ');

    final String timezone =
        intelligence.timeZones.join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: 0.55),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            displayName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (intelligence.callerType.isNotEmpty)
            Text(
              intelligence.callerType,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium,
            ),
          const SizedBox(height: 8),
          _CallerInfoRow(
            label: 'Number',
            value:
                intelligence.nationalFormat.isNotEmpty
                    ? intelligence.nationalFormat
                    : intelligence.phoneNumber,
          ),
          if (network.isNotEmpty)
            _CallerInfoRow(
              label: 'Carrier / line',
              value: network,
            ),
          if (location.isNotEmpty)
            _CallerInfoRow(
              label: 'Number region',
              value: location,
            ),
          if (timezone.isNotEmpty)
            _CallerInfoRow(
              label: 'Time zone',
              value: timezone,
            ),
          _CallerInfoRow(
            label: 'Number validity',
            value: intelligence.valid
                ? 'Valid numbering range'
                : 'Not verified as valid',
          ),
          if (intelligence.mobileCountryCode.isNotEmpty ||
              intelligence.mobileNetworkCode.isNotEmpty)
            _CallerInfoRow(
              label: 'Network codes',
              value:
                  '${intelligence.mobileCountryCode}/${intelligence.mobileNetworkCode}',
            ),
          if (intelligence.lookupError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                intelligence.lookupError,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            intelligence.locationNote,
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CallerInfoRow extends StatelessWidget {
  const _CallerInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
}
