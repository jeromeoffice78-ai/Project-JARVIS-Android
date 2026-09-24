import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_device_repair_service.dart';

class JarvisDeviceDefenseScreen
    extends ConsumerStatefulWidget {
  const JarvisDeviceDefenseScreen({
    super.key,
  });

  @override
  ConsumerState<JarvisDeviceDefenseScreen>
      createState() =>
          _JarvisDeviceDefenseScreenState();
}

class _JarvisDeviceDefenseScreenState
    extends ConsumerState<JarvisDeviceDefenseScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _diagnosis =
      <String, dynamic>{};
  List<Map<String, dynamic>> _apps =
      const <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;
  String? _pendingRemovalPackage;
  String? _pendingRemovalLabel;

  JarvisDeviceRepairService get _repair =>
      ref.read(
        jarvisDeviceRepairServiceProvider,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_runFullScan);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_verifyPendingRemoval());
    }
  }

  Future<void> _runFullScan() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> diagnosis =
          await _repair.diagnose();
      final List<Map<String, dynamic>> apps =
          await _repair.scanApps();

      if (!mounted) {
        return;
      }

      setState(() {
        _diagnosis = diagnosis;
        _apps = apps;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'Device scan failed: ' +
            error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _verifyPendingRemoval() async {
    final String? packageName =
        _pendingRemovalPackage;

    if (packageName == null ||
        packageName.isEmpty) {
      return;
    }

    final bool stillInstalled =
        await _repair.isPackageInstalled(
      packageName,
    );

    if (!mounted) {
      return;
    }

    final String label =
        _pendingRemovalLabel ??
            packageName;

    if (!stillInstalled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            label +
                ' is no longer installed.',
          ),
        ),
      );

      _pendingRemovalPackage = null;
      _pendingRemovalLabel = null;
    }

    await _runFullScan();
  }

  Future<void> _repairIssue(
    Map<String, dynamic> issue,
  ) async {
    final String target =
        issue['repair']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    if (target.isEmpty) {
      return;
    }

    final Map<String, dynamic> result =
        await _repair.repairTarget(
      target,
    );

    if (!mounted) {
      return;
    }

    if (result['ok'] != true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            result['error']
                    ?.toString() ??
                'JARVIS could not open that repair.',
          ),
        ),
      );
    }
  }

  Future<void> _clearJarvisCache() async {
    final bool ok =
        await _repair.clearJarvisCache();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'JARVIS cache cleared.'
              : 'JARVIS could not clear its cache.',
        ),
      ),
    );

    if (ok) {
      await _runFullScan();
    }
  }

  Future<void> _requestRemoval(
    Map<String, dynamic> app,
  ) async {
    final String packageName =
        app['packageName']
                ?.toString()
                .trim() ??
            '';

    if (packageName.isEmpty) {
      return;
    }

    final String label =
        app['label']
                ?.toString()
                .trim() ??
            packageName;

    final bool approved =
        await showDialog<bool>(
              context: context,
              builder:
                  (BuildContext dialogContext) {
                return AlertDialog(
                  title: const Text(
                    'Remove suspicious app?',
                  ),
                  content: Text(
                    'JARVIS found elevated risk signals in ' +
                        label +
                        '.\n\nAndroid will show its own uninstall confirmation. '
                        'JARVIS will verify whether the package is still installed when you return.',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () =>
                          Navigator.of(
                        dialogContext,
                      ).pop(false),
                      child: const Text(
                        'Cancel',
                      ),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(
                        dialogContext,
                      ).pop(true),
                      child: const Text(
                        'Continue',
                      ),
                    ),
                  ],
                );
              },
            ) ??
            false;

    if (!approved) {
      return;
    }

    final bool opened =
        await _repair.requestUninstall(
      packageName,
    );

    if (!mounted) {
      return;
    }

    if (!opened) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Android could not open the uninstall confirmation.',
          ),
        ),
      );
      return;
    }

    _pendingRemovalPackage =
        packageName;
    _pendingRemovalLabel = label;
  }

  List<Map<String, dynamic>>
      get _issues {
    final Object? raw =
        _diagnosis['issues'];

    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map(
          (Map item) =>
              Map<String, dynamic>.from(
            item,
          ),
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>>
      get _suspiciousApps {
    return _apps
        .where(
          (Map<String, dynamic> app) {
            final int score =
                (app['riskScore']
                            as num?)
                        ?.toInt() ??
                    0;
            return score >= 3;
          },
        )
        .toList(growable: false);
  }

  int get _possibleMalwareCount =>
      _apps
          .where(
            (Map<String, dynamic> app) =>
                app['possibleMalware'] ==
                true,
          )
          .length;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>>
        issues = _issues;
    final List<Map<String, dynamic>>
        suspicious = _suspiciousApps;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'JARVIS Device Defense',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Run full scan',
            onPressed:
                _loading
                    ? null
                    : _runFullScan,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _runFullScan,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.all(16),
          children: <Widget>[
            Card(
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
                          Icons.security_rounded,
                          size: 30,
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child: Text(
                            _possibleMalwareCount >
                                    0
                                ? 'Suspicious software needs review'
                                : 'Device defense scan',
                            style: Theme.of(
                              context,
                            )
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Visible apps scanned: ' +
                          _apps.length
                              .toString() +
                          '\nPossible malware signals: ' +
                          _possibleMalwareCount
                              .toString() +
                          '\nDevice issues: ' +
                          issues.length
                              .toString(),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'A high-risk result means JARVIS found a suspicious combination of capabilities. '
                      'It is not a guaranteed malware verdict.',
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed:
                              _loading
                                  ? null
                                  : _runFullScan,
                          icon: const Icon(
                            Icons
                                .document_scanner_outlined,
                          ),
                          label: const Text(
                            'Full Device Check',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _clearJarvisCache,
                          icon: const Icon(
                            Icons.cleaning_services,
                          ),
                          label: const Text(
                            'Clear JARVIS Cache',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.warning_amber,
                  ),
                  title: const Text(
                    'Scan warning',
                  ),
                  subtitle:
                      Text(_error!),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Device repairs',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (issues.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(
                    Icons.check_circle_outline,
                  ),
                  title: Text(
                    'No automatic device warnings detected',
                  ),
                  subtitle: Text(
                    'JARVIS checks storage, memory, battery, internet, and Bluetooth state.',
                  ),
                ),
              )
            else
              ...issues.map(
                (Map<String, dynamic>
                    issue) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons
                            .build_circle_outlined,
                      ),
                      title: Text(
                        issue['summary']
                                ?.toString() ??
                            'Device issue',
                      ),
                      subtitle: Text(
                        'Severity: ' +
                            (issue['severity']
                                    ?.toString() ??
                                'unknown'),
                      ),
                      trailing:
                          FilledButton.tonal(
                        onPressed: () =>
                            _repairIssue(
                          issue,
                        ),
                        child: const Text(
                          'Repair',
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            Text(
              'Malware and risky-app scan',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (!_loading &&
                suspicious.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(
                    Icons
                        .verified_user_outlined,
                  ),
                  title: Text(
                    'No elevated-risk visible apps found',
                  ),
                  subtitle: Text(
                    'JARVIS checks launcher apps plus visible accessibility, notification-listener, and device-admin components.',
                  ),
                ),
              )
            else
              ...suspicious.map(
                (
                  Map<String, dynamic>
                      app,
                ) {
                  final int score =
                      (app['riskScore']
                                  as num?)
                              ?.toInt() ??
                          0;
                  final bool possible =
                      app[
                              'possibleMalware'] ==
                          true;
                  final List<dynamic>
                      reasons =
                      app['reasons']
                                  is List
                          ? app['reasons']
                              as List<dynamic>
                          : const <
                              dynamic>[];

                  return Card(
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .all(14),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                possible
                                    ? Icons
                                        .gpp_maybe
                                    : Icons
                                        .policy_outlined,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: <Widget>[
                                    Text(
                                      app['label']
                                              ?.toString() ??
                                          app['packageName']
                                              ?.toString() ??
                                          'App',
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                    Text(
                                      'Risk score ' +
                                          score.toString() +
                                          '/10 • ' +
                                          (app['riskLevel']
                                                  ?.toString() ??
                                              'unknown'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (reasons
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 10,
                            ),
                            ...reasons.take(5).map(
                                  (
                                    dynamic reason,
                                  ) =>
                                      Padding(
                                    padding:
                                        const EdgeInsets
                                            .only(
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      '• ' +
                                          reason
                                              .toString(),
                                    ),
                                  ),
                                ),
                          ],
                          const SizedBox(
                            height: 10,
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: () =>
                                    _repair
                                        .openAppDetails(
                                  app['packageName']
                                          ?.toString() ??
                                      '',
                                ),
                                child: const Text(
                                  'App Details',
                                ),
                              ),
                              if (app[
                                      'systemApp'] !=
                                  true)
                                FilledButton(
                                  onPressed: () =>
                                      _requestRemoval(
                                    app,
                                  ),
                                  child: const Text(
                                    'Remove…',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
