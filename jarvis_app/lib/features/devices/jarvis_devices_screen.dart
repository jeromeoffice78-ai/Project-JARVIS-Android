import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import '../phone/jarvis_phone_screen.dart';
import '../printer/jarvis_printer_screen.dart';
import 'jarvis_bluetooth_manager.dart';

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
                    'Connected Devices',
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
