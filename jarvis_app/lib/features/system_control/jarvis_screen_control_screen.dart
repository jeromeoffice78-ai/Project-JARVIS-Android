import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_system_control_service.dart';

class JarvisScreenControlScreen
    extends ConsumerStatefulWidget {
  const JarvisScreenControlScreen({
    super.key,
  });

  @override
  ConsumerState<JarvisScreenControlScreen>
      createState() =>
          _JarvisScreenControlScreenState();
}

class _JarvisScreenControlScreenState
    extends ConsumerState<
        JarvisScreenControlScreen> {
  bool _loading = true;
  bool _accessibilityEnabled = false;
  List<JarvisBondedBluetoothDevice> _bonded =
      const <JarvisBondedBluetoothDevice>[];
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final JarvisSystemControlService service =
        ref.read(
      jarvisSystemControlServiceProvider,
    );

    final bool enabled =
        await service.isAccessibilityEnabled();
    final List<JarvisBondedBluetoothDevice>
        bonded = await service
            .listBondedBluetoothDevices();

    if (!mounted) {
      return;
    }

    setState(() {
      _accessibilityEnabled = enabled;
      _bonded = bonded;
      _loading = false;
    });
  }

  Future<void> _globalAction(
    String action,
  ) async {
    final JarvisSystemControlService service =
        ref.read(
      jarvisSystemControlServiceProvider,
    );

    final bool ok =
        await service.performGlobalAction(
      action,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _status = ok
          ? 'Action completed: $action'
          : 'Action unavailable. Enable Jarvis Accessibility Control first.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final JarvisSystemControlService service =
        ref.watch(
      jarvisSystemControlServiceProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Screen & App Control'),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon:
                const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : ListView(
              padding:
                  const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: ListTile(
                    leading: Icon(
                      _accessibilityEnabled
                          ? Icons
                              .verified_user
                          : Icons
                              .admin_panel_settings_outlined,
                    ),
                    title: Text(
                      _accessibilityEnabled
                          ? 'Jarvis Accessibility Control enabled'
                          : 'Enable Jarvis Accessibility Control',
                    ),
                    subtitle: const Text(
                      'Required for Jarvis to perform Back/Home/Recents and approved on-screen gestures. Android must grant this permission in Settings.',
                    ),
                    trailing:
                        _accessibilityEnabled
                            ? const Icon(
                                Icons
                                    .check_circle,
                              )
                            : FilledButton(
                                onPressed:
                                    service
                                        .openAccessibilitySettings,
                                child:
                                    const Text(
                                  'Enable',
                                ),
                              ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'System actions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed:
                          _accessibilityEnabled
                              ? () =>
                                  _globalAction(
                                    'back',
                                  )
                              : null,
                      icon: const Icon(
                        Icons.arrow_back,
                      ),
                      label:
                          const Text('Back'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _accessibilityEnabled
                              ? () =>
                                  _globalAction(
                                    'home',
                                  )
                              : null,
                      icon: const Icon(
                        Icons.home_outlined,
                      ),
                      label:
                          const Text('Home'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _accessibilityEnabled
                              ? () =>
                                  _globalAction(
                                    'recents',
                                  )
                              : null,
                      icon: const Icon(
                        Icons
                            .view_carousel_outlined,
                      ),
                      label:
                          const Text('Recents'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _accessibilityEnabled
                              ? () =>
                                  _globalAction(
                                    'notifications',
                                  )
                              : null,
                      icon: const Icon(
                        Icons
                            .notifications_outlined,
                      ),
                      label: const Text(
                        'Notifications',
                      ),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(
                    height: 10,
                  ),
                  Text(_status!),
                ],
                const SizedBox(
                  height: 18,
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Classic Bluetooth',
                        style:
                            Theme.of(context)
                                .textTheme
                                .titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: service
                          .openBluetoothSettings,
                      icon: const Icon(
                        Icons.settings,
                      ),
                      label: const Text(
                        'Bluetooth Settings',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_bonded.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(
                        Icons
                            .bluetooth_disabled,
                      ),
                      title: Text(
                        'No bonded Classic Bluetooth devices visible',
                      ),
                      subtitle: Text(
                        'Pair speakers, earbuds, vehicle audio, or other Classic Bluetooth hardware in Android Settings first.',
                      ),
                    ),
                  )
                else
                  ..._bonded.map(
                    (
                      JarvisBondedBluetoothDevice
                          device,
                    ) =>
                        Card(
                      child: ListTile(
                        leading:
                            const Icon(
                          Icons.bluetooth,
                        ),
                        title: Text(
                          device.name,
                        ),
                        subtitle: Text(
                          device.address,
                        ),
                        trailing:
                            const Icon(
                          Icons
                              .check_circle_outline,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(16),
                    child: Text(
                      'Jarvis uses Accessibility only for user-enabled device control. The service does not scrape accessibility events or credentials. Some apps and protected screens can block automation.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
