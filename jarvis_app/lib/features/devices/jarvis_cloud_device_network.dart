import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torch_light/torch_light.dart';

import '../../core/config/jarvis_config.dart';
import '../music/jarvis_music_service.dart';
import '../printer/jarvis_printer_service.dart';
import '../security/jarvis_device_repair_service.dart';
import '../system_control/jarvis_system_control_service.dart';
import '../vision/jarvis_vision_service.dart';
import '../voice/jarvis_voice_service.dart';

final class JarvisCloudDevice {
  const JarvisCloudDevice({
    required this.deviceId,
    required this.deviceName,
    required this.online,
    required this.foreground,
    required this.activeAvatar,
    required this.capabilities,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final bool online;
  final bool foreground;
  final bool activeAvatar;
  final Map<String, dynamic> capabilities;
  final DateTime? lastSeenAt;

  factory JarvisCloudDevice.fromJson(
    Map<String, dynamic> json,
  ) {
    return JarvisCloudDevice(
      deviceId: json['device_id']?.toString() ?? '',
      deviceName:
          json['device_name']?.toString() ??
              'Jarvis device',
      online: json['online'] == true,
      foreground: json['foreground'] == true,
      activeAvatar: json['active_avatar'] == true,
      capabilities: json['capabilities'] is Map
          ? Map<String, dynamic>.from(
              json['capabilities'] as Map,
            )
          : const <String, dynamic>{},
      lastSeenAt: DateTime.tryParse(
        json['last_seen_at']?.toString() ?? '',
      ),
    );
  }
}

final class JarvisCloudCommandResult {
  const JarvisCloudCommandResult({
    required this.commandId,
    required this.status,
    required this.result,
    required this.error,
    required this.timedOut,
  });

  final String commandId;
  final String status;
  final Map<String, dynamic> result;
  final String? error;
  final bool timedOut;

  bool get isTerminal => const <String>{
        'completed',
        'failed',
        'cancelled',
        'expired',
      }.contains(status);

  bool get completed =>
      status == 'completed';

  factory JarvisCloudCommandResult.fromJson(
    Map<String, dynamic> json, {
    bool timedOut = false,
  }) {
    final Object? rawResult = json['result'];

    return JarvisCloudCommandResult(
      commandId: json['id']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'unknown',
      result: rawResult is Map
          ? Map<String, dynamic>.from(rawResult)
          : const <String, dynamic>{},
      error: json['error']?.toString(),
      timedOut: timedOut,
    );
  }

  JarvisCloudCommandResult withTimedOut() {
    return JarvisCloudCommandResult(
      commandId: commandId,
      status: status,
      result: result,
      error: error,
      timedOut: true,
    );
  }
}

final class JarvisCloudDeviceState {
  const JarvisCloudDeviceState({
    required this.configured,
    required this.deviceId,
    required this.deviceName,
    required this.foreground,
    required this.activeAvatar,
    required this.autoRoam,
    required this.devices,
    required this.lastCommand,
    required this.lastCommandResult,
    this.errorMessage,
  });

  const JarvisCloudDeviceState.initial()
      : configured = false,
        deviceId = '',
        deviceName = '',
        foreground = true,
        activeAvatar = false,
        autoRoam = true,
        devices = const <JarvisCloudDevice>[],
        lastCommand = '',
        lastCommandResult =
            const <String, dynamic>{},
        errorMessage = null;

  final bool configured;
  final String deviceId;
  final String deviceName;
  final bool foreground;
  final bool activeAvatar;
  final bool autoRoam;
  final List<JarvisCloudDevice> devices;
  final String lastCommand;
  final Map<String, dynamic> lastCommandResult;
  final String? errorMessage;

  int get onlineCount => devices
      .where((JarvisCloudDevice d) => d.online)
      .length;

  JarvisCloudDeviceState copyWith({
    bool? configured,
    String? deviceId,
    String? deviceName,
    bool? foreground,
    bool? activeAvatar,
    bool? autoRoam,
    List<JarvisCloudDevice>? devices,
    String? lastCommand,
    Map<String, dynamic>? lastCommandResult,
    String? errorMessage,
    bool clearError = false,
  }) {
    return JarvisCloudDeviceState(
      configured: configured ?? this.configured,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      foreground: foreground ?? this.foreground,
      activeAvatar: activeAvatar ?? this.activeAvatar,
      autoRoam: autoRoam ?? this.autoRoam,
      devices: devices ?? this.devices,
      lastCommand:
          lastCommand ?? this.lastCommand,
      lastCommandResult:
          lastCommandResult ??
              this.lastCommandResult,
      errorMessage: clearError
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class JarvisCloudDeviceNetwork
    with WidgetsBindingObserver {
  JarvisCloudDeviceNetwork({
    required JarvisConfig config,
    required JarvisPrinterService printerService,
    required JarvisMusicService musicService,
    required JarvisVisionService visionService,
    required JarvisVoiceService voiceService,
    required JarvisSystemControlService
        systemControlService,
    required JarvisDeviceRepairService
        deviceRepairService,
    http.Client? client,
  })  : _config = config,
        _printerService = printerService,
        _musicService = musicService,
        _visionService = visionService,
        _voiceService = voiceService,
        _systemControlService =
            systemControlService,
        _deviceRepairService =
            deviceRepairService,
        _client = client ?? http.Client() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  static const String _deviceIdKey =
      'jarvis.print.device_id';
  static const String _autoRoamKey =
      'jarvis.cloud.auto_roam_avatar';

  static const MethodChannel _relayChannel =
      MethodChannel('jarvis.cloud_relay');

  static const Set<String> _allowedActions =
      <String>{
    'ping',
    'speak_text',
    'play_music',
    'music_pause',
    'music_resume',
    'vision_refresh',
    'system_action',
    'flashlight_on',
    'flashlight_off',
    'avatar_handoff',
    'wake_jarvis',
    'device_diagnose',
    'device_scan_security',
    'device_repair',
  };

  final JarvisConfig _config;
  final JarvisPrinterService _printerService;
  final JarvisMusicService _musicService;
  final JarvisVisionService _visionService;
  final JarvisVoiceService _voiceService;
  final JarvisSystemControlService
      _systemControlService;
  final JarvisDeviceRepairService
      _deviceRepairService;
  final http.Client _client;

  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();
  final StreamController<JarvisCloudDeviceState>
      _stateController =
      StreamController<JarvisCloudDeviceState>
          .broadcast();

  JarvisCloudDeviceState _state =
      const JarvisCloudDeviceState.initial();

  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  Timer? _refreshTimer;
  bool _started = false;
  bool _disposed = false;
  bool _polling = false;
  bool _refreshing = false;
  bool _foreground = true;
  bool _activeAvatar = false;
  bool _autoRoam = true;
  bool _nativeRelayStarted = false;

  Stream<JarvisCloudDeviceState> get stateStream =>
      _stateController.stream;

  JarvisCloudDeviceState get state => _state;

  bool get isConfigured =>
      _config.clientToken.trim().isNotEmpty &&
      _config.deviceGatewayUrl.trim().isNotEmpty;

  bool get _supportsNativeRelay =>
      !kIsWeb &&
      defaultTargetPlatform ==
          TargetPlatform.android;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    final String deviceId =
        await _loadOrCreateDeviceId();
    final String deviceName =
        await _printerService.getDeviceName();
    _autoRoam =
        await _preferences.getBool(
              _autoRoamKey,
            ) ??
            true;

    _emit(
      _state.copyWith(
        configured: isConfigured,
        deviceId: deviceId,
        deviceName: deviceName,
        foreground: _foreground,
        autoRoam: _autoRoam,
        clearError: true,
      ),
    );

    if (!isConfigured) return;

    await _startNativeRelay(
      polling: !_foreground,
    );

    if (_foreground && _autoRoam) {
      _activeAvatar = true;
    }

    await refreshHeartbeat();
    await refreshDevices();
    await pollCommands();

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(refreshHeartbeat()),
    );
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(pollCommands()),
    );
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(refreshDevices()),
    );
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    _foreground =
        state == AppLifecycleState.resumed;
    _emit(
      _state.copyWith(
        foreground: _foreground,
      ),
    );
    if (isConfigured) {
      if (_foreground && _autoRoam) {
        _activeAvatar = true;
      }
      unawaited(refreshHeartbeat());
      unawaited(
        _setNativeRelayPolling(
          !_foreground,
        ),
      );
    }
  }

  Future<void> setAutoRoam(
    bool enabled,
  ) async {
    _autoRoam = enabled;
    await _preferences.setBool(
      _autoRoamKey,
      enabled,
    );

    if (enabled && _foreground) {
      _activeAvatar = true;
    }

    _emit(
      _state.copyWith(
        autoRoam: enabled,
        activeAvatar: _activeAvatar,
        clearError: true,
      ),
    );

    if (isConfigured &&
        _state.deviceId.isNotEmpty) {
      await refreshHeartbeat();
      await refreshDevices();
    }
  }

  Future<void> _startNativeRelay({
    required bool polling,
  }) async {
    if (!_supportsNativeRelay ||
        !isConfigured ||
        _state.deviceId.isEmpty) {
      return;
    }

    try {
      await _relayChannel.invokeMethod<bool>(
        'start',
        <String, dynamic>{
          'gatewayUrl':
              _config.deviceGatewayUrl,
          'token': _config.clientToken,
          'deviceId': _state.deviceId,
          'deviceName':
              _state.deviceName.isEmpty
                  ? 'Jarvis Android'
                  : _state.deviceName,
          'polling': polling,
        },
      );
      _nativeRelayStarted = true;
    } on PlatformException catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Background cloud relay could not start: ' +
                  (error.message ??
                      error.code),
        ),
      );
    } on MissingPluginException {
      // Non-Android/test builds keep using the
      // foreground Dart polling path.
    }
  }

  Future<void> _setNativeRelayPolling(
    bool enabled,
  ) async {
    if (!_supportsNativeRelay ||
        !_nativeRelayStarted) {
      return;
    }

    try {
      await _relayChannel.invokeMethod<bool>(
        'setPolling',
        <String, dynamic>{
          'enabled': enabled,
        },
      );
    } on Object {
      // Foreground Dart polling remains available.
    }
  }

  Future<Map<String, dynamic>>
      nativeRelayStatus() async {
    if (!_supportsNativeRelay) {
      return const <String, dynamic>{
        'running': false,
        'polling': false,
      };
    }

    try {
      final Map<dynamic, dynamic>? raw =
          await _relayChannel
              .invokeMapMethod<dynamic, dynamic>(
        'status',
      );

      return raw == null
          ? const <String, dynamic>{
              'running': false,
              'polling': false,
            }
          : Map<String, dynamic>.from(raw);
    } on Object {
      return const <String, dynamic>{
        'running': false,
        'polling': false,
      };
    }
  }

  Future<void> refreshHeartbeat() async {
    if (_disposed ||
        !isConfigured ||
        _state.deviceId.isEmpty) {
      return;
    }

    try {
      final Map<String, dynamic> payload =
          await _post(<String, dynamic>{
        'operation': 'heartbeat',
        'device_id': _state.deviceId,
        'device_name':
            _state.deviceName.isEmpty
                ? 'Jarvis Android'
                : _state.deviceName,
        'platform': 'android',
        'app_version': '1.3.0',
        'foreground': _foreground,
        'active_avatar': _activeAvatar,
        'capabilities':
            const <String, dynamic>{
          'cloud_commands': true,
          'cloud_background_relay': true,
          'speech': true,
          'music': true,
          'camera_vision': true,
          'screen_control': true,
          'flashlight': true,
          'avatar_handoff': true,
          'bluetooth_le': true,
          'device_diagnostics': true,
          'device_security_scan': true,
          'device_repair': true,
        },
      });

      final Map<String, dynamic> device =
          _asMap(payload['device']);
      _activeAvatar =
          device['active_avatar'] == true;

      _emit(
        _state.copyWith(
          activeAvatar: _activeAvatar,
          clearError: true,
        ),
      );
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Cloud heartbeat failed: ' +
                  error.toString(),
        ),
      );
    }
  }

  Future<void> refreshDevices() async {
    if (_disposed ||
        _refreshing ||
        !isConfigured) {
      return;
    }

    _refreshing = true;
    try {
      final Map<String, dynamic> payload =
          await _post(
        const <String, dynamic>{
          'operation': 'list_devices',
        },
      );

      final Object? raw = payload['devices'];
      final List<JarvisCloudDevice> devices =
          raw is List
              ? raw
                  .whereType<Map>()
                  .map(
                    (Map value) =>
                        JarvisCloudDevice.fromJson(
                      Map<String, dynamic>.from(
                        value,
                      ),
                    ),
                  )
                  .where(
                    (JarvisCloudDevice d) =>
                        d.deviceId.isNotEmpty,
                  )
                  .toList(growable: false)
              : const <JarvisCloudDevice>[];

      for (final JarvisCloudDevice device
          in devices) {
        if (device.deviceId ==
            _state.deviceId) {
          _activeAvatar =
              device.activeAvatar;
          break;
        }
      }

      _emit(
        _state.copyWith(
          devices: devices,
          activeAvatar: _activeAvatar,
          clearError: true,
        ),
      );
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Cloud device refresh failed: ' +
                  error.toString(),
        ),
      );
    } finally {
      _refreshing = false;
    }
  }

  Future<String> sendCommand({
    required String targetDeviceId,
    required String action,
    Map<String, dynamic> parameters =
        const <String, dynamic>{},
    int ttlSeconds = 300,
  }) async {
    _ensureReady();
    final String normalized = action.trim();

    if (!_allowedActions.contains(normalized)) {
      throw ArgumentError(
        'Unsupported cloud-device action: ' +
            normalized,
      );
    }

    final Map<String, dynamic> payload =
        await _post(<String, dynamic>{
      'operation': 'send_command',
      'requested_from_device_id':
          _state.deviceId,
      'target_device_id':
          targetDeviceId.trim(),
      'action': normalized,
      'parameters': parameters,
      'ttl_seconds':
          ttlSeconds.clamp(15, 3600),
    });

    return _asMap(
          payload['command'],
        )['id']?.toString() ??
        '';
  }

  Future<JarvisCloudCommandResult?>
      getCommand(
    String commandId,
  ) async {
    _ensureReady();

    final String normalized =
        commandId.trim();

    if (normalized.isEmpty) {
      throw ArgumentError(
        'A cloud command ID is required.',
      );
    }

    final Map<String, dynamic> payload =
        await _post(<String, dynamic>{
      'operation': 'get_command',
      'command_id': normalized,
    });

    final Map<String, dynamic> command =
        _asMap(payload['command']);

    if (command.isEmpty) {
      return null;
    }

    return JarvisCloudCommandResult.fromJson(
      command,
    );
  }

  Future<JarvisCloudCommandResult>
      waitForCommand(
    String commandId, {
    Duration timeout =
        const Duration(seconds: 30),
    Duration pollInterval =
        const Duration(milliseconds: 750),
  }) async {
    final String normalized =
        commandId.trim();

    if (normalized.isEmpty) {
      throw ArgumentError(
        'A cloud command ID is required.',
      );
    }

    final DateTime deadline =
        DateTime.now().add(timeout);

    JarvisCloudCommandResult last =
        JarvisCloudCommandResult(
      commandId: normalized,
      status: 'queued',
      result:
          const <String, dynamic>{},
      error: null,
      timedOut: false,
    );

    while (!_disposed &&
        DateTime.now().isBefore(deadline)) {
      final JarvisCloudCommandResult?
          current =
          await getCommand(normalized);

      if (current == null) {
        throw StateError(
          'Cloud command disappeared before verification.',
        );
      }

      last = current;

      if (current.isTerminal) {
        return current;
      }

      await Future<void>.delayed(
        pollInterval,
      );
    }

    return last.withTimedOut();
  }

  Future<List<String>> broadcastCommand({
    required String action,
    Map<String, dynamic> parameters =
        const <String, dynamic>{},
    int ttlSeconds = 300,
  }) async {
    _ensureReady();
    final String normalized = action.trim();

    if (!_allowedActions.contains(normalized)) {
      throw ArgumentError(
        'Unsupported cloud-device action: ' +
            normalized,
      );
    }

    final Map<String, dynamic> payload =
        await _post(<String, dynamic>{
      'operation': 'broadcast_command',
      'requested_from_device_id':
          _state.deviceId,
      'action': normalized,
      'parameters': parameters,
      'ttl_seconds':
          ttlSeconds.clamp(15, 3600),
    });

    final Object? raw = payload['commands'];
    if (raw is! List) {
      return const <String>[];
    }

    return raw
        .whereType<Map>()
        .map(
          (Map command) =>
              command['id']?.toString() ?? '',
        )
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> handoffJarvisTo(
    String targetDeviceId,
  ) {
    return sendCommand(
      targetDeviceId: targetDeviceId,
      action: 'avatar_handoff',
      parameters: const <String, dynamic>{
        'animate_entry': true,
      },
    );
  }

  Future<void> pollCommands() async {
    if (_disposed ||
        _polling ||
        !isConfigured ||
        _state.deviceId.isEmpty) {
      return;
    }

    _polling = true;
    try {
      final Map<String, dynamic> payload =
          await _post(<String, dynamic>{
        'operation': 'claim_commands',
        'device_id': _state.deviceId,
      });

      final Object? raw = payload['commands'];
      if (raw is! List) return;

      for (final Object? value in raw) {
        if (value is Map) {
          await _executeCommand(
            Map<String, dynamic>.from(value),
          );
        }
      }
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Cloud command polling failed: ' +
                  error.toString(),
        ),
      );
    } finally {
      _polling = false;
    }
  }

  Future<void> _executeCommand(
    Map<String, dynamic> command,
  ) async {
    final String id =
        command['id']?.toString() ?? '';
    final String action =
        command['action']?.toString() ?? '';
    final Map<String, dynamic> parameters =
        _asMap(command['parameters']);

    if (id.isEmpty ||
        !_allowedActions.contains(action)) {
      if (id.isNotEmpty) {
        await _updateCommand(
          commandId: id,
          status: 'failed',
          error: 'Unsupported command.',
        );
      }
      return;
    }

    await _updateCommand(
      commandId: id,
      status: 'executing',
    );

    try {
      final Map<String, dynamic> result =
          await _performAction(
        action,
        parameters,
      );

      _emit(
        _state.copyWith(
          lastCommand: action,
          lastCommandResult: result,
          clearError: true,
        ),
      );

      await _updateCommand(
        commandId: id,
        status: 'completed',
        result: result,
      );
      await refreshDevices();
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          lastCommand: action,
          errorMessage:
              'Remote action failed: ' +
                  error.toString(),
        ),
      );
      await _updateCommand(
        commandId: id,
        status: 'failed',
        error: error.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _performAction(
    String action,
    Map<String, dynamic> parameters,
  ) async {
    switch (action) {
      case 'ping':
        return <String, dynamic>{
          'online': true,
          'device_id': _state.deviceId,
          'device_name': _state.deviceName,
        };

      case 'speak_text':
        final String text =
            parameters['text']
                    ?.toString()
                    .trim() ??
                '';
        if (text.isEmpty) {
          throw ArgumentError(
            'speak_text requires text.',
          );
        }
        await _voiceService.speak(text);
        return <String, dynamic>{
          'spoken': true,
          'text': text,
        };

      case 'play_music':
        final String query =
            parameters['query']
                    ?.toString()
                    .trim() ??
                '';
        if (query.isEmpty) {
          throw ArgumentError(
            'play_music requires query.',
          );
        }
        final track =
            await _musicService.searchAndPlay(
          query,
        );
        return <String, dynamic>{
          'playing': true,
          'title': track.title,
          'author': track.author,
          'provider': track.provider,
          'video_id': track.videoId,
        };

      case 'music_pause':
        await _musicService.pause();
        return const <String, dynamic>{
          'paused': true,
        };

      case 'music_resume':
        await _musicService.play();
        return const <String, dynamic>{
          'playing': true,
        };

      case 'vision_refresh':
        if (!_visionService.isActive) {
          await _visionService.start();
        } else {
          await _visionService.refreshFrameNow();
        }
        return <String, dynamic>{
          'vision_active':
              _visionService.isActive,
          'frame_refreshed': true,
        };

      case 'system_action':
        final String name =
            parameters['action']
                    ?.toString()
                    .trim() ??
                '';
        if (!const <String>{
          'back',
          'home',
          'recents',
          'notifications',
        }.contains(name)) {
          throw ArgumentError(
            'Unsupported global action.',
          );
        }
        final bool ok =
            await _systemControlService
                .performGlobalAction(name);
        if (!ok) {
          throw StateError(
            'Android did not confirm '
            'the global action.',
          );
        }
        return <String, dynamic>{
          'action': name,
          'completed': true,
        };

      case 'flashlight_on':
      case 'flashlight_off':
        final bool available =
            await TorchLight
                .isTorchAvailable();
        if (!available) {
          throw StateError(
            'This device has no flashlight.',
          );
        }
        if (action == 'flashlight_on') {
          await TorchLight.enableTorch();
        } else {
          await TorchLight.disableTorch();
        }
        return <String, dynamic>{
          'state': action == 'flashlight_on'
              ? 'on'
              : 'off',
        };

      case 'wake_jarvis':
        await _voiceService.speak(
          parameters['response']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
              ? parameters['response']
                  .toString()
                  .trim()
              : 'Yes?',
        );
        await _voiceService.startListening();
        return const <String, dynamic>{
          'awake': true,
          'listening': true,
        };

      case 'device_diagnose':
        final JarvisDeviceDiagnosis diagnosis =
            await _deviceRepairService.diagnose();
        return <String, dynamic>{
          'healthy': diagnosis.healthy,
          'issues': diagnosis.issues
              .map(
                (JarvisDeviceIssue issue) =>
                    <String, dynamic>{
                  'code': issue.code,
                  'severity': issue.severity,
                  'summary': issue.summary,
                  'repair': issue.repair,
                },
              )
              .toList(growable: false),
        };

      case 'device_scan_security':
        final List<JarvisAppThreat> apps =
            await _deviceRepairService.scanApps();
        final List<JarvisAppThreat> risky =
            apps
                .where(
                  (JarvisAppThreat app) =>
                      app.needsReview,
                )
                .toList(growable: false);
        return <String, dynamic>{
          'scanned_apps': apps.length,
          'review_count': risky.length,
          'possible_malware_count': risky
              .where(
                (JarvisAppThreat app) =>
                    app.possibleMalware,
              )
              .length,
          'findings': risky
              .map(
                (JarvisAppThreat app) =>
                    <String, dynamic>{
                  'label': app.label,
                  'package_name':
                      app.packageName,
                  'risk_score':
                      app.riskScore,
                  'risk_level':
                      app.riskLevel,
                  'possible_malware':
                      app.possibleMalware,
                  'reasons': app.reasons,
                },
              )
              .toList(growable: false),
        };

      case 'device_repair':
        final String target =
            parameters['target']
                    ?.toString()
                    .trim() ??
                '';
        if (!const <String>{
          'storage',
          'memory',
          'internet',
          'bluetooth',
          'battery',
          'apps',
          'security',
          'system_update',
          'date_time',
          'display',
          'sound',
          'accessibility',
          'jarvis_cache',
        }.contains(target)) {
          throw ArgumentError(
            'Unsupported device repair target.',
          );
        }

        final JarvisRepairResult repair =
            await _deviceRepairService
                .repairIssue(target);

        if (!repair.ok) {
          throw StateError(repair.message);
        }

        return <String, dynamic>{
          'target': repair.target,
          'action': repair.action,
          'requires_user_action':
              repair.requiresUserAction,
          'message': repair.message,
        };

      case 'avatar_handoff':
        _activeAvatar = true;
        await refreshHeartbeat();
        return <String, dynamic>{
          'device_id': _state.deviceId,
          'active_avatar': true,
          'animate_entry':
              parameters['animate_entry'] ==
                  true,
        };
    }

    throw StateError(
      'Unhandled cloud-device action.',
    );
  }

  Future<void> _updateCommand({
    required String commandId,
    required String status,
    Map<String, dynamic> result =
        const <String, dynamic>{},
    String? error,
  }) async {
    await _post(<String, dynamic>{
      'operation': 'update_command',
      'device_id': _state.deviceId,
      'command_id': commandId,
      'status': status,
      'result': result,
      if (error != null) 'error': error,
    });
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body,
  ) async {
    final http.Response response =
        await _client
            .post(
              Uri.parse(
                _config.deviceGatewayUrl,
              ),
              headers: <String, String>{
                'content-type':
                    'application/json',
                'authorization':
                    'Bearer ' +
                        _config.clientToken,
              },
              body: jsonEncode(body),
            )
            .timeout(
              const Duration(seconds: 15),
            );

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }

    final Map<String, dynamic> payload =
        decoded is Map
            ? Map<String, dynamic>.from(
                decoded,
              )
            : <String, dynamic>{};

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw StateError(
        payload['error']?.toString() ??
            'Device gateway failed with HTTP ' +
                response.statusCode.toString() +
                '.',
      );
    }

    return payload;
  }

  Future<String> _loadOrCreateDeviceId() async {
    final String? existing =
        await _preferences.getString(
      _deviceIdKey,
    );

    if (existing != null &&
        existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final String generated =
        DateTime.now()
                .microsecondsSinceEpoch
                .toString() +
            '-' +
            Object().hashCode.abs().toString();

    await _preferences.setString(
      _deviceIdKey,
      generated,
    );

    return generated;
  }

  Map<String, dynamic> _asMap(
    Object? value,
  ) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  void _ensureReady() {
    if (_disposed) {
      throw StateError(
        'Jarvis cloud device network '
        'has been disposed.',
      );
    }
    if (!isConfigured) {
      throw StateError(
        'Jarvis cloud device network '
        'is not configured.',
      );
    }
    if (_state.deviceId.isEmpty) {
      throw StateError(
        'Jarvis device identity is '
        'still initializing.',
      );
    }
  }

  void _emit(
    JarvisCloudDeviceState next,
  ) {
    if (_disposed) return;
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _refreshTimer?.cancel();

    // Leave the Android foreground relay active so
    // safe cloud commands can still reach this device
    // after the Flutter UI is backgrounded or detached.
    if (_nativeRelayStarted) {
      unawaited(
        _setNativeRelayPolling(true),
      );
    }

    _client.close();
    await _stateController.close();
  }
}
