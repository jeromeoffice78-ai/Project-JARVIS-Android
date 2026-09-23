import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../realtime/jarvis_realtime_voice_service.dart';
import 'jarvis_avatar_behavior.dart';

class JarvisTalkingAvatar extends StatefulWidget {
  const JarvisTalkingAvatar({
    super.key,
    required this.behavior,
    required this.voice,
  });

  final JarvisAvatarBehavior behavior;
  final JarvisRealtimeVoiceState voice;

  @override
  State<JarvisTalkingAvatar> createState() =>
      _JarvisTalkingAvatarState();
}

class _JarvisTalkingAvatarState
    extends State<JarvisTalkingAvatar> {
  late final WebViewController _controller;
  Timer? _fallbackTimer;
  bool _ready = false;
  bool _failed = false;
  String _lastTranscript = '';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setBackgroundColor(
        Colors.transparent,
      )
      ..addJavaScriptChannel(
        'JarvisAvatarBridge',
        onMessageReceived: (
          JavaScriptMessage message,
        ) {
          if (!mounted) {
            return;
          }

          if (message.message == 'ready') {
            _fallbackTimer?.cancel();
            setState(() {
              _ready = true;
              _failed = false;
            });
            unawaited(_syncAvatarState());
            return;
          }

          if (message.message
              .startsWith('error:')) {
            _fallbackTimer?.cancel();
            setState(() {
              _failed = true;
            });
          }
        },
      )
      ..loadHtmlString(_avatarHtml);

    _fallbackTimer = Timer(
      const Duration(seconds: 16),
      () {
        if (mounted && !_ready) {
          setState(() {
            _failed = true;
          });
        }
      },
    );
  }

  @override
  void didUpdateWidget(
    covariant JarvisTalkingAvatar oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (_ready &&
        (oldWidget.behavior.expression !=
                widget.behavior.expression ||
            oldWidget.behavior.motion !=
                widget.behavior.motion ||
            oldWidget.behavior.energy !=
                widget.behavior.energy ||
            oldWidget.voice.activity !=
                widget.voice.activity ||
            oldWidget.voice.mood !=
                widget.voice.mood ||
            oldWidget.voice.transcript !=
                widget.voice.transcript)) {
      unawaited(_syncAvatarState());
    }
  }

  Future<void> _syncAvatarState() async {
    if (!_ready || _failed) {
      return;
    }

    final String mood =
        _talkingHeadMood(widget.behavior);
    final String activity =
        widget.voice.activity.name;
    final bool walking =
        widget.behavior.motion ==
            JarvisAvatarMotion.pace;
    final String gesture =
        _gestureFor(widget.behavior);

    final String script =
        'window.jarvisSetState(' +
        jsonEncode(mood) +
        ',' +
        jsonEncode(activity) +
        ',' +
        (walking ? 'true' : 'false') +
        ',' +
        jsonEncode(gesture) +
        ');';

    try {
      await _controller.runJavaScript(
        script,
      );

      if (widget.voice.activity ==
              JarvisConversationActivity.speaking &&
          widget.voice.transcript !=
              _lastTranscript) {
        _lastTranscript =
            widget.voice.transcript;
        await _controller.runJavaScript(
          'window.jarvisSpeechPulse();',
        );
      } else if (widget.voice.activity !=
          JarvisConversationActivity.speaking) {
        _lastTranscript =
            widget.voice.transcript;
      }
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  String _talkingHeadMood(
    JarvisAvatarBehavior behavior,
  ) {
    switch (behavior.expression) {
      case JarvisAvatarExpression.warm:
        return 'love';
      case JarvisAvatarExpression.energetic:
        return 'happy';
      case JarvisAvatarExpression.intense:
        return 'angry';
      case JarvisAvatarExpression.serious:
      case JarvisAvatarExpression.thinking:
      case JarvisAvatarExpression.attentive:
      case JarvisAvatarExpression.speaking:
      case JarvisAvatarExpression.confident:
      case JarvisAvatarExpression.neutral:
        return 'neutral';
    }
  }

  String _gestureFor(
    JarvisAvatarBehavior behavior,
  ) {
    switch (behavior.expression) {
      case JarvisAvatarExpression.energetic:
        return 'thumbup';
      case JarvisAvatarExpression.warm:
        return 'side';
      case JarvisAvatarExpression.intense:
        return 'index';
      case JarvisAvatarExpression.attentive:
        return 'handup';
      case JarvisAvatarExpression.serious:
      case JarvisAvatarExpression.thinking:
      case JarvisAvatarExpression.speaking:
      case JarvisAvatarExpression.confident:
      case JarvisAvatarExpression.neutral:
        return '';
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const ModelViewer(
        src: 'assets/models/CesiumMan.glb',
        alt: 'Animated 3D Jarvis humanoid',
        autoPlay: true,
        autoRotate: false,
        cameraControls: true,
        disableZoom: false,
        backgroundColor: Colors.transparent,
        loading: Loading.eager,
        reveal: Reveal.auto,
        interactionPrompt:
            InteractionPrompt.none,
        cameraOrbit: '0deg 75deg 2.2m',
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WebViewWidget(
          controller: _controller,
        ),
        if (!_ready)
          const IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child:
                    CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}

const String _avatarHtml = r'''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport"
      content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body {
    margin: 0;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: transparent;
  }

  #avatar {
    width: 100%;
    height: 100%;
    background: transparent;
  }
</style>
<script type="importmap">
{
  "imports": {
    "three": "https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js/+esm",
    "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/",
    "talkinghead": "https://cdn.jsdelivr.net/gh/met4citizen/TalkingHead@1.7/modules/talkinghead.mjs"
  }
}
</script>
<script type="module">
import { TalkingHead } from "talkinghead";

let head = null;
let currentWalking = false;
let lastGesture = "";
let lastActivity = "";

const walkUrl =
  "https://cdn.jsdelivr.net/gh/met4citizen/TalkingHead@1.7/animations/walking.fbx";

async function startAvatar() {
  const nodeAvatar =
    document.getElementById("avatar");

  head = new TalkingHead(nodeAvatar, {
    cameraView: "full",
    modelFPS: 30,
    modelPixelRatio:
      Math.min(window.devicePixelRatio || 1, 1.6),
    avatarIdleEyeContact: 0.72,
    avatarSpeakingEyeContact: 0.94,
    avatarIdleHeadMove: 0.25,
    avatarSpeakingHeadMove: 0.55,
    lightAmbientIntensity: 2.5,
    lightDirectIntensity: 22,
    lightSpotIntensity: 1.5
  });

  await head.showAvatar({
    url:
      "https://cdn.jsdelivr.net/gh/met4citizen/TalkingHead@1.7/avatars/avatarsdk.glb",
    body: "M",
    avatarMood: "neutral",
    retarget: {
      Neck: { z: -0.01, rx: -0.15 },
      Neck1: { z: -0.01, rx: -0.15 },
      Neck2: { z: -0.01, rx: -0.15 },
      LeftShoulder: { rz: -0.3 },
      RightShoulder: { rz: 0.3 },
      scaleToEyesLevel: 1.0,
      origin: { y: -0.1 }
    },
    baseline: {
      headRotateX: -0.04,
      eyeBlinkLeft: 0.05,
      eyeBlinkRight: 0.05
    }
  });

  try {
    head.setView("full");
  } catch (_) {}

  // A neutral mouth-shape animation used as a cadence pulse.
  // Realtime transcript deltas from Flutter trigger this while
  // Jarvis is speaking, so the mouth visibly articulates without
  // creating a second TTS/audio stream.
  head.animEmojis["jarvis-talk"] = {
    dt: [70, 100, 90, 110],
    rescale: [0, 1, 0.35, 0],
    vs: {
      jawOpen: [0.05, 0.36, 0.14, 0.05],
      mouthOpen: [0.04, 0.28, 0.1, 0.04],
      mouthStretchLeft: [0.04, 0.13, 0.07, 0.04],
      mouthStretchRight: [0.04, 0.13, 0.07, 0.04]
    }
  };

  window.jarvisSpeechPulse = function() {
    if (!head) return;
    try {
      head.playGesture(
        "jarvis-talk",
        0.42,
        false,
        55
      );
    } catch (_) {}
  };

  window.jarvisSetState =
    async function(mood, activity, walking, gesture) {
      if (!head) return;

      try {
        head.setMood(mood || "neutral");
      } catch (_) {}

      if (walking !== currentWalking) {
        currentWalking = walking;
        try {
          if (walking) {
            head.playAnimation(
              walkUrl,
              null,
              8,
              0,
              0.01
            );
          } else {
            head.stopAnimation();
          }
        } catch (_) {}
      }

      if (gesture &&
          gesture !== lastGesture &&
          activity === "speaking") {
        lastGesture = gesture;
        try {
          head.playGesture(
            gesture,
            2.4,
            false,
            450
          );
        } catch (_) {}
      }

      if (activity !== lastActivity) {
        lastActivity = activity;

        if (activity === "listening" ||
            activity === "speaking") {
          try {
            head.lookAtCamera(
              activity === "speaking"
                ? 400
                : 700
            );
          } catch (_) {}
        }
      }

      if (!gesture) {
        lastGesture = "";
      }
    };

  if (window.JarvisAvatarBridge) {
    window.JarvisAvatarBridge.postMessage(
      "ready"
    );
  }
}

document.addEventListener(
  "DOMContentLoaded",
  () => {
    startAvatar().catch((error) => {
      if (window.JarvisAvatarBridge) {
        window.JarvisAvatarBridge.postMessage(
          "error:" +
          String(error)
        );
      }
    });
  }
);

document.addEventListener(
  "visibilitychange",
  () => {
    if (!head) return;

    if (document.visibilityState === "visible") {
      head.start();
    } else {
      head.stop();
    }
  }
);
</script>
</head>
<body>
  <div id="avatar"></div>
</body>
</html>
''';
