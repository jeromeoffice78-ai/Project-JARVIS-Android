import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/jarvis_chat_controller.dart';
import '../../features/autonomy/jarvis_autonomy_controller.dart';
import '../../features/capabilities/jarvis_action_approval_service.dart';
import '../../features/capabilities/jarvis_capability_service.dart';
import '../../features/devices/jarvis_bluetooth_manager.dart';
import '../../features/phone/jarvis_phone_service.dart';
import '../../features/printer/jarvis_printer_service.dart';
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

final jarvisBluetoothManagerProvider =
    Provider<JarvisBluetoothManager>((Ref ref) {
  final JarvisBluetoothManager manager =
      JarvisBluetoothManager();

  ref.onDispose(() {
    unawaited(manager.dispose());
  });

  return manager;
});

final jarvisBluetoothStateProvider =
    StreamProvider<JarvisBluetoothState>(
  (Ref ref) {
    return ref
        .watch(jarvisBluetoothManagerProvider)
        .stateStream;
  },
);

final jarvisPhoneServiceProvider =
    Provider<JarvisPhoneService>((Ref ref) {
  return JarvisPhoneService();
});

final jarvisPrinterServiceProvider =
    Provider<JarvisPrinterService>((Ref ref) {
  return JarvisPrinterService();
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

final jarvisAutonomyControllerProvider =
    Provider<JarvisAutonomyController>((Ref ref) {
  final JarvisAutonomyController controller =
      JarvisAutonomyController(
    chatController: ref.watch(
      jarvisChatControllerProvider,
    ),
    apiService: ref.watch(
      jarvisApiServiceProvider,
    ),
  );

  ref.onDispose(() {
    unawaited(controller.dispose());
  });

  return controller;
});

final jarvisAutonomyStateProvider =
    StreamProvider<JarvisAutonomyState>(
  (Ref ref) {
    return ref
        .watch(jarvisAutonomyControllerProvider)
        .stateStream;
  },
);

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

extension JarvisAsyncValueCompatibility<T> on AsyncValue<T> {
  T? get valueOrNull {
    final AsyncValue<T> current = this;
    return current is AsyncData<T> ? current.value : null;
  }
}
