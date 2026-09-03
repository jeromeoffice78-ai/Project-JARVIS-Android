import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/jarvis_config.dart';
import '../../core/network/jarvis_ws_service.dart';
import '../../core/network/providers.dart';
import '../capabilities/jarvis_capability_service.dart';

class JarvisSystemScreen extends ConsumerStatefulWidget {
  const JarvisSystemScreen({super.key});

  @override
  ConsumerState<JarvisSystemScreen> createState() =>
      _JarvisSystemScreenState();
}

class _JarvisSystemScreenState
    extends ConsumerState<JarvisSystemScreen> {
  final TextEditingController _smartHomeWebhook =
      TextEditingController();

  Map<String, dynamic>? _health;
  String? _error;
  String _capabilityResult = '';
  bool _loading = false;
  bool _savingWebhook = false;

  @override
  void initState() {
    super.initState();

    Future<void>.microtask(
      _loadCapabilitySettings,
    );
  }

  @override
  void dispose() {
    _smartHomeWebhook.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilitySettings() async {
    try {
      final String? webhook = await ref
          .read(jarvisCapabilityServiceProvider)
          .getSmartHomeWebhook();

      if (!mounted) {
        return;
      }

      _smartHomeWebhook.text =
          webhook ?? '';
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to load capability settings: $error',
        );
      }
    }
  }

  Future<void> _refreshHealth() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final health =
          await ref.read(jarvisApiServiceProvider).health();

      if (!mounted) {
        return;
      }

      setState(() => _health = health);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveWebhook() async {
    setState(() {
      _savingWebhook = true;
      _error = null;
    });

    try {
      await ref
          .read(jarvisCapabilityServiceProvider)
          .saveSmartHomeWebhook(
            _smartHomeWebhook.text,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _smartHomeWebhook.text.trim().isEmpty
                ? 'Smart-home webhook cleared.'
                : 'Smart-home webhook saved.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to save smart-home webhook: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _savingWebhook = false,
        );
      }
    }
  }

  Future<void> _testCapability(
    String action,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
      _capabilityResult = '';
    });

    try {
      final JarvisCapabilityResult result =
          await ref
              .read(
                jarvisCapabilityServiceProvider,
              )
              .execute(
                requestId: 'manual-system-test',
                callId:
                    '${DateTime.now().microsecondsSinceEpoch}',
                action: action,
                parameters:
                    const <String, dynamic>{},
              );

      if (!mounted) {
        return;
      }

      setState(() {
        _capabilityResult = const JsonEncoder
                .withIndent('  ')
            .convert(
          <String, dynamic>{
            'ok': result.ok,
            'result': result.result,
            'error': result.error,
          },
        );
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Capability test failed: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _loading = false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final JarvisConfig config =
        ref.watch(jarvisConfigProvider);

    final AsyncValue<JarvisConnectionState>
        connection = ref.watch(
      jarvisConnectionStateProvider,
    );

    final JarvisConnectionState state =
        connection.valueOrNull ??
            ref
                .read(jarvisWsServiceProvider)
                .currentState;

    return RefreshIndicator(
      onRefresh: _refreshHealth,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _StatusCard(
            title: 'WebSocket',
            value: state.name.toUpperCase(),
            icon: Icons.swap_horiz,
          ),
          const SizedBox(height: 12),
          _StatusCard(
            title: 'Backend',
            value:
                _health?['status']
                    ?.toString()
                    .toUpperCase() ??
                    'NOT CHECKED',
            icon: Icons.dns_outlined,
          ),
          const SizedBox(height: 12),
          _StatusCard(
            title: 'AI Model',
            value:
                _health?['model']?.toString() ??
                    'Configured server-side',
            icon: Icons.memory,
          ),
          const SizedBox(height: 12),
          _StatusCard(
            title: 'Persistent Memory',
            value:
                _health == null
                    ? 'UNKNOWN'
                    : 'AVAILABLE',
            icon: Icons.psychology,
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Configuration',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'HTTP: ${config.httpBaseUrl}\n'
                    'WS: ${config.wsUrl}\n'
                    'Client token configured: '
                    '${config.hasDevelopmentToken ? "YES" : "NO"}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Smart Home Bridge',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure an HTTP/HTTPS webhook for Home Assistant, '
                    'IFTTT, Node-RED, or another smart-home bridge. '
                    'Jarvis requires an approval dialog before triggering it.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        _smartHomeWebhook,
                    keyboardType:
                        TextInputType.url,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Smart-home webhook URL',
                      hintText:
                          'https://...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _savingWebhook
                            ? null
                            : _saveWebhook,
                    icon: const Icon(
                      Icons.save,
                    ),
                    label: const Text(
                      'Save Smart Home Bridge',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Capability Diagnostics',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Test permission-backed capabilities directly on the device.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _loading
                            ? null
                            : () =>
                                _testCapability(
                                  'get_current_location',
                                ),
                        icon: const Icon(
                          Icons.my_location,
                        ),
                        label: const Text(
                          'Test GPS',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading
                            ? null
                            : () =>
                                _testCapability(
                                  'get_health_summary',
                                ),
                        icon: const Icon(
                          Icons.favorite_border,
                        ),
                        label: const Text(
                          'Test Health',
                        ),
                      ),
                    ],
                  ),
                  if (_capabilityResult
                      .isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _capabilityResult,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading
                ? null
                : _refreshHealth,
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'Run Backend Health Check',
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color:
                      Colors.orangeAccent,
                ),
                title: const Text(
                  'System Warning',
                ),
                subtitle:
                    Text(_error!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}
