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
  bool _lightweightMode = false;
  bool _detailedLoading = false;
  String? _avatarDiagnostic;
  String? _errorMessage;
  int _retryCount = 0;
  bool _retryPending = false;
  Timer? _pageWatchdog;
  Timer? _statePushTimer;
  bool _statePushInFlight = false;
  bool _statePushPending = false;
  int _loadGeneration = 0;
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
              _pageWatchdog?.cancel();
              if (mounted) {
                setState(() {
                  _ready = true;
                  _lightweightMode = data['mode'] == 'lightweight-human';
                  _fallbackMode = false;
                  _detailedLoading = false;
                  if (!_lightweightMode) _avatarDiagnostic = null;
                  _errorMessage = null;
                });
              }
              _pushState(immediate: true);
            } else if (data['type'] == 'fallback') {
              _pageWatchdog?.cancel();
              if (mounted) {
                setState(() {
                  _ready = true;
                  _fallbackMode = true;
                  _lightweightMode = false;
                  _detailedLoading = false;
                  _avatarDiagnostic = data['reason']?.toString();
                  _errorMessage = null;
                });
              }
              _pushState(immediate: true);
            } else if (data['type'] == 'detail-loading') {
              if (mounted) {
                setState(() {
                  _detailedLoading = true;
                  _avatarDiagnostic = null;
                });
              }
            } else if (data['type'] == 'detail-error') {
              if (mounted) {
                setState(() {
                  _detailedLoading = false;
                  _avatarDiagnostic = data['message']?.toString();
                });
              }
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
    final int generation = ++_loadGeneration;
    _pageWatchdog?.cancel();
    // WebView can leave a failed module page blank without reporting a main
    // frame error. Give the bundled renderer time to start, then recover.
    _pageWatchdog = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready && generation == _loadGeneration) {
        unawaited(_retryMainPage('3D page did not respond'));
      }
    });
    try {
      final Uri url = await JarvisAvatarAssetServer.avatarPage();
      if (!mounted || generation != _loadGeneration) return;
      // Ambient and system-floating avatars load only the lightweight human.
      // Full-screen presence can upgrade after the working 3D figure appears.
      await _controller.loadRequest(
        widget.showRecoveryControls
            ? url.replace(queryParameters: const <String, String>{
                'detail': '1',
              })
            : url,
      );
    } on Object {
      if (generation != _loadGeneration) return;
      _pageWatchdog?.cancel();
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

  void _pushState({bool immediate = false}) {
    if (!_ready || !mounted) {
      return;
    }

    if (immediate) {
      _statePushTimer?.cancel();
      _statePushTimer = null;
      unawaited(_sendState());
      return;
    }

    // Audio level changes can arrive much faster than the display refreshes.
    // Send the latest widget state at most once per 33 ms window.
    _statePushTimer ??= Timer(const Duration(milliseconds: 33), () {
      _statePushTimer = null;
      if (_ready && mounted) unawaited(_sendState());
    });
  }

  Future<void> _sendState() async {
    if (!_ready || !mounted) return;
    if (_statePushInFlight) {
      _statePushPending = true;
      return;
    }
    _statePushInFlight = true;

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

    try {
      await _controller.runJavaScript(
        'window.jarvisSetState?.(' + jsonEncode(payload) + ');',
      );
    } on Object {
      // WebView can be replaced by Android while a voice frame is in flight.
      // The next page-ready event sends the latest state again.
    } finally {
      _statePushInFlight = false;
      if (_statePushPending && mounted && _ready) {
        _statePushPending = false;
        _pushState();
      }
    }
  }

  @override
  void dispose() {
    _pageWatchdog?.cancel();
    _statePushTimer?.cancel();
    super.dispose();
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
        if ((_fallbackMode || _lightweightMode) &&
            widget.showRecoveryControls)
          Positioned(
            top: 6,
            left: 12,
            right: 12,
            child: Material(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xDE0B1824),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _fallbackMode
                          ? '3D unavailable — visual standby'
                          : _detailedLoading
                              ? 'Animated 3D online · upgrading detail…'
                              : 'Animated 3D online',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_avatarDiagnostic?.isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        _avatarDiagnostic!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: _detailedLoading
                          ? null
                          : () {
                              if (_fallbackMode) {
                                setState(() {
                                  _ready = false;
                                  _fallbackMode = false;
                                  _lightweightMode = false;
                                  _avatarDiagnostic = null;
                                  _errorMessage = null;
                                  _retryCount = 0;
                                });
                                unawaited(_loadAvatar());
                              } else {
                                unawaited(_controller.runJavaScript(
                                  'window.jarvisTryDetailedModel?.();',
                                ));
                              }
                            },
                      icon: const Icon(Icons.refresh, size: 17),
                      label: Text(
                        _fallbackMode
                            ? 'RETRY 3D'
                            : _detailedLoading
                                ? 'LOADING…'
                                : 'LOAD HIGH DETAIL',
                      ),
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
