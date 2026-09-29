import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../realtime/jarvis_realtime_voice_service.dart';
import 'jarvis_avatar_asset_server.dart';

class JarvisHumanAvatarView
    extends StatefulWidget {
  const JarvisHumanAvatarView({
    super.key,
    required this.voiceState,
    required this.active,
    this.showRecoveryControls = false,
  });

  final JarvisRealtimeVoiceState voiceState;
  final bool active;
  final bool showRecoveryControls;

  @override
  State<JarvisHumanAvatarView> createState() =>
      _JarvisHumanAvatarViewState();
}

class _JarvisHumanAvatarViewState
    extends State<JarvisHumanAvatarView> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _fallbackMode = false;
  String? _avatarDiagnostic;
  String? _errorMessage;
  int _retryCount = 0;
  bool _retryPending = false;
  static const int _maxAutomaticRetries = 2;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setBackgroundColor(
        Colors.transparent,
      )
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..addJavaScriptChannel(
        'JarvisAvatar',
        onMessageReceived:
            (JavaScriptMessage message) {
          try {
            final Object? decoded =
                jsonDecode(message.message);

            if (decoded is! Map) {
              return;
            }

            final Map<String, dynamic> data =
                Map<String, dynamic>.from(
              decoded,
            );

            if (data['type'] == 'ready') {
              if (mounted) {
                setState(() {
                  _ready = true;
                  _fallbackMode = data['mode'] == 'lightweight-human';
                  _errorMessage = null;
                });
              }
              _pushState();
            } else if (data['type'] == 'fallback') {
              if (mounted) {
                setState(() {
                  _ready = true;
                  _fallbackMode = true;
                  _avatarDiagnostic = data['reason']?.toString();
                  _errorMessage = null;
                });
              }
              _pushState();
            } else if (data['type'] == 'diagnostic') {
              if (mounted) {
                setState(() {
                  _avatarDiagnostic = data['message']?.toString();
                });
              }
            } else if (data['type'] ==
                'error') {
              if (mounted) {
                setState(() {
                  _errorMessage =
                      data['message']
                              ?.toString() ??
                          'Human avatar error.';
                });
              }
            }
          } on FormatException {
            // Ignore malformed bridge messages.
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError:
              (WebResourceError error) {
            if (!mounted || _ready) return;
            // Android WebView may report optional textures or a transient
            // glTF subresource as ERR_FAILED. The page handles model errors
            // with its built-in offline 3D backup. Only the main document
            // should trigger a WebView restart.
            if (error.isForMainFrame != true) return;
            unawaited(_retryMainPage(error.description));
          },
        ),
      );

    _loadAvatar();
  }

  Future<void> _retryMainPage(String reason) async {
    if (_ready || _retryPending || !mounted) return;
    if (_retryCount >= _maxAutomaticRetries) {
      setState(() {
        _errorMessage = 'Avatar page could not load: $reason';
      });
      return;
    }
    _retryPending = true;
    _retryCount++;
    await Future<void>.delayed(Duration(milliseconds: 350 * _retryCount));
    _retryPending = false;
    if (!mounted || _ready) return;
    await _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final Uri url = await JarvisAvatarAssetServer.avatarPage();
      await _controller.loadRequest(url);
    } on Object {
      if (!mounted) return;
      if (_retryCount < _maxAutomaticRetries) {
        unawaited(_retryMainPage('Bundled resources unavailable'));
      } else {
        setState(() {
          _errorMessage = 'Bundled human avatar files could not be opened.';
        });
      }
    }
  }

  @override
  void didUpdateWidget(
    JarvisHumanAvatarView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active ||
        oldWidget.voiceState.activity !=
            widget.voiceState.activity ||
        oldWidget.voiceState.mood !=
            widget.voiceState.mood ||
        oldWidget.voiceState.companionMode !=
            widget
                .voiceState.companionMode ||
        oldWidget.voiceState.isConnected !=
            widget.voiceState.isConnected ||
        oldWidget.voiceState.transcript !=
            widget.voiceState.transcript ||
        oldWidget.voiceState.remoteAudioLevel !=
            widget.voiceState.remoteAudioLevel ||
        oldWidget.voiceState.remoteAudioLevelAvailable !=
            widget.voiceState.remoteAudioLevelAvailable) {
      _pushState();
    }
  }

  Future<void> _pushState() async {
    if (!_ready) {
      return;
    }

    final Map<String, dynamic> payload =
        <String, dynamic>{
      'active': widget.active,
      'activity':
          widget.voiceState.activity.name,
      'mood': widget.voiceState.mood,
      'connected':
          widget.voiceState.isConnected,
      'companion':
          widget.voiceState.companionMode,
      'transcript':
          widget.voiceState.transcript,
      'audioLevel':
          widget.voiceState.remoteAudioLevel,
      'audioLevelAvailable':
          widget.voiceState.remoteAudioLevelAvailable,
    };

    await _controller.runJavaScript(
      'window.jarvisSetState(' +
          jsonEncode(payload) +
          ');',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WebViewWidget(
          controller: _controller,
        ),
        if (!_ready &&
            _errorMessage == null)
          const Center(
            child:
                CircularProgressIndicator(),
          ),
        if (_errorMessage != null && !_ready)
          Center(
            child: Card(
              color: const Color(0xFF091522),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 88,
                      color: Color(0xFF38E8FF),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Jarvis visual standby',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'The detailed avatar is unavailable. '
                      'Voice and chat remain independent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _retryCount = 0;
                          _ready = false;
                        });
                        unawaited(_loadAvatar());
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('RETRY AVATAR'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_fallbackMode && widget.showRecoveryControls)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xE30B1824),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      '3D model not available — branded visual standby',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_avatarDiagnostic?.isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        _avatarDiagnostic!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _ready = false;
                          _fallbackMode = false;
                          _avatarDiagnostic = null;
                          _errorMessage = null;
                          _retryCount = 0;
                        });
                        unawaited(_loadAvatar());
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('TRY FULL 3D AGAIN'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
