import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../distribution/jarvis_share_screen.dart';
import '../phone/jarvis_phone_screen.dart';
import '../printer/jarvis_printer_screen.dart';
import '../system_control/jarvis_screen_control_screen.dart';
import 'jarvis_bluetooth_manager.dart';
import 'jarvis_cloud_device_network.dart';

class JarvisDevicesScreen
    extends ConsumerStatefulWidget {
  const JarvisDevicesScreen({super.key});

  @override
  ConsumerState<JarvisDevicesScreen>
      createState() => _JarvisDevicesScreenState();
}

class _JarvisDevicesScreenState
    extends ConsumerState<JarvisDevicesScreen> {
  final Set<String> _selectedIds = <String>{};

  void _send(String prompt) {
    ref
        .read(jarvisChatControllerProvider)
        .askJarvis(prompt);
  }

  Future<void> _handoffJarvis(
    JarvisCloudDeviceNetwork network,
    JarvisCloudDevice device,
  ) async {
    try {
      await network.handoffJarvisTo(
        device.deviceId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Jarvis handoff sent to ' +
                device.deviceName +
                '.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Handoff failed: ' +
                error.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _pingCloudDevice(
    JarvisCloudDeviceNetwork network,
    JarvisCloudDevice device,
  ) async {
    try {
      await network.sendCommand(
        targetDeviceId: device.deviceId,
        action: 'ping',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Ping queued for ' +
                device.deviceName +
                '.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Ping failed: ' +
                error.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _speakOnCloudDevice(
    JarvisCloudDeviceNetwork network,
    JarvisCloudDevice device,
  ) async {
    try {
      await network.sendCommand(
        targetDeviceId: device.deviceId,
        action: 'speak_text',
        parameters: <String, dynamic>{
          'text':
              'Jarvis cloud connection is online.',
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Speech command sent to ' +
                device.deviceName +
                '.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Cloud speech failed: ' +
                error.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _checkBackgroundRelay(
    JarvisCloudDeviceNetwork network,
  ) async {
    final Map<String, dynamic> status =
        await network.nativeRelayStatus();

    if (!mounted) return;

    final bool running =
        status['running'] == true;
    final bool polling =
        status['polling'] == true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          running
              ? 'Background cloud relay is running' +
                  (polling
                      ? ' and listening for safe remote commands.'
                      : ' and standing by while Jarvis is in the foreground.')
              : 'Background cloud relay is not running on this device.',
        ),
      ),
    );
  }

  Future<void> _connectSelected(
    JarvisBluetoothManager manager,
  ) async {
    if (_selectedIds.isEmpty) {
      return;
    }

    await manager.connectMany(_selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final JarvisBluetoothManager manager =
        ref.watch(jarvisBluetoothManagerProvider);

    final AsyncValue<JarvisBluetoothState> asyncState =
        ref.watch(jarvisBluetoothStateProvider);

    final JarvisBluetoothState state =
        asyncState.valueOrNull ?? manager.state;

    final JarvisCloudDeviceNetwork
        cloudNetwork = ref.watch(
      jarvisCloudDeviceNetworkProvider,
    );

    final AsyncValue<JarvisCloudDeviceState>
        cloudAsync = ref.watch(
      jarvisCloudDeviceStateProvider,
    );

    final JarvisCloudDeviceState cloudState =
        cloudAsync.valueOrNull ??
            cloudNetwork.state;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Cloud Jarvis Network',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  Text(
                    cloudState.configured
                        ? cloudState.onlineCount
                                .toString() +
                            ' internet-connected Jarvis device(s) online'
                        : 'Cloud device network is not configured in this build',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip:
                  'Refresh cloud devices',
              onPressed:
                  cloudState.configured
                      ? cloudNetwork
                          .refreshDevices
                      : null,
              icon: const Icon(
                Icons.cloud_sync,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
                    Icon(
                      cloudState.configured
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        cloudState.configured
                            ? 'Internet Device Bus Active'
                            : 'Internet Device Bus Offline',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jarvis devices communicate through the cloud with no Bluetooth pairing and no same-Wi-Fi requirement. Bluetooth remains available below for nearby hardware.',
                ),
                if (cloudState.deviceId
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This device: ' +
                        cloudState.deviceName,
                  ),
                  Text(
                    'Device ID: ' +
                        cloudState.deviceId,
                    style:
                        Theme.of(context)
                            .textTheme
                            .bodySmall,
                  ),
                ],
                if (cloudState.errorMessage !=
                    null) ...[
                  const SizedBox(height: 8),
                  Text(
                    cloudState.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: cloudState.configured
                      ? () => _checkBackgroundRelay(
                            cloudNetwork,
                          )
                      : null,
                  icon: const Icon(
                    Icons.cloud_queue,
                  ),
                  label: const Text(
                    'Background Cloud Relay',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (cloudState.devices.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.devices_other,
              ),
              title: Text(
                'No other Jarvis devices online yet',
              ),
              subtitle: Text(
                'Install and sign in to this Jarvis build on another internet-connected device. It will register automatically.',
              ),
            ),
          )
        else
          ...cloudState.devices.map(
            (JarvisCloudDevice device) {
              final bool isThisDevice =
                  device.deviceId ==
                      cloudState.deviceId;

              return Card(
                child: ListTile(
                  leading: Stack(
                    clipBehavior:
                        Clip.none,
                    children: <Widget>[
                      Icon(
                        device.online
                            ? Icons
                                .devices
                            : Icons
                                .devices_other,
                      ),
                      Positioned(
                        right: -5,
                        bottom: -4,
                        child: Icon(
                          Icons.circle,
                          size: 10,
                          color: device.online
                              ? Colors
                                  .greenAccent
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    device.deviceName +
                        (isThisDevice
                            ? ' • This device'
                            : ''),
                  ),
                  subtitle: Text(
                    (device.online
                            ? 'Online'
                            : 'Offline') +
                        (device.foreground
                            ? ' • foreground'
                            : '') +
                        (device.activeAvatar
                            ? ' • Jarvis active here'
                            : ''),
                  ),
                  trailing: isThisDevice
                      ? null
                      : PopupMenuButton<
                          String>(
                          enabled:
                              device.online,
                          onSelected:
                              (String action) {
                            if (action ==
                                'handoff') {
                              _handoffJarvis(
                                cloudNetwork,
                                device,
                              );
                            } else if (action ==
                                'ping') {
                              _pingCloudDevice(
                                cloudNetwork,
                                device,
                              );
                            } else if (action ==
                                'speak') {
                              _speakOnCloudDevice(
                                cloudNetwork,
                                device,
                              );
                            }
                          },
                          itemBuilder:
                              (BuildContext
                                      context) =>
                                  const <
                                      PopupMenuEntry<
                                          String>>[
                            PopupMenuItem<
                                String>(
                              value: 'handoff',
                              child: Text(
                                'Move Jarvis Here',
                              ),
                            ),
                            PopupMenuItem<
                                String>(
                              value: 'speak',
                              child: Text(
                                'Test Voice',
                              ),
                            ),
                            PopupMenuItem<
                                String>(
                              value: 'ping',
                              child: Text(
                                'Ping Device',
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Bluetooth Devices',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${state.connectedCount} Bluetooth LE device(s) connected',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh connected devices',
              onPressed:
                  manager.refreshSystemDevices,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      state.isReady
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.isReady
                            ? 'Bluetooth LE Hub Ready'
                            : 'Bluetooth Not Ready',
                        style: const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jarvis can keep multiple BLE devices connected at the same time. Each device has an independent connection state and known devices are remembered for reconnection.',
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: state.isScanning
                          ? manager.stopScan
                          : manager.startScan,
                      icon: Icon(
                        state.isScanning
                            ? Icons.stop
                            : Icons.radar,
                      ),
                      label: Text(
                        state.isScanning
                            ? 'Stop Scan'
                            : 'Scan',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _selectedIds.isEmpty
                              ? null
                              : () =>
                                  _connectSelected(
                                    manager,
                                  ),
                      icon: const Icon(
                        Icons.link,
                      ),
                      label: Text(
                        'Connect Selected (${_selectedIds.length})',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (state.devices.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.bluetooth_searching,
              ),
              title: Text(
                'No BLE devices discovered yet',
              ),
              subtitle: Text(
                'Tap Scan. Speakers, earbuds, vehicle audio and other Classic Bluetooth profiles may remain managed by Android system Bluetooth.',
              ),
            ),
          )
        else
          ...state.devices.map(
            (JarvisBluetoothDeviceState device) =>
                Card(
              child: CheckboxListTile(
                value:
                    _selectedIds.contains(
                  device.deviceId,
                ),
                onChanged: device.isConnected
                    ? null
                    : (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(
                              device.deviceId,
                            );
                          } else {
                            _selectedIds.remove(
                              device.deviceId,
                            );
                          }
                        });
                      },
                secondary: Icon(
                  device.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                ),
                title: Text(device.name),
                subtitle: Text(
                  '${device.connectionState.name}'
                  '${device.rssi == null ? '' : ' • RSSI ${device.rssi}'}'
                  '${device.isKnown ? ' • remembered' : ''}'
                  '${device.error == null ? '' : '\n${device.error}'}',
                ),
                controlAffinity:
                    ListTileControlAffinity.trailing,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.install_mobile_outlined,
            ),
            title: const Text(
              'Send JARVIS to another device',
            ),
            subtitle: const Text(
              'Privately share the exact installed JARVIS APK with another Android device using Quick Share, Drive, Messages, or another file-transfer target.',
            ),
            trailing:
                const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (BuildContext context) =>
                          const JarvisShareScreen(),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.print_outlined,
            ),
            title: const Text(
              'HP OfficeJet 2620 / USB Printing',
            ),
            subtitle: const Text(
              'Detect a USB-OTG printer, open Android print settings, and run a test print.',
            ),
            trailing:
                const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (BuildContext context) =>
                          const JarvisPrinterScreen(),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.touch_app_outlined,
            ),
            title: const Text(
              'Screen & App Control',
            ),
            subtitle: const Text(
              'Android Accessibility controls, global navigation actions, gestures, and bonded Classic Bluetooth devices.',
            ),
            trailing:
                const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (BuildContext context) =>
                          const JarvisScreenControlScreen(),
                ),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.phone_in_talk_outlined,
            ),
            title: const Text(
              'Phone Receptionist',
            ),
            subtitle: const Text(
              'Default-dialer setup, incoming-call handling, auto-answer controls and call activity.',
            ),
            trailing:
                const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (BuildContext context) =>
                          const JarvisPhoneScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Android Device Controls',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: () => _send(
                        'Turn on my flashlight.',
                      ),
                      child: const Text(
                        'Flashlight On',
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _send(
                        'Turn off my flashlight.',
                      ),
                      child: const Text(
                        'Flashlight Off',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _send(
                        'Change the Jarvis app theme to dark mode.',
                      ),
                      child:
                          const Text('Dark Mode'),
                    ),
                    OutlinedButton(
                      onPressed: () => _send(
                        'Change the Jarvis app theme to light mode.',
                      ),
                      child:
                          const Text('Light Mode'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.security),
            title: Text('Verified Execution'),
            subtitle: Text(
              'Jarvis reports success only after the local device/tool layer confirms the action. Unsupported actions are rejected instead of being faked.',
            ),
          ),
        ),
      ],
    );
  }
}
