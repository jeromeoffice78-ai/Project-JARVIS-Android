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
        await ref.read(jarvisWsServiceProvider).connect();
      } on Object {
        // The service owns reconnect/error state; the UI remains usable offline.
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
