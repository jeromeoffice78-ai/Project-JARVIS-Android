import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../realtime/jarvis_realtime_voice_service.dart';

class JarvisHumanAvatarView
    extends StatefulWidget {
  const JarvisHumanAvatarView({
    super.key,
    required this.voiceState,
    required this.active,
  });

  final JarvisRealtimeVoiceState voiceState;
  final bool active;

  @override
  State<JarvisHumanAvatarView> createState() =>
      _JarvisHumanAvatarViewState();
}

class _JarvisHumanAvatarViewState
    extends State<JarvisHumanAvatarView> {
  late final WebViewController _controller;
  bool _ready = false;
  String? _errorMessage;

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
                  _errorMessage = null;
                });
              }
              _pushState();
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
            if (!mounted) {
              return;
            }

            setState(() {
              _errorMessage =
                  error.description;
            });
          },
        ),
      )
      ..loadFlutterAsset(
        'assets/avatar/jarvis_human_avatar.html',
      );
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
            widget.voiceState.transcript) {
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
        if (_errorMessage != null)
          Center(
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding:
                    const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.warning_amber,
                      color:
                          Colors.amberAccent,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Human avatar runtime needs attention',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _errorMessage!,
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color:
                            Colors.white70,
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
