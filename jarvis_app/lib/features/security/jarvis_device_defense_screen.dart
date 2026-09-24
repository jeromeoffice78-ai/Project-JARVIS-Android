import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_device_repair_service.dart';

class JarvisDeviceDefenseScreen extends ConsumerStatefulWidget {
  const JarvisDeviceDefenseScreen({super.key});

  @override
  ConsumerState<JarvisDeviceDefenseScreen> createState() =>
      _JarvisDeviceDefenseScreenState();
}

class _JarvisDeviceDefenseScreenState
    extends ConsumerState<JarvisDeviceDefenseScreen>
    with WidgetsBindingObserver {
  JarvisDeviceDiagnosis? _diagnosis;
  List<JarvisAppThreat> _apps = const <JarvisAppThreat>[];
  bool _scanning = false;
  String? _error;
  String? _pendingUninstallPackage;
  String? _statusMessage;

  JarvisDeviceRepairService get _service =>
      ref.read(jarvisDeviceRepairServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scanEverything());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _pendingUninstallPackage != null) {
      unawaited(_verifyPendingUninstall());
    }
  }

  Future<void> _scanEverything() async {
    if (_scanning) {
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final JarvisDeviceDiagnosis diagnosis =
          await _service.diagnose();
      final List<JarvisAppThreat> apps =
          await _service.scanApps();

      if (!mounted) {
        return;
      }

      setState(() {
        _diagnosis = diagnosis;
        _apps = apps;
        _statusMessage =
            'Scan complete. JARVIS analyzed ${apps.length} visible apps and ${diagnosis.issues.length} device issue(s).';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Device Defense scan failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  Future<void> _openRepair(String repair) async {
    final JarvisRepairResult result =
        await _service.repairIssue(repair);

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = result.message;
    });
  }

  Future<void> _reviewApp(JarvisAppThreat app) async {
    final bool opened =
        await _service.openAppDetails(app.packageName);

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = opened
          ? 'Opened Android app details for ${app.label}.'
          : 'Unable to open app details for ${app.label}.';
    });
  }

  Future<void> _removeApp(JarvisAppThreat app) async {
    if (app.systemApp) {
      setState(() {
        _statusMessage =
            'Android protects this system app. JARVIS will not bypass system protections.';
      });
      return;
    }

    final bool approved = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Remove suspicious app?'),
              content: Text(
                'JARVIS found risk signals in ${app.label} '
                '(${app.packageName}). Android will show the final uninstall confirmation. '
                'Risk score: ${app.riskScore}/10.\n\n'
                '${app.reasons.join('\n')}',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Open Uninstall'),
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
        await _service.requestUninstall(app.packageName);

    if (!mounted) {
      return;
    }

    setState(() {
      if (opened) {
        _pendingUninstallPackage = app.packageName;
        _statusMessage =
            'Android uninstall confirmation opened for ${app.label}. JARVIS will verify removal when you return.';
      } else {
        _statusMessage =
            'Android could not start uninstall for ${app.label}.';
      }
    });
  }

  Future<void> _verifyPendingUninstall() async {
    final String? packageName = _pendingUninstallPackage;
    if (packageName == null) {
      return;
    }

    final bool stillInstalled =
        await _service.isPackageInstalled(packageName);

    if (!mounted) {
      return;
    }

    setState(() {
      _pendingUninstallPackage = null;
      _statusMessage = stillInstalled
          ? 'Removal was not completed. The app is still installed.'
          : 'Threat removal verified. The app is no longer installed.';
    });

    await _scanEverything();
  }

  @override
  Widget build(BuildContext context) {
    final List<JarvisAppThreat> possibleMalware = _apps
        .where((JarvisAppThreat item) => item.possibleMalware)
        .toList(growable: false);

    final List<JarvisAppThreat> needsReview = _apps
        .where(
          (JarvisAppThreat item) =>
              !item.possibleMalware && item.needsReview,
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('JARVIS Device Defense'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _scanEverything,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: Icon(
                possibleMalware.isEmpty
                    ? Icons.verified_user_outlined
                    : Icons.gpp_bad_outlined,
                color: possibleMalware.isEmpty
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
              title: const Text('Virus & Malware Finder'),
              subtitle: Text(
                _scanning
                    ? 'Scanning device diagnostics and visible installed apps...'
                    : possibleMalware.isEmpty
                        ? 'No high-risk app matched JARVIS malware heuristics in the current scan.'
                        : '${possibleMalware.length} high-risk app(s) require immediate review.',
              ),
              trailing: _scanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _scanEverything,
                      icon: const Icon(Icons.security),
                      label: const Text('Scan'),
                    ),
            ),
          ),
          if (_diagnosis != null &&
              _diagnosis!.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Device Problems',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            for (final JarvisDeviceIssue issue in _diagnosis!.issues)
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.build_circle_outlined,
                    color: Colors.orangeAccent,
                  ),
                  title: Text(issue.summary),
                  subtitle: Text('Severity: ${issue.severity}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _openRepair(issue.repair),
                    child: const Text('Repair'),
                  ),
                ),
              ),
          ],
          if (possibleMalware.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Possible Malware',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
            ),
            for (final JarvisAppThreat app in possibleMalware)
              _ThreatCard(
                app: app,
                onReview: () => _reviewApp(app),
                onRemove: () => _removeApp(app),
              ),
          ],
          if (needsReview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Security Review',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            for (final JarvisAppThreat app in needsReview)
              _ThreatCard(
                app: app,
                onReview: () => _reviewApp(app),
                onRemove: () => _removeApp(app),
              ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Detection standard',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'JARVIS checks local security signals including accessibility control, '
                    'display-over-apps, device admin, notification access, boot persistence, '
                    'APK-install privileges, SMS/call-log access, and installer source. '
                    'A high score means possible malware; it is not a laboratory-confirmed virus signature.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bool ok =
                          await _service.clearJarvisCache();
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _statusMessage = ok
                            ? 'JARVIS temporary cache cleared.'
                            : 'JARVIS cache could not be cleared.';
                      });
                    },
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clean JARVIS Cache'),
                  ),
                ],
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(_statusMessage!),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                ),
                title: Text(_error!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreatCard extends StatelessWidget {
  const _ThreatCard({
    required this.app,
    required this.onReview,
    required this.onRemove,
  });

  final JarvisAppThreat app;
  final VoidCallback onReview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  app.possibleMalware
                      ? Icons.bug_report_outlined
                      : Icons.policy_outlined,
                  color: app.possibleMalware
                      ? Colors.redAccent
                      : Colors.amberAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        app.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        app.packageName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text('${app.riskScore}/10'),
                ),
              ],
            ),
            if (app.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final String reason in app.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $reason'),
                ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Inspect'),
                ),
                FilledButton.icon(
                  onPressed: app.systemApp ? null : onRemove,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
