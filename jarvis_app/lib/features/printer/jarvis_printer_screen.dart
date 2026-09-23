import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_printer_service.dart';
import 'jarvis_print_router.dart';

class JarvisPrinterScreen
    extends ConsumerStatefulWidget {
  const JarvisPrinterScreen({super.key});

  @override
  ConsumerState<JarvisPrinterScreen>
      createState() => _JarvisPrinterScreenState();
}

class _JarvisPrinterScreenState
    extends ConsumerState<JarvisPrinterScreen> {
  bool _loading = true;
  List<JarvisPrinterDevice> _devices =
      const <JarvisPrinterDevice>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final JarvisPrinterService service =
        ref.read(jarvisPrinterServiceProvider);
    final List<JarvisPrinterDevice> devices =
        await service.listUsbPrinters();

    if (!mounted) return;

    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final JarvisPrinterService service =
        ref.watch(jarvisPrinterServiceProvider);
    final JarvisPrintRouter router =
        ref.watch(jarvisPrintRouterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jarvis Printers'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh USB devices',
            onPressed: _refresh,
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
                router.isCloudRoutingConfigured
                    ? Icons.hub
                    : Icons.cloud_off,
              ),
              title: const Text(
                'Automatic printer routing',
              ),
              subtitle: Text(
                router.isCloudRoutingConfigured
                    ? 'This device: ${router.deviceName ?? 'initializing'}\nJarvis automatically selects whichever authorized Android device currently reports a ready printer.'
                    : 'Cloud routing is not configured in this build.',
              ),
              trailing: IconButton(
                tooltip: 'Refresh printer heartbeat',
                onPressed:
                    router.isCloudRoutingConfigured
                        ? () async {
                            await router
                                .refreshHeartbeat();
                            if (mounted) {
                              setState(() {});
                            }
                          }
                        : null,
                icon: const Icon(
                  Icons.sync,
                ),
              ),
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
                  const Row(
                    children: <Widget>[
                      Icon(Icons.print),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'HP OfficeJet 2620',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This model connects by USB 2.0, not Bluetooth or Wi-Fi. Connect the printer to the Android device with a USB OTG adapter and standard printer USB cable.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed:
                            service.openPrintSettings,
                        icon: const Icon(
                          Icons.settings,
                        ),
                        label: const Text(
                          'Print Settings',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            service.printTestPage,
                        icon:
                            const Icon(Icons.print),
                        label:
                            const Text('Test Print'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connected USB devices',
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    CircularProgressIndicator(),
              ),
            )
          else if (_devices.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(
                  Icons.usb_off_outlined,
                ),
                title: Text(
                  'No USB printer detected',
                ),
                subtitle: Text(
                  'Turn on the printer, connect its USB cable to a USB-OTG adapter, then connect the adapter to this Android device.',
                ),
              ),
            )
          else
            ..._devices.map(
              (JarvisPrinterDevice device) =>
                  Card(
                child: ListTile(
                  leading: Icon(
                    device.isHpDevice
                        ? Icons.print
                        : Icons.usb,
                  ),
                  title: Text(
                    device.displayName,
                  ),
                  subtitle: Text(
                    'Vendor ${device.vendorId} • Product ${device.productId}'
                    '${device.manufacturer.isEmpty ? '' : '\n${device.manufacturer}'}',
                  ),
                  trailing: device.isPrinterClass ||
                          device.isHpDevice
                      ? const Icon(
                          Icons.check_circle,
                        )
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'For HP USB printing, Android uses the system print framework and the HP Print Service Plugin. Jarvis can detect the USB printer, open print-service settings, and launch a test print through Android.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
