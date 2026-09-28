import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/jarvis_chairman_auth.dart';
import '../../core/network/jarvis_ws_service.dart';
import '../../core/network/providers.dart';
import '../chat/jarvis_chat_controller.dart';
import '../chat/jarvis_chat_screen.dart';
import '../autonomy/jarvis_autonomy_screen.dart';
import '../capabilities/jarvis_action_approval_service.dart';
import '../devices/jarvis_devices_screen.dart';
import '../frontier/jarvis_frontier_screen.dart';
import '../presence/jarvis_presence_screen.dart';
import '../presence/jarvis_ambient_avatar_layer.dart';
import '../presence/jarvis_system_overlay_sync.dart';
import '../memory/jarvis_memory_screen.dart';
import '../music/jarvis_music_now_playing.dart';
import '../people/people_memory_screen.dart';
import '../phone/jarvis_phone_screen.dart';
import '../system/jarvis_system_screen.dart';
import '../vision/jarvis_vision_screen.dart';
import '../voice/jarvis_voice_screen.dart';

class JarvisShell extends ConsumerStatefulWidget {
  const JarvisShell({super.key});

  @override
  ConsumerState<JarvisShell> createState() =>
      _JarvisShellState();
}

class _JarvisShellState
    extends ConsumerState<JarvisShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _openingPhoneScreen = false;

  StreamSubscription<JarvisActionApprovalRequest>?
      _approvalSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeLaunchTarget()),
    );

    // Start printer presence/heartbeat immediately with the Jarvis shell so
    // cross-device routing knows which Android device currently hosts a printer.
    ref.read(jarvisPrintRouterProvider);

    // Keep the internet-based Jarvis device network active for
    // cross-device commands even when the Devices tab is not open.
    ref.read(jarvisCloudDeviceNetworkProvider);

    ref.read(jarvisVoiceControllerProvider);

    _approvalSubscription = ref
        .read(
          jarvisActionApprovalServiceProvider,
        )
        .requests
        .listen(
      (JarvisActionApprovalRequest request) {
        unawaited(
          _showApprovalDialog(request),
        );
      },
    );
  }

  Future<void> _consumeLaunchTarget() async {
    final String target = await ref
        .read(jarvisPhoneServiceProvider)
        .consumeLaunchTarget();

    if (!mounted ||
        target != 'phone' ||
        _openingPhoneScreen) {
      return;
    }

    _openingPhoneScreen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const JarvisPhoneScreen(),
        ),
      );
    } finally {
      _openingPhoneScreen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumeLaunchTarget());
    }
  }

  Future<void> _showApprovalDialog(
    JarvisActionApprovalRequest request,
  ) async {
    if (!mounted) {
      ref
          .read(
            jarvisActionApprovalServiceProvider,
          )
          .resolve(
            request.id,
            false,
          );
      return;
    }

    final bool approved =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (
            BuildContext dialogContext,
          ) {
            return AlertDialog(
              title: Text(request.title),
              content: SingleChildScrollView(
                child: Text(
                  request.description,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      Navigator.of(
                    dialogContext,
                  ).pop(false),
                  child:
                      const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(
                    dialogContext,
                  ).pop(true),
                  child:
                      const Text('Approve'),
                ),
              ],
            );
          },
        ) ??
        false;

    ref
        .read(
          jarvisActionApprovalServiceProvider,
        )
        .resolve(
          request.id,
          approved,
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _approvalSubscription?.cancel();
    _approvalSubscription = null;
    super.dispose();
  }

  static const List<Widget> _screens =
      <Widget>[
    JarvisChatScreen(),
    JarvisVoiceScreen(),
    JarvisMemoryScreen(),
    JarvisDevicesScreen(),
    JarvisVisionScreen(),
    PeopleMemoryScreen(),
    JarvisSystemScreen(),
  ];

  static const List<String> _titles =
      <String>[
    'Command Center',
    'Voice',
    'Memory',
    'Device Control',
    'Camera Vision',
    'People Memory',
    'System',
  ];

  @override
  Widget build(BuildContext context) {
    final AsyncValue<JarvisConnectionState>
        connectionValue = ref.watch(
      jarvisConnectionStateProvider,
    );

    final JarvisConnectionState connection =
        connectionValue.valueOrNull ??
            ref
                .read(jarvisWsServiceProvider)
                .currentState;

    final AsyncValue<JarvisChatState> chatSnapshot =
        ref.watch(jarvisChatStateProvider);
    final JarvisChatState chatState = chatSnapshot.valueOrNull ??
        ref.watch(jarvisChatControllerProvider).state;
    final bool chatIsShowingAnError =
        chatState.status == JarvisChatStatus.error;
    final bool keyboardIsOpen =
        MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/branding/jarvis_ai_assistant_brand_icon.png',
                fit: BoxFit.cover,
                semanticLabel: 'JARVIS AI Assistant brand logo',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'JARVIS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    _titles[_index],
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          // Local Jarvis is always available; only owner-only cloud actions
          // require optional Google or email verification.
          ValueListenableBuilder<int>(
            valueListenable: JarvisAuthSession.sessionRevision,
            builder: (BuildContext context, int revision, Widget? child) {
              final bool signedIn =
                  JarvisAuthSession.currentToken.isNotEmpty;
              return IconButton(
                tooltip: signedIn
                    ? 'Owner account and sign-out options'
                    : 'Sign in to Jarvis',
                icon: Icon(
                  signedIn
                      ? Icons.verified_user_outlined
                      : Icons.account_circle_outlined,
                ),
                onPressed: JarvisAuthSession.requestSignIn,
              );
            },
          ),
          IconButton(
            tooltip: 'Jarvis Presence',
            icon: const Icon(
              Icons.face_retouching_natural,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const JarvisPresenceScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Frontier AI',
            icon: const Icon(
              Icons.hub_outlined,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const JarvisFrontierScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Autonomous Agent',
            icon: const Icon(
              Icons.auto_awesome,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const JarvisAutonomyScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _ConnectionBanner(
                state: connection,
              ),
              const _MemoryBanner(),
              const JarvisMusicNowPlaying(),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: _screens,
                ),
              ),
            ],
          ),
          // The roaming avatar should not cover microphone, diagnostics, or
          // other interactive controls on the Voice and settings tabs.
          // Keep the message and any error fully legible. The roaming
          // character returns automatically when the keyboard is dismissed
          // and the next conversation begins.
          if (_index == 0 && !keyboardIsOpen && !chatIsShowingAnError)
            const Positioned.fill(
              child: JarvisAmbientAvatarLayer(),
            ),
          const JarvisSystemOverlaySync(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) {
          setState(() => _index = value);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Memory',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_other_outlined),
            selectedIcon: Icon(Icons.devices_other),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.visibility_outlined),
            selectedIcon: Icon(Icons.visibility),
            label: 'Vision',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'System',
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner({
    required this.state,
  });

  final JarvisConnectionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connected =
        state == JarvisConnectionState.connected;

    final Color statusColor = switch (state) {
      JarvisConnectionState.connected =>
        Colors.greenAccent,
      JarvisConnectionState.connecting ||
      JarvisConnectionState.reconnecting =>
        Colors.amberAccent,
      JarvisConnectionState.closing =>
        Colors.orangeAccent,
      JarvisConnectionState.disconnected =>
        Colors.redAccent,
    };

    return Material(
      color: statusColor.withValues(alpha: 0.08),
      child: InkWell(
        onTap: connected
            ? null
            : () {
                ref.invalidate(
                  jarvisConnectionStateProvider,
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 7,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                connected
                    ? Icons.cloud_done
                    : Icons.cloud_off,
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Jarvis Network: '
                  '${state.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!connected)
                const Icon(
                  Icons.refresh,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryBanner extends StatelessWidget {
  const _MemoryBanner();

  @override
  Widget build(BuildContext context) {
    final Color color =
        Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 6,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(
            color: color.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.psychology,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Jarvis Memory Engine: Persistent',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
