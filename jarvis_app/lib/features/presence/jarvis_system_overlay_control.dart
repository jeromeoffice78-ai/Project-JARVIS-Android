import 'dart:async';

import 'package:flutter/material.dart';

import '../realtime/jarvis_realtime_voice_service.dart';
import 'jarvis_system_overlay_service.dart';

class JarvisSystemOverlayControl
    extends StatefulWidget {
  const JarvisSystemOverlayControl({
    super.key,
    required this.voiceState,
    required this.active,
  });

  final JarvisRealtimeVoiceState voiceState;
  final bool active;

  @override
  State<JarvisSystemOverlayControl>
      createState() =>
          _JarvisSystemOverlayControlState();
}

class _JarvisSystemOverlayControlState
    extends State<JarvisSystemOverlayControl>
    with WidgetsBindingObserver {
  static const JarvisSystemOverlayService
      _overlay =
      JarvisSystemOverlayService();

  bool _permissionGranted = false;
  bool _running = false;
  bool _busy = true;
  bool _startAfterPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(
    JarvisSystemOverlayControl oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (_running &&
        (
          oldWidget.active != widget.active ||
          oldWidget.voiceState.activity !=
              widget.voiceState.activity ||
          oldWidget.voiceState.mood !=
              widget.voiceState.mood ||
          oldWidget.voiceState.companionMode !=
              widget.voiceState.companionMode ||
          oldWidget.voiceState.transcript !=
              widget.voiceState.transcript ||
          oldWidget.voiceState.remoteAudioLevel !=
              widget.voiceState.remoteAudioLevel ||
          oldWidget.voiceState
                  .remoteAudioLevelAvailable !=
              widget.voiceState
                  .remoteAudioLevelAvailable
        )) {
      unawaited(
        _overlay.updateAvatarState(
          voiceState: widget.voiceState,
          active: widget.active,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeFromSettings());
    }
  }

  Future<void> _resumeFromSettings() async {
    await _refresh();

    if (
        _startAfterPermission &&
        _permissionGranted &&
        !_running) {
      _startAfterPermission = false;
      await _setEnabled(true);
    }
  }

  Future<void> _refresh() async {
    final JarvisSystemOverlayStatus status =
        await _overlay.status();

    if (!mounted) {
      return;
    }

    setState(() {
      _permissionGranted =
          status.permissionGranted;
      _running = status.running;
      _busy = false;
    });
  }

  Future<void> _setEnabled(
    bool enabled,
  ) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    if (enabled) {
      final JarvisSystemOverlayStatus current =
          await _overlay.status();

      if (!current.permissionGranted) {
        _startAfterPermission = true;
        await _overlay.openPermissionSettings();

        if (!mounted) {
          return;
        }

        setState(() {
          _permissionGranted = false;
          _running = false;
          _busy = false;
        });

        return;
      }

      await _overlay.start(
        voiceState: widget.voiceState,
        active: widget.active,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 250),
      );
    } else {
      _startAfterPermission = false;
      await _overlay.stop();
    }

    await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle =
        !_permissionGranted
            ? 'Android permission is required once. JARVIS will open Display over other apps so you can approve it.'
            : _running
                ? 'JARVIS can now walk over the Android home screen and other apps. The overlay never captures taps.'
                : 'Permission approved. Turn this on to keep JARVIS visible outside the app.';

    return Card(
      color: Colors.white
          .withValues(alpha: 0.06),
      child: SwitchListTile(
        value: _running,
        onChanged:
            _busy ? null : _setEnabled,
        secondary: Icon(
          _running
              ? Icons.picture_in_picture_alt
              : Icons.layers_outlined,
          color: _running
              ? Colors.lightBlueAccent
              : Colors.white70,
        ),
        title: const Text(
          'Float JARVIS over other apps',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white60,
          ),
        ),
      ),
    );
  }
}
