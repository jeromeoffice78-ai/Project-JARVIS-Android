import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';

import '../../core/network/jarvis_ws_service.dart';
import '../../core/protocol/jarvis_protocol.dart';
import '../capabilities/jarvis_capability_service.dart';

enum JarvisChatStatus {
  idle,
  thinking,
  streaming,
  completed,
  cancelled,
  error,
}

final class JarvisChatState {
  const JarvisChatState({
    required this.status,
    required this.responseText,
    this.requestId,
    this.errorMessage,
    this.retryable = false,
  });

  const JarvisChatState.initial()
      : status = JarvisChatStatus.idle,
        responseText = '',
        requestId = null,
        errorMessage = null,
        retryable = false;

  final JarvisChatStatus status;
  final String responseText;
  final String? requestId;
  final String? errorMessage;
  final bool retryable;

  bool get isGenerating =>
      status == JarvisChatStatus.thinking ||
      status == JarvisChatStatus.streaming;
}

class JarvisChatController {
  JarvisChatController({
    required JarvisWsService wsService,
    required JarvisCapabilityService capabilityService,
  })  : _wsService = wsService,
        _capabilityService = capabilityService {
    _messageSubscription = _wsService.incomingMessages.listen(
      (Map<String, dynamic> rawMap) {
        unawaited(_handleIncomingMessage(rawMap));
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitState(
          JarvisChatState(
            status: JarvisChatStatus.error,
            responseText: _currentResponseBuffer,
            requestId: _activeRequestId,
            errorMessage: 'Jarvis transport error: $error',
            retryable: true,
          ),
        );
      },
    );
  }

  final JarvisWsService _wsService;
  final JarvisCapabilityService _capabilityService;

  final StreamController<JarvisChatState> _stateController =
      StreamController<JarvisChatState>.broadcast();

  final StreamController<String> _responseBufferController =
      StreamController<String>.broadcast();

  final StreamController<ThemeMode> _themeModeController =
      StreamController<ThemeMode>.broadcast();

  final Map<String, ToolResultEvent> _completedToolCalls =
      <String, ToolResultEvent>{};

  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  JarvisChatState _state = const JarvisChatState.initial();
  String _currentResponseBuffer = '';
  String? _activeRequestId;
  int _expectedChunkIndex = 0;
  bool _disposed = false;

  Stream<JarvisChatState> get stateStream => _stateController.stream;
  Stream<String> get currentResponseStream =>
      _responseBufferController.stream;
  Stream<ThemeMode> get themeModeStream => _themeModeController.stream;

  JarvisChatState get state => _state;
  String get currentResponse => _currentResponseBuffer;
  String? get activeRequestId => _activeRequestId;

  String? askJarvis(String query) {
    _ensureNotDisposed();

    final String normalized = query.trim();

    if (normalized.isEmpty) {
      return null;
    }

    if (_activeRequestId != null && _state.isGenerating) {
      cancelCurrentResponse();
    }

    final UserTextQueryEvent event =
        UserTextQueryEvent(text: normalized);

    _activeRequestId = event.requestId;
    _currentResponseBuffer = '';
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
        requestId: event.requestId,
      ),
    );

    _emitResponseBuffer();

    try {
      _wsService.sendJson(event.toJson());
      return event.requestId;
    } on Object catch (error) {
      _activeRequestId = null;

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: '',
          requestId: event.requestId,
          errorMessage: 'Unable to send request: $error',
          retryable: true,
        ),
      );

      return null;
    }
  }

  void cancelCurrentResponse() {
    _ensureNotDisposed();

    final String? requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }

    _wsService.sendJson(
      CancelResponseEvent(
        requestId: requestId,
      ).toJson(),
    );
  }

  Future<void> _handleIncomingMessage(
    Map<String, dynamic> rawMap,
  ) async {
    if (_disposed) {
      return;
    }

    try {
      final JarvisEvent event = JarvisEventParser.parse(rawMap);

      if (event is SystemCommandEvent) {
        await _executeLocalDeviceCommand(event);
        return;
      }

      if (event is AgentTextChunkEvent) {
        _handleAgentTextChunk(event);
        return;
      }

      if (event is JarvisErrorEvent) {
        _handleJarvisError(event);
        return;
      }

      if (event is ResponseCancelledEvent) {
        _handleResponseCancelled(event);
      }
    } on JarvisProtocolException catch (error) {
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: _currentResponseBuffer,
          requestId: _activeRequestId,
          errorMessage: error.message,
          retryable: false,
        ),
      );
    } on Object catch (error) {
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: _currentResponseBuffer,
          requestId: _activeRequestId,
          errorMessage: 'Unexpected Jarvis protocol error: $error',
          retryable: false,
        ),
      );
    }
  }

  void _handleAgentTextChunk(AgentTextChunkEvent event) {
    if (event.requestId != _activeRequestId) {
      return;
    }

    if (event.chunkIndex < _expectedChunkIndex) {
      return;
    }

    if (event.chunkIndex > _expectedChunkIndex) {
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: _currentResponseBuffer,
          requestId: event.requestId,
          errorMessage:
              'Streaming sequence interrupted. Expected chunk '
              '$_expectedChunkIndex but received ${event.chunkIndex}.',
          retryable: true,
        ),
      );
      return;
    }

    if (event.textChunk.isNotEmpty) {
      _currentResponseBuffer += event.textChunk;
      _emitResponseBuffer();
    }

    _expectedChunkIndex++;

    if (event.isFinal) {
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.completed,
          responseText: _currentResponseBuffer,
          requestId: event.requestId,
        ),
      );
      _activeRequestId = null;
      _expectedChunkIndex = 0;
      return;
    }

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.streaming,
        responseText: _currentResponseBuffer,
        requestId: event.requestId,
      ),
    );
  }

  void _handleJarvisError(JarvisErrorEvent event) {
    if (event.requestId != null &&
        _activeRequestId != null &&
        event.requestId != _activeRequestId) {
      return;
    }

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.error,
        responseText: _currentResponseBuffer,
        requestId: event.requestId ?? _activeRequestId,
        errorMessage: event.message,
        retryable: event.retryable,
      ),
    );

    if (event.requestId == null ||
        event.requestId == _activeRequestId) {
      _activeRequestId = null;
      _expectedChunkIndex = 0;
    }
  }

  void _handleResponseCancelled(
    ResponseCancelledEvent event,
  ) {
    if (event.requestId != null &&
        _activeRequestId != null &&
        event.requestId != _activeRequestId) {
      return;
    }

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.cancelled,
        responseText: _currentResponseBuffer,
        requestId: event.requestId ?? _activeRequestId,
      ),
    );

    _activeRequestId = null;
    _expectedChunkIndex = 0;
  }

  Future<void> _executeLocalDeviceCommand(
    SystemCommandEvent event,
  ) async {
    final String cacheKey =
        '${event.requestId}:${event.callId}';

    final ToolResultEvent? cached =
        _completedToolCalls[cacheKey];

    if (cached != null) {
      _wsService.sendJson(cached.toJson());
      return;
    }

    final ToolResultEvent result;

    if (event.action == 'toggle_flashlight') {
      result = await _executeFlashlightCommand(event);
    } else if (event.action == 'change_system_theme') {
      result = _executeThemeCommand(event);
    } else {
      final JarvisCapabilityResult capability =
          await _capabilityService.execute(
        requestId: event.requestId,
        callId: event.callId,
        action: event.action,
        parameters: event.parameters,
      );

      result = ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: capability.ok,
        result: capability.result,
        error: capability.error,
      );
    }

    _completedToolCalls[cacheKey] = result;
    _trimToolResultCache();

    try {
      _wsService.sendJson(result.toJson());
    } on Object catch (error) {
      debugPrint(
        'Unable to return Jarvis tool result: $error',
      );
    }
  }

  Future<ToolResultEvent> _executeFlashlightCommand(
    SystemCommandEvent event,
  ) async {
    final Object? requestedState =
        event.parameters['state'];

    if (requestedState != 'on' &&
        requestedState != 'off') {
      return ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: false,
        result: const <String, dynamic>{},
        error: 'Invalid flashlight state.',
      );
    }

    if (!_supportsNativeTorch) {
      return ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: false,
        result: const <String, dynamic>{
          'supported': false,
        },
        error: 'Flashlight control is unavailable on this platform.',
      );
    }

    try {
      final bool available =
          await TorchLight.isTorchAvailable();

      if (!available) {
        return ToolResultEvent(
          requestId: event.requestId,
          callId: event.callId,
          ok: false,
          result: const <String, dynamic>{
            'supported': false,
          },
          error: 'This device has no available flashlight.',
        );
      }

      if (requestedState == 'on') {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }

      return ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: true,
        result: <String, dynamic>{
          'supported': true,
          'state': requestedState,
        },
      );
    } on Object catch (error) {
      return ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: false,
        result: const <String, dynamic>{},
        error:
            'Flashlight operation failed: ${error.runtimeType}',
      );
    }
  }

  ToolResultEvent _executeThemeCommand(
    SystemCommandEvent event,
  ) {
    final Object? requestedTheme =
        event.parameters['theme'];

    if (requestedTheme != 'light' &&
        requestedTheme != 'dark') {
      return ToolResultEvent(
        requestId: event.requestId,
        callId: event.callId,
        ok: false,
        result: const <String, dynamic>{},
        error: 'Invalid application theme.',
      );
    }

    final ThemeMode mode =
        requestedTheme == 'dark'
            ? ThemeMode.dark
            : ThemeMode.light;

    if (!_themeModeController.isClosed) {
      _themeModeController.add(mode);
    }

    return ToolResultEvent(
      requestId: event.requestId,
      callId: event.callId,
      ok: true,
      result: <String, dynamic>{
        'theme': requestedTheme,
      },
    );
  }

  bool get _supportsNativeTorch {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform ==
            TargetPlatform.android ||
        defaultTargetPlatform ==
            TargetPlatform.iOS;
  }

  void _trimToolResultCache() {
    const int maximumEntries = 100;

    while (_completedToolCalls.length >
        maximumEntries) {
      _completedToolCalls.remove(
        _completedToolCalls.keys.first,
      );
    }
  }

  void _emitResponseBuffer() {
    if (!_disposed &&
        !_responseBufferController.isClosed) {
      _responseBufferController.add(
        _currentResponseBuffer,
      );
    }
  }

  void _emitState(JarvisChatState state) {
    if (_disposed || _stateController.isClosed) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'JarvisChatController has been disposed.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _messageSubscription?.cancel();
    _messageSubscription = null;

    _completedToolCalls.clear();

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _responseBufferController.close(),
      _themeModeController.close(),
    ]);
  }
}
