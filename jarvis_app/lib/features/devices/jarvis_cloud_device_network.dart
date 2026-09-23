import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torch_light/torch_light.dart';

import '../../core/config/jarvis_config.dart';
import '../music/jarvis_music_service.dart';
import '../printer/jarvis_printer_service.dart';
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

final class JarvisCloudDeviceState {
  const JarvisCloudDeviceState({
    required this.configured,
    required this.deviceId,
    required this.deviceName,
    required this.foreground,
    required this.activeAvatar,
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
    http.Client? client,
  })  : _config = config,
        _printerService = printerService,
        _musicService = musicService,
        _visionService = visionService,
        _voiceService = voiceService,
        _systemControlService =
            systemControlService,
        _client = client ?? http.Client() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  static const String _deviceIdKey =
      'jarvis.print.device_id';

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
  };

  final JarvisConfig _config;
  final JarvisPrinterService _printerService;
  final JarvisMusicService _musicService;
  final JarvisVisionService _visionService;
  final JarvisVoiceService _voiceService;
  final JarvisSystemControlService
      _systemControlService;
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
  bool _autoHandoffInFlight = false;

  Stream<JarvisCloudDeviceState> get stateStream =>
      _stateController.stream;

  JarvisCloudDeviceState get state => _state;

  bool get isConfigured =>
      _config.clientToken.trim().isNotEmpty &&
      _config.deviceGatewayUrl.trim().isNotEmpty;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    final String deviceId =
        await _loadOrCreateDeviceId();
    final String deviceName =
        await _printerService.getDeviceName();

    _emit(
      _state.copyWith(
        configured: isConfigured,
        deviceId: deviceId,
        deviceName: deviceName,
        foreground: _foreground,
        clearError: true,
      ),
    );

    if (!isConfigured) return;

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

    if (!isConfigured) {
      return;
    }

    if (_foreground) {
      unawaited(_syncForegroundPresence());
    } else {
      unawaited(refreshHeartbeat());
    }
  }

  Future<void> _syncForegroundPresence() async {
    await refreshHeartbeat();
    await refreshDevices();

    if (_disposed ||
        !_foreground ||
        _autoHandoffInFlight ||
        _state.deviceId.isEmpty) {
      return;
    }

    JarvisCloudDevice? activeDevice;
    for (final JarvisCloudDevice device
        in _state.devices) {
      if (device.activeAvatar) {
        activeDevice = device;
        break;
      }
    }

    if (activeDevice == null ||
        activeDevice.deviceId ==
            _state.deviceId) {
      return;
    }

    // Do not make two devices that are both actively in use
    // fight over the avatar. Jarvis follows only when the
    // previous host is backgrounded or offline.
    if (activeDevice.online &&
        activeDevice.foreground) {
      return;
    }

    _autoHandoffInFlight = true;
    try {
      await handoffJarvisTo(
        _state.deviceId,
      );
      await pollCommands();
      await refreshDevices();
    } on Object catch (error) {
      _emit(
        _state.copyWith(
          errorMessage:
              'Automatic Jarvis handoff failed: ' +
                  error.toString(),
        ),
      );
    } finally {
      _autoHandoffInFlight = false;
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
        'app_version': '1.2.0',
        'foreground': _foreground,
        'active_avatar': _activeAvatar,
        'capabilities':
            const <String, dynamic>{
          'cloud_commands': true,
          'speech': true,
          'music': true,
          'camera_vision': true,
          'screen_control': true,
          'flashlight': true,
          'avatar_handoff': true,
          'bluetooth_le': true,
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
    _client.close();
    await _stateController.close();
  }
}
