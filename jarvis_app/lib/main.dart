import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/providers.dart';
import 'core/theme/jarvis_theme.dart';
import 'features/dashboard/jarvis_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: JarvisBootstrap()));
}

class JarvisBootstrap extends ConsumerStatefulWidget {
  const JarvisBootstrap({super.key});

  @override
  ConsumerState<JarvisBootstrap> createState() => _JarvisBootstrapState();
}

class _JarvisBootstrapState extends ConsumerState<JarvisBootstrap> {
  @override
  void initState() {
    super.initState();

    Future<void>.microtask(() async {
      try {
        await ref
            .read(jarvisApiServiceProvider)
            .health()
            .timeout(
              const Duration(seconds: 20),
            );
      } on Object {
        // The UI remains usable while the backend wakes or reconnects.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(jarvisChatControllerProvider);

    return StreamBuilder<ThemeMode>(
      stream: controller.themeModeStream,
      initialData: ThemeMode.dark,
      builder: (context, snapshot) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Project Jarvis',
          theme: JarvisTheme.light,
          darkTheme: JarvisTheme.dark,
          themeMode: snapshot.data ?? ThemeMode.dark,
          home: const JarvisShell(),
        );
      },
    );
  }
}
