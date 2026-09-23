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
  final TextEditingController _textController =
      TextEditingController();
  final TextEditingController _packageController =
      TextEditingController();

  bool _loading = true;
  bool _accessibilityEnabled = false;
  List<JarvisBondedBluetoothDevice> _bonded =
      const <JarvisBondedBluetoothDevice>[];
  String? _status;

  @override
  void dispose() {
    _textController.dispose();
    _packageController.dispose();
    super.dispose();
  }

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

  Future<void> _analyzeCurrentScreen() async {
    if (!_accessibilityEnabled || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Capturing and analyzing the current screen...';
    });

    try {
      final JarvisSystemControlService control =
          ref.read(
        jarvisSystemControlServiceProvider,
      );
      final String screenshot =
          await control.captureScreenshot();

      final result = await ref
          .read(jarvisApiServiceProvider)
          .frontierQuery(
        prompt:
            'Analyze this Android screen. Describe what is visible, identify important buttons or controls, and note any warnings or errors. Do not infer hidden information.',
        mode: 'reason',
        imageBase64: screenshot,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _status = result.answer;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status =
            'Screen analysis failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _typeFocusedText() async {
    final String text =
        _textController.text;
    if (text.isEmpty) return;

    final bool ok = await ref
        .read(
          jarvisSystemControlServiceProvider,
        )
        .typeIntoFocusedField(text);

    if (!mounted) return;
    setState(() {
      _status = ok
          ? 'Text entered into the focused field.'
          : 'No editable focused field was available.';
    });
  }

  Future<void> _launchPackage() async {
    final String packageName =
        _packageController.text.trim();
    if (packageName.isEmpty) return;

    final bool ok = await ref
        .read(
          jarvisSystemControlServiceProvider,
        )
        .launchAppPackage(packageName);

    if (!mounted) return;
    setState(() {
      _status = ok
          ? 'Opened $packageName.'
          : 'Android could not launch $packageName.';
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
                FilledButton.icon(
                  onPressed:
                      _accessibilityEnabled && !_loading
                          ? _analyzeCurrentScreen
                          : null,
                  icon: const Icon(
                    Icons.visibility_outlined,
                  ),
                  label: const Text(
                    'Analyze Current Screen',
                  ),
                ),
                const SizedBox(height: 18),
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
                const SizedBox(height: 18),
                Text(
                  'Focused-field control',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jarvis can type only into the field currently focused by you. The accessibility service does not log or store screen text.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _textController,
                  decoration:
                      const InputDecoration(
                    border:
                        OutlineInputBorder(),
                    labelText:
                        'Text to enter',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed:
                      _accessibilityEnabled
                          ? _typeFocusedText
                          : null,
                  icon: const Icon(
                    Icons.keyboard,
                  ),
                  label: const Text(
                    'Type Into Focused Field',
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Launch installed app',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use an Android package name, for example com.android.settings. Jarvis does not enumerate installed apps.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _packageController,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(
                    border:
                        OutlineInputBorder(),
                    labelText:
                        'Android package name',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _launchPackage,
                  icon: const Icon(
                    Icons.open_in_new,
                  ),
                  label: const Text(
                    'Launch App',
                  ),
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
