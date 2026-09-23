import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class JarvisShareScreen
    extends StatefulWidget {
  const JarvisShareScreen({super.key});

  @override
  State<JarvisShareScreen> createState() =>
      _JarvisShareScreenState();
}

class _JarvisShareScreenState
    extends State<JarvisShareScreen> {
  static const MethodChannel _channel =
      MethodChannel(
        'jarvis.app_distribution',
      );

  bool _sharing = false;
  String? _error;

  Future<void> _shareInstalledApk(
    BuildContext buttonContext,
  ) async {
    if (_sharing) return;

    setState(() {
      _sharing = true;
      _error = null;
    });

    try {
      final String? path =
          await _channel.invokeMethod<String>(
        'exportInstalledApk',
      );

      if (path == null || path.isEmpty) {
        throw StateError(
          'Android returned no APK file.',
        );
      }

      final RenderBox? box =
          buttonContext.findRenderObject()
              as RenderBox?;

      await SharePlus.instance.share(
        ShareParams(
          title: 'Send JARVIS',
          subject:
              'JARVIS Android installer',
          text:
              'JARVIS Android installer. Send this only to devices you control.',
          files: <XFile>[
            XFile(
              path,
              mimeType:
                  'application/vnd.android.package-archive',
              name:
                  'JARVIS-current.apk',
            ),
          ],
          fileNameOverrides:
              const <String>[
            'JARVIS-current.apk',
          ],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(
                    Offset.zero,
                  ) &
                  box.size,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Send JARVIS',
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Send JARVIS to another Android device',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight:
                      FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Jarvis exports the exact APK currently installed on this device, '
            'then opens Android sharing. You can use Quick Share, Google Drive, '
            'email, Messages, or another file-transfer target.',
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(
                        Icons.install_mobile,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Private device transfer',
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
                    '1. Tap Share Installed APK.\n'
                    '2. Pick Quick Share, Drive, or another sharing method.\n'
                    '3. Open JARVIS-current.apk on the other Android device.\n'
                    '4. Android may ask for permission to install from that source.\n'
                    '5. After installation, Jarvis can register that device on the cloud network.',
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (
                      BuildContext buttonContext,
                    ) {
                      return SizedBox(
                        width:
                            double.infinity,
                        child:
                            FilledButton.icon(
                          onPressed: _sharing
                              ? null
                              : () =>
                                  _shareInstalledApk(
                                    buttonContext,
                                  ),
                          icon: _sharing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .share_outlined,
                                ),
                          label: Text(
                            _sharing
                                ? 'Preparing APK...'
                                : 'Share Installed APK',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber,
                  color: Theme.of(context)
                      .colorScheme
                      .error,
                ),
                title: const Text(
                  'APK sharing failed',
                ),
                subtitle: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Card(
            child: ListTile(
              leading:
                  Icon(Icons.security),
              title: Text(
                'Keep this build private',
              ),
              subtitle: Text(
                'This is your configured JARVIS build. Send it only to devices you control rather than posting the APK publicly.',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading:
                  Icon(Icons.bluetooth),
              title: Text(
                'Bluetooth remains available',
              ),
              subtitle: Text(
                'Installing Jarvis on another device does not replace Bluetooth. '
                'The cloud network handles Jarvis-to-Jarvis communication over the internet, '
                'while Bluetooth continues to handle nearby compatible hardware.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
