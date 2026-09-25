import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'jarvis_signed_release.dart';

class JarvisShareScreen extends StatefulWidget {
  const JarvisShareScreen({super.key});

  @override
  State<JarvisShareScreen> createState() =>
      _JarvisShareScreenState();
}

class _JarvisShareScreenState
    extends State<JarvisShareScreen> {
  final JarvisSignedReleaseService _service =
      JarvisSignedReleaseService();

  JarvisSignedRelease _release =
      JarvisSignedRelease.verifiedFallback;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final JarvisSignedRelease latest =
          await _service.latest();
      if (!mounted) return;

      setState(() {
        _release = latest;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _share(
    BuildContext buttonContext,
  ) async {
    final RenderBox? box =
        buttonContext.findRenderObject()
            as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        title: 'Install JARVIS AI Assistant',
        subject:
            'Verified production-signed JARVIS Android app',
        text:
            'Install JARVIS on your Android device using '
            'this verified production-signed release:\n'
            + _release.apkUrl
            + '\n\nSign in with your authorized '
                'JARVIS Google account after installation.',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(
                  Offset.zero,
                ) &
                box.size,
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: _release.apkUrl,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Signed JARVIS installer link copied.',
        ),
      ),
    );
  }

  Future<void> _open(
    String url,
  ) async {
    final bool opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the installer link.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Send JARVIS',
        ),
        actions: <Widget>[
          IconButton(
            tooltip:
                'Refresh signed release',
            onPressed:
                _loading ? null : _refresh,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Install JARVIS on another device',
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
            'This screen only shares a production-signed '
            'JARVIS release. It never exports an older '
            'debug APK or embeds your personal account '
            'credentials in the sharing link.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(
                        Icons.verified_outlined,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Verified signed installer',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  SelectableText(
                    _release.tag,
                    textAlign:
                        TextAlign.center,
                  ),
                  if (_loading) ...[
                    const SizedBox(
                      height: 12,
                    ),
                    const LinearProgressIndicator(),
                    const Text(
                      'Checking for newer signed releases...',
                    ),
                  ],
                  const SizedBox(
                    height: 16,
                  ),
                  Container(
                    padding:
                        const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: _release.apkUrl,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'Scan with your other Android '
                    'device to download and install.',
                    textAlign:
                        TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () =>
                _open(_release.apkUrl),
            icon: const Icon(
              Icons.download_outlined,
            ),
            label: const Text(
              'Download Signed JARVIS APK',
            ),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (
              BuildContext buttonContext,
            ) {
              return OutlinedButton.icon(
                onPressed: () =>
                    _share(buttonContext),
                icon: const Icon(
                  Icons.share_outlined,
                ),
                label: const Text(
                  'Send Download Link',
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _copy,
            icon: const Icon(
              Icons.content_copy,
            ),
            label: const Text(
              'Copy Download Link',
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () =>
                _open(_release.releaseUrl),
            icon: const Icon(
              Icons.open_in_new,
            ),
            label: const Text(
              'View Verified Release',
            ),
          ),
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.warning_amber,
                ),
                title: const Text(
                  'Release lookup failed',
                ),
                subtitle: Text(_error!),
              ),
            ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.info_outline,
              ),
              title: Text(
                'Android installation',
              ),
              subtitle: Text(
                'The signed installer is for ARM64 '
                'Android devices. Open the APK '
                'download and permit installation '
                'from that browser or file manager '
                'when Android asks. If you have an '
                'older debug-signed JARVIS app, '
                'Android may require removing it '
                'before installing this differently '
                'signed production build. Back up '
                'important local data first.',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(
                Icons.cloud_outlined,
              ),
              title: Text(
                'Cloud and Bluetooth both stay',
              ),
              subtitle: Text(
                'After sign-in, the new device can '
                'register on the JARVIS cloud network '
                'using internet access. Bluetooth '
                'continues to work separately with '
                'nearby compatible devices.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
