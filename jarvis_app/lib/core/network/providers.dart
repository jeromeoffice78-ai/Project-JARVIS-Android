import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/jarvis_chat_controller.dart';
import '../../features/capabilities/jarvis_action_approval_service.dart';
import '../../features/capabilities/jarvis_capability_service.dart';
import '../../features/vision/jarvis_vision_service.dart';
import '../../features/voice/jarvis_voice_controller.dart';
import '../../features/voice/jarvis_voice_service.dart';
import '../config/jarvis_config.dart';
import 'jarvis_api_service.dart';
import 'jarvis_ws_service.dart';

final jarvisConfigProvider = Provider<JarvisConfig>((Ref ref) {
  return JarvisConfig.fromEnvironment();
});

final jarvisWsServiceProvider =
    Provider<JarvisWsService>((Ref ref) {
  final JarvisConfig config =
      ref.watch(jarvisConfigProvider);

  final JarvisWsService service =
      JarvisWsService(
    wsUri: Uri.parse(config.wsUrl),
    ticketProvider: () async {
      final String token =
          config.clientToken.trim();
      return token.isEmpty ? null : token;
    },
  );

  ref.onDispose(() {
    unawaited(service.dispose());
  });

  return service;
});

final jarvisApiServiceProvider =
    Provider<JarvisApiService>((Ref ref) {
  final JarvisApiService service =
      JarvisApiService(
    config: ref.watch(jarvisConfigProvider),
  );

  ref.onDispose(service.dispose);

  return service;
});


final jarvisActionApprovalServiceProvider =
    Provider<JarvisActionApprovalService>((Ref ref) {
  final JarvisActionApprovalService service =
      JarvisActionApprovalService();

  ref.onDispose(() {
    unawaited(service.dispose());
  });

  return service;
});

final jarvisCapabilityServiceProvider =
    Provider<JarvisCapabilityService>((Ref ref) {
  final JarvisCapabilityService service =
      JarvisCapabilityService(
    approvalService: ref.watch(
      jarvisActionApprovalServiceProvider,
    ),
  );

  ref.onDispose(service.dispose);

  return service;
});

final jarvisChatControllerProvider =
    Provider<JarvisChatController>((Ref ref) {
  final JarvisChatController controller =
      JarvisChatController(
    wsService: ref.watch(
      jarvisWsServiceProvider,
    ),
    capabilityService: ref.watch(
      jarvisCapabilityServiceProvider,
    ),
  );

  ref.onDispose(() {
    unawaited(controller.dispose());
  });

  return controller;
});



final jarvisVoiceServiceProvider =
    Provider<JarvisVoiceService>((Ref ref) {
  final JarvisVoiceService service =
      JarvisVoiceService();

  ref.onDispose(() {
    unawaited(service.dispose());
  });

  return service;
});

final jarvisVoiceControllerProvider =
    Provider<JarvisVoiceController>((Ref ref) {
  final JarvisVoiceController controller =
      JarvisVoiceController(
    voiceService: ref.watch(
      jarvisVoiceServiceProvider,
    ),
    chatController: ref.watch(
      jarvisChatControllerProvider,
    ),
  );

  ref.onDispose(() {
    unawaited(controller.dispose());
  });

  return controller;
});

final jarvisVoiceStateProvider =
    StreamProvider<JarvisVoiceState>(
  (Ref ref) {
    return ref
        .watch(jarvisVoiceServiceProvider)
        .stateStream;
  },
);

final jarvisVisionServiceProvider =
    Provider<JarvisVisionService>((Ref ref) {
  final JarvisVisionService service =
      JarvisVisionService(
    apiService: ref.watch(
      jarvisApiServiceProvider,
    ),
  );

  ref.onDispose(() {
    unawaited(service.dispose());
  });

  return service;
});

final jarvisVisionStateProvider =
    StreamProvider<JarvisVisionState>(
  (Ref ref) {
    return ref
        .watch(jarvisVisionServiceProvider)
        .stateStream;
  },
);

final jarvisConnectionStateProvider =
    StreamProvider<JarvisConnectionState>(
  (Ref ref) {
    return ref
        .watch(jarvisWsServiceProvider)
        .connectionState;
  },
);

final jarvisWsErrorsProvider =
    StreamProvider<JarvisWsException>(
  (Ref ref) {
    return ref
        .watch(jarvisWsServiceProvider)
        .errors;
  },
);
