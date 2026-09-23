import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class JarvisShareScreen extends StatelessWidget {
  const JarvisShareScreen({super.key});

  static const String apkUrl =
      'https://github.com/jeromeoffice78-ai/Project-JARVIS-Android/releases/download/jarvis-latest/JARVIS-v1.2-debug.apk';

  static const String releaseUrl =
      'https://github.com/jeromeoffice78-ai/Project-JARVIS-Android/releases/tag/jarvis-latest';

  Future<void> _share(BuildContext context) async {
    final RenderBox? box =
        context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        title: 'Install JARVIS',
        subject: 'JARVIS Android installer',
        text:
            'Install the latest verified JARVIS Android build:\n$apkUrl',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) &
                box.size,
      ),
    );
  }

  Future<void> _openInstaller(
    BuildContext context,
  ) async {
    final bool opened = await launchUrl(
      Uri.parse(apkUrl),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the installer link.',
          ),
        ),
      );
    }
  }

  Future<void> _openRelease(
    BuildContext context,
  ) async {
    final bool opened = await launchUrl(
      Uri.parse(releaseUrl),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the JARVIS release page.',
          ),
        ),
      );
    }
  }

  Future<void> _copyLink(
    BuildContext context,
  ) async {
    await Clipboard.setData(
      const ClipboardData(text: apkUrl),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'JARVIS installer link copied.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send JARVIS'),
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
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The other Android device does not need Bluetooth or direct pairing. '
            'Open the installer link or scan the QR code, install JARVIS, then the '
            'new device can register itself on the cloud device network.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  Container(
                    padding:
                        const EdgeInsets.all(14),
                    color: Colors.white,
                    child: const QrImageView(
                      data: apkUrl,
                      version: QrVersions.auto,
                      size: 220,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Scan this QR code with the other device.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _openInstaller(context),
            icon:
                const Icon(Icons.download_outlined),
            label: const Text(
              'Download Latest APK',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.share_outlined),
            label: const Text(
              'Share Installer Link',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _copyLink(context),
            icon:
                const Icon(Icons.content_copy),
            label: const Text(
              'Copy Installer Link',
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _openRelease(context),
            icon:
                const Icon(Icons.open_in_new),
            label: const Text(
              'Open Release Page',
            ),
          ),
          const SizedBox(height: 18),
          const Card(
            child: ListTile(
              leading:
                  Icon(Icons.security_outlined),
              title: Text(
                'Android installation note',
              ),
              subtitle: Text(
                'Android may ask you to allow installs from your browser or file manager. '
                'Only use the JARVIS release link shown in this app.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
