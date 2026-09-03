import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';

class JarvisDevicesScreen extends ConsumerWidget {
  const JarvisDevicesScreen({super.key});

  void _send(WidgetRef ref, String prompt) {
    ref
        .read(jarvisChatControllerProvider)
        .askJarvis(prompt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Text(
          'Device Controls',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Commands are routed through Jarvis, executed locally, '
          'then verified back to the AI before success is reported.',
        ),
        const SizedBox(height: 18),
        _DeviceActionCard(
          icon: Icons.flashlight_on,
          title: 'Flashlight',
          subtitle: 'Control the phone torch.',
          actions: <Widget>[
            FilledButton(
              onPressed: () => _send(
                ref,
                'Turn on my flashlight.',
              ),
              child: const Text('Turn On'),
            ),
            OutlinedButton(
              onPressed: () => _send(
                ref,
                'Turn off my flashlight.',
              ),
              child: const Text('Turn Off'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DeviceActionCard(
          icon: Icons.palette_outlined,
          title: 'Application Theme',
          subtitle: 'Switch Jarvis between light and dark mode.',
          actions: <Widget>[
            FilledButton.tonal(
              onPressed: () => _send(
                ref,
                'Change the Jarvis app theme to dark mode.',
              ),
              child: const Text('Dark'),
            ),
            FilledButton.tonal(
              onPressed: () => _send(
                ref,
                'Change the Jarvis app theme to light mode.',
              ),
              child: const Text('Light'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Card(
          child: ListTile(
            leading: Icon(Icons.security),
            title: Text('Verified Execution'),
            subtitle: Text(
              'Unsupported device commands are rejected. '
              'Every supported action returns a tool_result '
              'to the backend.',
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceActionCard extends StatelessWidget {
  const _DeviceActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                      ),
                      Text(subtitle),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
