import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:torch_light/torch_light.dart';

import '../../core/network/jarvis_api_service.dart';
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
    required JarvisApiService apiService,
    required JarvisCapabilityService capabilityService,
  })  : _wsService = wsService,
        _apiService = apiService,
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
  final JarvisApiService _apiService;
  final JarvisCapabilityService _capabilityService;

  final StreamController<JarvisChatState> _stateController =
      StreamController<JarvisChatState>.broadcast();

  final StreamController<String> _responseBufferController =
      StreamController<String>.broadcast();

  final StreamController<ThemeMode> _themeModeController =
      StreamController<ThemeMode>.broadcast();

  final Map<String, ToolResultEvent> _completedToolCalls =
      <String, ToolResultEvent>{};

  final Set<String> _autoPrintRequestIds =
      <String>{};

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

    final String? localRequestId =
        _tryHandleLocalFeatureCommand(
      normalized,
    );

    if (localRequestId != null) {
      return localRequestId;
    }

    if (_looksLikeVisionRequest(normalized)) {
      final String requestId =
          _newLocalRequestId('vision');

      unawaited(
        _prepareVisionAndSend(
          requestId,
          normalized,
        ),
      );

      return requestId;
    }

    return _sendRemoteQuery(normalized);
  }

  String? _sendRemoteQuery(
    String normalized,
  ) {
    if (_activeRequestId != null &&
        _state.isGenerating) {
      cancelCurrentResponse();
    }

    final bool autoPrint =
        _shouldAutoPrint(normalized);

    final String effectiveQuery = autoPrint
        ? _buildAutoPrintQuery(normalized)
        : normalized;

    final String requestId =
        _newLocalRequestId('remote');

    if (autoPrint) {
      _autoPrintRequestIds.add(requestId);
    }

    _activeRequestId = requestId;
    _currentResponseBuffer = '';
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
        requestId: requestId,
      ),
    );
    _emitResponseBuffer();

    unawaited(
      _executeRemoteHttpQuery(
        requestId: requestId,
        prompt: effectiveQuery,
        autoPrint: autoPrint,
      ),
    );

    return requestId;
  }

  Future<void> _executeRemoteHttpQuery({
    required String requestId,
    required String prompt,
    required bool autoPrint,
  }) async {
    try {
      final JarvisFrontierResult result =
          await _apiService.frontierQuery(
        prompt: prompt,
        mode: 'reason',
      );

      if (_disposed ||
          _activeRequestId != requestId) {
        return;
      }

      final String response =
          result.answer.trim();

      if (response.isEmpty) {
        throw const FormatException(
          'Jarvis backend returned an empty response.',
        );
      }

      _currentResponseBuffer = response;
      _emitResponseBuffer();

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.completed,
          responseText: response,
          requestId: requestId,
        ),
      );

      if (autoPrint) {
        _autoPrintRequestIds.remove(requestId);
        unawaited(
          _routeCompletedDocumentForPrinting(
            requestId: requestId,
            rawResponse: response,
          ),
        );
      }
    } on Object catch (error) {
      if (_disposed ||
          _activeRequestId != requestId) {
        return;
      }

      _autoPrintRequestIds.remove(requestId);

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText:
              _currentResponseBuffer,
          requestId: requestId,
          errorMessage:
              'Jarvis backend request failed: $error',
          retryable: true,
        ),
      );
    } finally {
      if (_activeRequestId == requestId) {
        _activeRequestId = null;
        _expectedChunkIndex = 0;
      }
    }
  }

  String? _tryHandleLocalFeatureCommand(
    String query,
  ) {
    final String cleaned = query
        .replaceFirst(
          RegExp(
            r'^jarvis[,:]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    final String lower =
        cleaned.toLowerCase();

    if (RegExp(
      r'^(pause|stop)\s+(the\s+)?(music|song|track)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'pause_music',
        parameters:
            const <String, dynamic>{},
        successText: (_) =>
            'Music paused.',
      );
    }

    if (RegExp(
      r'^(resume|continue)\s+(the\s+)?(music|song|track)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'resume_music',
        parameters:
            const <String, dynamic>{},
        successText: (_) =>
            'Music resumed.',
      );
    }

    final RegExp remotePlayPattern =
        RegExp(
      r'^play\s+(.+?)\s+on\s+(?:my\s+)?(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? remotePlay =
        remotePlayPattern.firstMatch(
      cleaned,
    );

    if (remotePlay != null) {
      final String musicQuery =
          remotePlay.group(1)?.trim() ?? '';
      final String deviceName =
          remotePlay.group(2)?.trim() ?? '';

      if (musicQuery.isNotEmpty &&
          deviceName.isNotEmpty) {
        return _runLocalCapability(
          action:
              'send_cloud_device_command',
          parameters: <String, dynamic>{
            'target_device_name':
                deviceName,
            'action': 'play_music',
            'parameters':
                <String, dynamic>{
              'query': musicQuery,
            },
          },
          successText: (
            Map<String, dynamic> result,
          ) {
            return 'Music command sent to ' +
                (result['target_device_name']
                        ?.toString() ??
                    deviceName) +
                '.';
          },
        );
      }
    }

    final RegExp playPattern = RegExp(
      r'^play\s+(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? playMatch =
        playPattern.firstMatch(cleaned);

    if (playMatch != null) {
      String musicQuery =
          playMatch.group(1)?.trim() ?? '';

      musicQuery = musicQuery.replaceFirst(
        RegExp(
          r'^(the\s+)?(song|track|music)\s+',
          caseSensitive: false,
        ),
        '',
      );

      if (musicQuery.isNotEmpty) {
        return _runLocalCapability(
          action: 'play_music',
          parameters: <String, dynamic>{
            'query': musicQuery,
          },
          successText: (
            Map<String, dynamic> result,
          ) {
            final String title =
                result['title']
                        ?.toString() ??
                    musicQuery;
            final String author =
                result['author']
                        ?.toString() ??
                    '';

            return author.isEmpty
                ? 'Playing ' + title + '.'
                : 'Playing ' +
                    title +
                    ' by ' +
                    author +
                    '.';
          },
        );
      }
    }

    final RegExp handoffPattern = RegExp(
      r'^(move|send|go)\s+(?:jarvis\s+|yourself\s+)?(?:to\s+)?(?:my\s+)?(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? handoff =
        handoffPattern.firstMatch(
      cleaned,
    );

    if (handoff != null) {
      final String verb =
          handoff.group(1)
                  ?.toLowerCase() ??
              '';
      final String target =
          handoff.group(2)?.trim() ?? '';

      final bool clearlyHandoff =
          verb == 'move' ||
          lower.startsWith(
            'send jarvis',
          ) ||
          lower.startsWith('go to');

      if (clearlyHandoff &&
          target.isNotEmpty) {
        return _runLocalCapability(
          action:
              'handoff_jarvis_device',
          parameters: <String, dynamic>{
            'target_device_name':
                target,
          },
          successText: (
            Map<String, dynamic> result,
          ) {
            return 'Jarvis handoff sent to ' +
                (result['target_device_name']
                        ?.toString() ??
                    target) +
                '.';
          },
        );
      }
    }

    final RegExp speakPattern = RegExp(
      r'^(say|speak)\s+(.+?)\s+on\s+(?:my\s+)?(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? speak =
        speakPattern.firstMatch(
      cleaned,
    );

    if (speak != null) {
      final String text =
          speak.group(2)?.trim() ?? '';
      final String deviceName =
          speak.group(3)?.trim() ?? '';

      if (text.isNotEmpty &&
          deviceName.isNotEmpty) {
        return _runLocalCapability(
          action:
              'send_cloud_device_command',
          parameters: <String, dynamic>{
            'target_device_name':
                deviceName,
            'action': 'speak_text',
            'parameters':
                <String, dynamic>{
              'text': text,
            },
          },
          successText: (
            Map<String, dynamic> result,
          ) {
            return 'Speech command sent to ' +
                (result['target_device_name']
                        ?.toString() ??
                    deviceName) +
                '.';
          },
        );
      }
    }

    if (RegExp(
      r"^(who('s| is)? calling|identify (the )?caller|caller id|caller information)$",
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_caller_lookup',
        parameters: const <String, dynamic>{},
        successText: _formatCallerIntelligence,
      );
    }

    final RegExp callerLookupPattern = RegExp(
      r'^(?:look up|lookup|identify|caller info(?:rmation)? for)\s+([+0-9().\-\s]{7,})
      return _runLocalCapability(
        action: 'phone_answer_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call answered.',
      );
    }

    if (RegExp(
      r'^(reject|decline)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_reject_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call rejected.',
      );
    }

    if (RegExp(
      r'^(hang up|end)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_end_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call ended.',
      );
    }

    final RegExp mutePattern = RegExp(
      r'^(mute|unmute)( the)? (call|phone|microphone|mic)$',
    );
    final RegExpMatch? muteMatch =
        mutePattern.firstMatch(lower);
    if (muteMatch != null) {
      final bool muted =
          muteMatch.group(1) == 'mute';
      return _runLocalCapability(
        action: 'phone_set_mute',
        parameters: <String, dynamic>{
          'muted': muted,
        },
        successText: (_) => muted
            ? 'Call muted.'
            : 'Call unmuted.',
      );
    }

    final RegExp speakerPattern = RegExp(
      r'^(turn )?(speaker|speakerphone) (on|off)$',
    );
    final RegExpMatch? speakerMatch =
        speakerPattern.firstMatch(lower);
    if (speakerMatch != null) {
      final bool enabled =
          speakerMatch.group(3) == 'on';
      return _runLocalCapability(
        action: 'phone_set_speaker',
        parameters: <String, dynamic>{
          'enabled': enabled,
        },
        successText: (_) => enabled
            ? 'Speakerphone on.'
            : 'Speakerphone off.',
      );
    }

    final Map<String, String> systemPhrases =
        <String, String>{
      'go home': 'home',
      'home screen': 'home',
      'go back': 'back',
      'show recents': 'recents',
      'show recent apps': 'recents',
      'show notifications': 'notifications',
      'open notifications': 'notifications',
      'show quick settings': 'quick_settings',
      'open quick settings': 'quick_settings',
    };

    final String? systemAction =
        systemPhrases[lower];
    if (systemAction != null) {
      return _runLocalCapability(
        action: 'system_global_action',
        parameters: <String, dynamic>{
          'action': systemAction,
        },
        successText: (_) =>
            'Android action completed.',
      );
    }

    final RegExp typePattern = RegExp(
      r'^type (?:this|the following|text)[: ]+(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? typeMatch =
        typePattern.firstMatch(cleaned);
    if (typeMatch != null) {
      final String text =
          typeMatch.group(1)?.trim() ?? '';
      if (text.isNotEmpty) {
        return _runLocalCapability(
          action: 'system_type_text',
          parameters: <String, dynamic>{
            'text': text,
          },
          successText: (_) =>
              'Text entered into the focused field.',
        );
      }
    }

    final RegExp packagePattern = RegExp(
      r'^(?:open|launch) app package ([a-z0-9_.]+)$',
      caseSensitive: false,
    );
    final RegExpMatch? packageMatch =
        packagePattern.firstMatch(cleaned);
    if (packageMatch != null) {
      final String packageName =
          packageMatch.group(1)?.trim() ?? '';
      return _runLocalCapability(
        action: 'system_launch_app',
        parameters: <String, dynamic>{
          'package_name': packageName,
        },
        successText: (_) =>
            'App launched.',
      );
    }

    if (RegExp(
      r'^(list|show|which|what).*(cloud|jarvis).*(device|devices)',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'list_cloud_devices',
        parameters:
            const <String, dynamic>{},
        successText: _formatCloudDevices,
      );
    }

    return null;
  }

  bool _looksLikeVisionRequest(
    String query,
  ) {
    return RegExp(
      r'\b(what do you see|what am i looking at|look at this|look at that|read this|read that|see what i see|use (the )?camera|through (the )?camera|camera vision)\b',
      caseSensitive: false,
    ).hasMatch(query);
  }

  String _newLocalRequestId(
    String prefix,
  ) {
    return prefix +
        '-' +
        DateTime.now()
            .microsecondsSinceEpoch
            .toString();
  }

  String _runLocalCapability({
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) {
    final String requestId =
        _newLocalRequestId('local');

    _activeRequestId = requestId;
    _currentResponseBuffer = '';
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
        requestId: requestId,
      ),
    );
    _emitResponseBuffer();

    unawaited(
      _executeLocalCapability(
        requestId: requestId,
        action: action,
        parameters: parameters,
        successText: successText,
      ),
    );

    return requestId;
  }

  Future<void> _executeLocalCapability({
    required String requestId,
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) async {
    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'local-' + requestId,
      action: action,
      parameters: parameters,
    );

    if (_disposed ||
        _activeRequestId != requestId) {
      return;
    }

    final String response = result.ok
        ? successText(result.result)
        : (result.error ??
            'Jarvis could not complete that action.');

    _currentResponseBuffer = response;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText: response,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );

    _activeRequestId = null;
    _expectedChunkIndex = 0;
  }

  String _formatCallerIntelligence(
    Map<String, dynamic> result,
  ) {
    final String national =
        result['national_format']?.toString().trim() ?? '';
    final String e164 =
        result['phone_number']?.toString().trim() ?? '';
    final String number =
        national.isNotEmpty ? national : e164;
    final String name =
        result['caller_name']?.toString().trim() ?? '';
    final String type =
        result['caller_type']?.toString().trim() ?? '';
    final String carrier =
        result['carrier_name']?.toString().trim() ?? '';
    final String line =
        result['line_type']?.toString().trim() ?? '';
    final String region =
        result['region']?.toString().trim() ?? '';
    final String country =
        result['country_code']?.toString().trim() ?? '';
    final String error =
        result['lookup_error']?.toString().trim() ?? '';

    final List<String> parts = <String>[];
    parts.add(
      name.isEmpty
          ? 'Caller name was not returned'
          : 'Caller: ' +
              name +
              (type.isEmpty ? '' : ' (' + type + ')'),
    );
    if (number.isNotEmpty) {
      parts.add('Number: ' + number);
    }

    final String network = <String>[
      carrier,
      line,
    ].where((String value) => value.isNotEmpty)
        .join(' • ');
    if (network.isNotEmpty) {
      parts.add('Carrier/line: ' + network);
    }

    final String location = <String>[
      region,
      country,
    ].where((String value) => value.isNotEmpty)
        .join(' • ');
    if (location.isNotEmpty) {
      parts.add('Number region: ' + location);
    }

    if (error.isNotEmpty) {
      parts.add(error);
    }

    parts.add(
      "Number region is not the caller's live GPS location",
    );
    return parts.join('. ') + '.';
  }

  String _formatCloudDevices(
    Map<String, dynamic> result,
  ) {
    final Object? raw = result['devices'];

    if (raw is! List || raw.isEmpty) {
      return 'No Jarvis cloud devices are registered yet.';
    }

    final List<String> labels =
        <String>[];

    for (final Object? value in raw) {
      if (value is! Map) {
        continue;
      }

      final String name =
          value['device_name']
                  ?.toString() ??
              'Jarvis device';
      final bool online =
          value['online'] == true;
      final bool active =
          value['active_avatar'] == true;

      labels.add(
        name +
            (online
                ? ' (online'
                : ' (offline') +
            (active
                ? ', Jarvis active here)'
                : ')'),
      );
    }

    return labels.isEmpty
        ? 'No Jarvis cloud devices are registered yet.'
        : 'Jarvis devices: ' +
            labels.join(', ') +
            '.';
  }

  Future<void> _prepareVisionAndSend(
    String preparationRequestId,
    String query,
  ) async {
    _activeRequestId =
        preparationRequestId;
    _currentResponseBuffer =
        'Updating camera vision...';
    _expectedChunkIndex = 0;

    _emitResponseBuffer();
    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText:
            _currentResponseBuffer,
        requestId:
            preparationRequestId,
      ),
    );

    final JarvisCapabilityResult vision =
        await _capabilityService.execute(
      requestId:
          preparationRequestId,
      callId:
          'vision-' +
              preparationRequestId,
      action: 'vision_refresh',
      parameters:
          const <String, dynamic>{},
    );

    if (_disposed ||
        _activeRequestId !=
            preparationRequestId) {
      return;
    }

    if (!vision.ok) {
      final String error = vision.error ??
          'Camera vision could not be refreshed.';

      _currentResponseBuffer = error;
      _emitResponseBuffer();
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: error,
          requestId:
              preparationRequestId,
          errorMessage: error,
          retryable: true,
        ),
      );

      _activeRequestId = null;
      return;
    }

    _activeRequestId = null;

    _sendRemoteQuery(
      query +
          '\n\nJARVIS VISION CONTEXT: Use the latest camera frame currently available to Jarvis to answer this request.',
    );
  }

  bool _shouldAutoPrint(String query) {
    final String lower =
        query.toLowerCase();

    if (!RegExp(r'\bprint\b')
        .hasMatch(lower)) {
      return false;
    }

    final bool informationalQuestion =
        RegExp(
      r'\b(how (do|can|should) i|how to|what is|why does|where do i)\b',
    ).hasMatch(lower);

    if (informationalQuestion) {
      return false;
    }

    final bool hasDocumentObject = RegExp(
      r'\b(document|letter|invoice|receipt|estimate|proposal|report|contract|agreement|form|notice|memo|page|it|this|that)\b',
    ).hasMatch(lower);

    final bool hasCreationIntent = RegExp(
      r'\b(create|make|write|draft|prepare|generate|compose)\b',
    ).hasMatch(lower);

    final bool directPrintIntent = RegExp(
      r'\bprint\s+(this|it|that|the|my|a|an)\b',
    ).hasMatch(lower);

    return hasDocumentObject &&
        (hasCreationIntent ||
            directPrintIntent);
  }

  String _buildAutoPrintQuery(
    String original,
  ) {
    return '''
${original}

JARVIS PRINT EXECUTION INSTRUCTION:
The user explicitly asked for a document to be printed. Create the finished document now. Output only the finished printable artifact with no explanation before or after it. Put a first line exactly in this format:
PRINT_TITLE: <short document title>

Then add one blank line and the complete document body. Do not include markdown code fences.
''';
  }

  Future<void>
      _routeCompletedDocumentForPrinting({
    required String requestId,
    required String rawResponse,
  }) async {
    final String normalized =
        rawResponse.trim();

    if (normalized.isEmpty) {
      return;
    }

    String title = 'Jarvis Document';
    String body = normalized;

    final List<String> lines =
        normalized.split('\n');

    if (lines.isNotEmpty &&
        lines.first
            .trimLeft()
            .startsWith('PRINT_TITLE:')) {
      final String parsedTitle =
          lines.first
              .substring(
                lines.first.indexOf(':') + 1,
              )
              .trim();

      if (parsedTitle.isNotEmpty) {
        title = parsedTitle;
      }

      body = lines
          .skip(1)
          .join('\n')
          .trim();
    }

    if (body.isEmpty) {
      return;
    }

    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'auto-print-${requestId}',
      action:
          'create_and_print_document',
      parameters: <String, dynamic>{
        'title': title,
        'document_text': body,
        'copies': 1,
      },
    );

    if (_disposed) {
      return;
    }

    final String statusText;
    if (result.ok) {
      final String target =
          result.result['target_device_name']
                  ?.toString() ??
              'printer host';
      final String printer =
          result.result['printer_name']
                  ?.toString() ??
              'printer';

      statusText =
          '\n\nJarvis print routing: sent to ${target} → ${printer}.';
    } else {
      statusText =
          '\n\nJarvis print routing failed: ${result.error ?? 'No printer-ready Android device is available.'}';
    }

    _currentResponseBuffer =
        body + statusText;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText:
            _currentResponseBuffer,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );
  }

  void cancelCurrentResponse() {
    _ensureNotDisposed();

    final String? requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }

    _autoPrintRequestIds.remove(requestId);
    _activeRequestId = null;
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.cancelled,
        responseText: _currentResponseBuffer,
        requestId: requestId,
      ),
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
      final bool autoPrint =
          _autoPrintRequestIds.remove(
        event.requestId,
      );

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.completed,
          responseText: _currentResponseBuffer,
          requestId: event.requestId,
        ),
      );

      if (autoPrint) {
        unawaited(
          _routeCompletedDocumentForPrinting(
            requestId: event.requestId,
            rawResponse:
                _currentResponseBuffer,
          ),
        );
      }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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
    _autoPrintRequestIds.clear();

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _responseBufferController.close(),
      _themeModeController.close(),
    ]);
  }
}
,
      caseSensitive: false,
    );
    final RegExpMatch? callerLookupMatch =
        callerLookupPattern.firstMatch(cleaned);

    if (callerLookupMatch != null) {
      final String number =
          callerLookupMatch.group(1)?.trim() ?? '';
      if (number.isNotEmpty) {
        return _runLocalCapability(
          action: 'phone_caller_lookup',
          parameters: <String, dynamic>{
            'phone_number': number,
          },
          successText: _formatCallerIntelligence,
        );
      }
    }

    if (RegExp(
      r'^(answer|pick up)( the)? (call|phone)
      return _runLocalCapability(
        action: 'phone_answer_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call answered.',
      );
    }

    if (RegExp(
      r'^(reject|decline)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_reject_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call rejected.',
      );
    }

    if (RegExp(
      r'^(hang up|end)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_end_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call ended.',
      );
    }

    final RegExp mutePattern = RegExp(
      r'^(mute|unmute)( the)? (call|phone|microphone|mic)$',
    );
    final RegExpMatch? muteMatch =
        mutePattern.firstMatch(lower);
    if (muteMatch != null) {
      final bool muted =
          muteMatch.group(1) == 'mute';
      return _runLocalCapability(
        action: 'phone_set_mute',
        parameters: <String, dynamic>{
          'muted': muted,
        },
        successText: (_) => muted
            ? 'Call muted.'
            : 'Call unmuted.',
      );
    }

    final RegExp speakerPattern = RegExp(
      r'^(turn )?(speaker|speakerphone) (on|off)$',
    );
    final RegExpMatch? speakerMatch =
        speakerPattern.firstMatch(lower);
    if (speakerMatch != null) {
      final bool enabled =
          speakerMatch.group(3) == 'on';
      return _runLocalCapability(
        action: 'phone_set_speaker',
        parameters: <String, dynamic>{
          'enabled': enabled,
        },
        successText: (_) => enabled
            ? 'Speakerphone on.'
            : 'Speakerphone off.',
      );
    }

    final Map<String, String> systemPhrases =
        <String, String>{
      'go home': 'home',
      'home screen': 'home',
      'go back': 'back',
      'show recents': 'recents',
      'show recent apps': 'recents',
      'show notifications': 'notifications',
      'open notifications': 'notifications',
      'show quick settings': 'quick_settings',
      'open quick settings': 'quick_settings',
    };

    final String? systemAction =
        systemPhrases[lower];
    if (systemAction != null) {
      return _runLocalCapability(
        action: 'system_global_action',
        parameters: <String, dynamic>{
          'action': systemAction,
        },
        successText: (_) =>
            'Android action completed.',
      );
    }

    final RegExp typePattern = RegExp(
      r'^type (?:this|the following|text)[: ]+(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? typeMatch =
        typePattern.firstMatch(cleaned);
    if (typeMatch != null) {
      final String text =
          typeMatch.group(1)?.trim() ?? '';
      if (text.isNotEmpty) {
        return _runLocalCapability(
          action: 'system_type_text',
          parameters: <String, dynamic>{
            'text': text,
          },
          successText: (_) =>
              'Text entered into the focused field.',
        );
      }
    }

    final RegExp packagePattern = RegExp(
      r'^(?:open|launch) app package ([a-z0-9_.]+)$',
      caseSensitive: false,
    );
    final RegExpMatch? packageMatch =
        packagePattern.firstMatch(cleaned);
    if (packageMatch != null) {
      final String packageName =
          packageMatch.group(1)?.trim() ?? '';
      return _runLocalCapability(
        action: 'system_launch_app',
        parameters: <String, dynamic>{
          'package_name': packageName,
        },
        successText: (_) =>
            'App launched.',
      );
    }

    if (RegExp(
      r'^(list|show|which|what).*(cloud|jarvis).*(device|devices)',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'list_cloud_devices',
        parameters:
            const <String, dynamic>{},
        successText: _formatCloudDevices,
      );
    }

    return null;
  }

  bool _looksLikeVisionRequest(
    String query,
  ) {
    return RegExp(
      r'\b(what do you see|what am i looking at|look at this|look at that|read this|read that|see what i see|use (the )?camera|through (the )?camera|camera vision)\b',
      caseSensitive: false,
    ).hasMatch(query);
  }

  String _newLocalRequestId(
    String prefix,
  ) {
    return prefix +
        '-' +
        DateTime.now()
            .microsecondsSinceEpoch
            .toString();
  }

  String _runLocalCapability({
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) {
    final String requestId =
        _newLocalRequestId('local');

    _activeRequestId = requestId;
    _currentResponseBuffer = '';
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
        requestId: requestId,
      ),
    );
    _emitResponseBuffer();

    unawaited(
      _executeLocalCapability(
        requestId: requestId,
        action: action,
        parameters: parameters,
        successText: successText,
      ),
    );

    return requestId;
  }

  Future<void> _executeLocalCapability({
    required String requestId,
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) async {
    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'local-' + requestId,
      action: action,
      parameters: parameters,
    );

    if (_disposed ||
        _activeRequestId != requestId) {
      return;
    }

    final String response = result.ok
        ? successText(result.result)
        : (result.error ??
            'Jarvis could not complete that action.');

    _currentResponseBuffer = response;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText: response,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );

    _activeRequestId = null;
    _expectedChunkIndex = 0;
  }

  String _formatCloudDevices(
    Map<String, dynamic> result,
  ) {
    final Object? raw = result['devices'];

    if (raw is! List || raw.isEmpty) {
      return 'No Jarvis cloud devices are registered yet.';
    }

    final List<String> labels =
        <String>[];

    for (final Object? value in raw) {
      if (value is! Map) {
        continue;
      }

      final String name =
          value['device_name']
                  ?.toString() ??
              'Jarvis device';
      final bool online =
          value['online'] == true;
      final bool active =
          value['active_avatar'] == true;

      labels.add(
        name +
            (online
                ? ' (online'
                : ' (offline') +
            (active
                ? ', Jarvis active here)'
                : ')'),
      );
    }

    return labels.isEmpty
        ? 'No Jarvis cloud devices are registered yet.'
        : 'Jarvis devices: ' +
            labels.join(', ') +
            '.';
  }

  Future<void> _prepareVisionAndSend(
    String preparationRequestId,
    String query,
  ) async {
    _activeRequestId =
        preparationRequestId;
    _currentResponseBuffer =
        'Updating camera vision...';
    _expectedChunkIndex = 0;

    _emitResponseBuffer();
    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText:
            _currentResponseBuffer,
        requestId:
            preparationRequestId,
      ),
    );

    final JarvisCapabilityResult vision =
        await _capabilityService.execute(
      requestId:
          preparationRequestId,
      callId:
          'vision-' +
              preparationRequestId,
      action: 'vision_refresh',
      parameters:
          const <String, dynamic>{},
    );

    if (_disposed ||
        _activeRequestId !=
            preparationRequestId) {
      return;
    }

    if (!vision.ok) {
      final String error = vision.error ??
          'Camera vision could not be refreshed.';

      _currentResponseBuffer = error;
      _emitResponseBuffer();
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: error,
          requestId:
              preparationRequestId,
          errorMessage: error,
          retryable: true,
        ),
      );

      _activeRequestId = null;
      return;
    }

    _activeRequestId = null;

    _sendRemoteQuery(
      query +
          '\n\nJARVIS VISION CONTEXT: Use the latest camera frame currently available to Jarvis to answer this request.',
    );
  }

  bool _shouldAutoPrint(String query) {
    final String lower =
        query.toLowerCase();

    if (!RegExp(r'\bprint\b')
        .hasMatch(lower)) {
      return false;
    }

    final bool informationalQuestion =
        RegExp(
      r'\b(how (do|can|should) i|how to|what is|why does|where do i)\b',
    ).hasMatch(lower);

    if (informationalQuestion) {
      return false;
    }

    final bool hasDocumentObject = RegExp(
      r'\b(document|letter|invoice|receipt|estimate|proposal|report|contract|agreement|form|notice|memo|page|it|this|that)\b',
    ).hasMatch(lower);

    final bool hasCreationIntent = RegExp(
      r'\b(create|make|write|draft|prepare|generate|compose)\b',
    ).hasMatch(lower);

    final bool directPrintIntent = RegExp(
      r'\bprint\s+(this|it|that|the|my|a|an)\b',
    ).hasMatch(lower);

    return hasDocumentObject &&
        (hasCreationIntent ||
            directPrintIntent);
  }

  String _buildAutoPrintQuery(
    String original,
  ) {
    return '''
${original}

JARVIS PRINT EXECUTION INSTRUCTION:
The user explicitly asked for a document to be printed. Create the finished document now. Output only the finished printable artifact with no explanation before or after it. Put a first line exactly in this format:
PRINT_TITLE: <short document title>

Then add one blank line and the complete document body. Do not include markdown code fences.
''';
  }

  Future<void>
      _routeCompletedDocumentForPrinting({
    required String requestId,
    required String rawResponse,
  }) async {
    final String normalized =
        rawResponse.trim();

    if (normalized.isEmpty) {
      return;
    }

    String title = 'Jarvis Document';
    String body = normalized;

    final List<String> lines =
        normalized.split('\n');

    if (lines.isNotEmpty &&
        lines.first
            .trimLeft()
            .startsWith('PRINT_TITLE:')) {
      final String parsedTitle =
          lines.first
              .substring(
                lines.first.indexOf(':') + 1,
              )
              .trim();

      if (parsedTitle.isNotEmpty) {
        title = parsedTitle;
      }

      body = lines
          .skip(1)
          .join('\n')
          .trim();
    }

    if (body.isEmpty) {
      return;
    }

    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'auto-print-${requestId}',
      action:
          'create_and_print_document',
      parameters: <String, dynamic>{
        'title': title,
        'document_text': body,
        'copies': 1,
      },
    );

    if (_disposed) {
      return;
    }

    final String statusText;
    if (result.ok) {
      final String target =
          result.result['target_device_name']
                  ?.toString() ??
              'printer host';
      final String printer =
          result.result['printer_name']
                  ?.toString() ??
              'printer';

      statusText =
          '\n\nJarvis print routing: sent to ${target} → ${printer}.';
    } else {
      statusText =
          '\n\nJarvis print routing failed: ${result.error ?? 'No printer-ready Android device is available.'}';
    }

    _currentResponseBuffer =
        body + statusText;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText:
            _currentResponseBuffer,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );
  }

  void cancelCurrentResponse() {
    _ensureNotDisposed();

    final String? requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }

    _autoPrintRequestIds.remove(requestId);
    _activeRequestId = null;
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.cancelled,
        responseText: _currentResponseBuffer,
        requestId: requestId,
      ),
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
      final bool autoPrint =
          _autoPrintRequestIds.remove(
        event.requestId,
      );

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.completed,
          responseText: _currentResponseBuffer,
          requestId: event.requestId,
        ),
      );

      if (autoPrint) {
        unawaited(
          _routeCompletedDocumentForPrinting(
            requestId: event.requestId,
            rawResponse:
                _currentResponseBuffer,
          ),
        );
      }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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
    _autoPrintRequestIds.clear();

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _responseBufferController.close(),
      _themeModeController.close(),
    ]);
  }
}
,
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_answer_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call answered.',
      );
    }

    if (RegExp(
      r'^(reject|decline)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_reject_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call rejected.',
      );
    }

    if (RegExp(
      r'^(hang up|end)( the)? (call|phone)$',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'phone_end_call',
        parameters: const <String, dynamic>{},
        successText: (_) => 'Call ended.',
      );
    }

    final RegExp mutePattern = RegExp(
      r'^(mute|unmute)( the)? (call|phone|microphone|mic)$',
    );
    final RegExpMatch? muteMatch =
        mutePattern.firstMatch(lower);
    if (muteMatch != null) {
      final bool muted =
          muteMatch.group(1) == 'mute';
      return _runLocalCapability(
        action: 'phone_set_mute',
        parameters: <String, dynamic>{
          'muted': muted,
        },
        successText: (_) => muted
            ? 'Call muted.'
            : 'Call unmuted.',
      );
    }

    final RegExp speakerPattern = RegExp(
      r'^(turn )?(speaker|speakerphone) (on|off)$',
    );
    final RegExpMatch? speakerMatch =
        speakerPattern.firstMatch(lower);
    if (speakerMatch != null) {
      final bool enabled =
          speakerMatch.group(3) == 'on';
      return _runLocalCapability(
        action: 'phone_set_speaker',
        parameters: <String, dynamic>{
          'enabled': enabled,
        },
        successText: (_) => enabled
            ? 'Speakerphone on.'
            : 'Speakerphone off.',
      );
    }

    final Map<String, String> systemPhrases =
        <String, String>{
      'go home': 'home',
      'home screen': 'home',
      'go back': 'back',
      'show recents': 'recents',
      'show recent apps': 'recents',
      'show notifications': 'notifications',
      'open notifications': 'notifications',
      'show quick settings': 'quick_settings',
      'open quick settings': 'quick_settings',
    };

    final String? systemAction =
        systemPhrases[lower];
    if (systemAction != null) {
      return _runLocalCapability(
        action: 'system_global_action',
        parameters: <String, dynamic>{
          'action': systemAction,
        },
        successText: (_) =>
            'Android action completed.',
      );
    }

    final RegExp typePattern = RegExp(
      r'^type (?:this|the following|text)[: ]+(.+)$',
      caseSensitive: false,
    );
    final RegExpMatch? typeMatch =
        typePattern.firstMatch(cleaned);
    if (typeMatch != null) {
      final String text =
          typeMatch.group(1)?.trim() ?? '';
      if (text.isNotEmpty) {
        return _runLocalCapability(
          action: 'system_type_text',
          parameters: <String, dynamic>{
            'text': text,
          },
          successText: (_) =>
              'Text entered into the focused field.',
        );
      }
    }

    final RegExp packagePattern = RegExp(
      r'^(?:open|launch) app package ([a-z0-9_.]+)$',
      caseSensitive: false,
    );
    final RegExpMatch? packageMatch =
        packagePattern.firstMatch(cleaned);
    if (packageMatch != null) {
      final String packageName =
          packageMatch.group(1)?.trim() ?? '';
      return _runLocalCapability(
        action: 'system_launch_app',
        parameters: <String, dynamic>{
          'package_name': packageName,
        },
        successText: (_) =>
            'App launched.',
      );
    }

    if (RegExp(
      r'^(list|show|which|what).*(cloud|jarvis).*(device|devices)',
    ).hasMatch(lower)) {
      return _runLocalCapability(
        action: 'list_cloud_devices',
        parameters:
            const <String, dynamic>{},
        successText: _formatCloudDevices,
      );
    }

    return null;
  }

  bool _looksLikeVisionRequest(
    String query,
  ) {
    return RegExp(
      r'\b(what do you see|what am i looking at|look at this|look at that|read this|read that|see what i see|use (the )?camera|through (the )?camera|camera vision)\b',
      caseSensitive: false,
    ).hasMatch(query);
  }

  String _newLocalRequestId(
    String prefix,
  ) {
    return prefix +
        '-' +
        DateTime.now()
            .microsecondsSinceEpoch
            .toString();
  }

  String _runLocalCapability({
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) {
    final String requestId =
        _newLocalRequestId('local');

    _activeRequestId = requestId;
    _currentResponseBuffer = '';
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText: '',
        requestId: requestId,
      ),
    );
    _emitResponseBuffer();

    unawaited(
      _executeLocalCapability(
        requestId: requestId,
        action: action,
        parameters: parameters,
        successText: successText,
      ),
    );

    return requestId;
  }

  Future<void> _executeLocalCapability({
    required String requestId,
    required String action,
    required Map<String, dynamic> parameters,
    required String Function(
      Map<String, dynamic> result,
    ) successText,
  }) async {
    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'local-' + requestId,
      action: action,
      parameters: parameters,
    );

    if (_disposed ||
        _activeRequestId != requestId) {
      return;
    }

    final String response = result.ok
        ? successText(result.result)
        : (result.error ??
            'Jarvis could not complete that action.');

    _currentResponseBuffer = response;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText: response,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );

    _activeRequestId = null;
    _expectedChunkIndex = 0;
  }

  String _formatCloudDevices(
    Map<String, dynamic> result,
  ) {
    final Object? raw = result['devices'];

    if (raw is! List || raw.isEmpty) {
      return 'No Jarvis cloud devices are registered yet.';
    }

    final List<String> labels =
        <String>[];

    for (final Object? value in raw) {
      if (value is! Map) {
        continue;
      }

      final String name =
          value['device_name']
                  ?.toString() ??
              'Jarvis device';
      final bool online =
          value['online'] == true;
      final bool active =
          value['active_avatar'] == true;

      labels.add(
        name +
            (online
                ? ' (online'
                : ' (offline') +
            (active
                ? ', Jarvis active here)'
                : ')'),
      );
    }

    return labels.isEmpty
        ? 'No Jarvis cloud devices are registered yet.'
        : 'Jarvis devices: ' +
            labels.join(', ') +
            '.';
  }

  Future<void> _prepareVisionAndSend(
    String preparationRequestId,
    String query,
  ) async {
    _activeRequestId =
        preparationRequestId;
    _currentResponseBuffer =
        'Updating camera vision...';
    _expectedChunkIndex = 0;

    _emitResponseBuffer();
    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.thinking,
        responseText:
            _currentResponseBuffer,
        requestId:
            preparationRequestId,
      ),
    );

    final JarvisCapabilityResult vision =
        await _capabilityService.execute(
      requestId:
          preparationRequestId,
      callId:
          'vision-' +
              preparationRequestId,
      action: 'vision_refresh',
      parameters:
          const <String, dynamic>{},
    );

    if (_disposed ||
        _activeRequestId !=
            preparationRequestId) {
      return;
    }

    if (!vision.ok) {
      final String error = vision.error ??
          'Camera vision could not be refreshed.';

      _currentResponseBuffer = error;
      _emitResponseBuffer();
      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.error,
          responseText: error,
          requestId:
              preparationRequestId,
          errorMessage: error,
          retryable: true,
        ),
      );

      _activeRequestId = null;
      return;
    }

    _activeRequestId = null;

    _sendRemoteQuery(
      query +
          '\n\nJARVIS VISION CONTEXT: Use the latest camera frame currently available to Jarvis to answer this request.',
    );
  }

  bool _shouldAutoPrint(String query) {
    final String lower =
        query.toLowerCase();

    if (!RegExp(r'\bprint\b')
        .hasMatch(lower)) {
      return false;
    }

    final bool informationalQuestion =
        RegExp(
      r'\b(how (do|can|should) i|how to|what is|why does|where do i)\b',
    ).hasMatch(lower);

    if (informationalQuestion) {
      return false;
    }

    final bool hasDocumentObject = RegExp(
      r'\b(document|letter|invoice|receipt|estimate|proposal|report|contract|agreement|form|notice|memo|page|it|this|that)\b',
    ).hasMatch(lower);

    final bool hasCreationIntent = RegExp(
      r'\b(create|make|write|draft|prepare|generate|compose)\b',
    ).hasMatch(lower);

    final bool directPrintIntent = RegExp(
      r'\bprint\s+(this|it|that|the|my|a|an)\b',
    ).hasMatch(lower);

    return hasDocumentObject &&
        (hasCreationIntent ||
            directPrintIntent);
  }

  String _buildAutoPrintQuery(
    String original,
  ) {
    return '''
${original}

JARVIS PRINT EXECUTION INSTRUCTION:
The user explicitly asked for a document to be printed. Create the finished document now. Output only the finished printable artifact with no explanation before or after it. Put a first line exactly in this format:
PRINT_TITLE: <short document title>

Then add one blank line and the complete document body. Do not include markdown code fences.
''';
  }

  Future<void>
      _routeCompletedDocumentForPrinting({
    required String requestId,
    required String rawResponse,
  }) async {
    final String normalized =
        rawResponse.trim();

    if (normalized.isEmpty) {
      return;
    }

    String title = 'Jarvis Document';
    String body = normalized;

    final List<String> lines =
        normalized.split('\n');

    if (lines.isNotEmpty &&
        lines.first
            .trimLeft()
            .startsWith('PRINT_TITLE:')) {
      final String parsedTitle =
          lines.first
              .substring(
                lines.first.indexOf(':') + 1,
              )
              .trim();

      if (parsedTitle.isNotEmpty) {
        title = parsedTitle;
      }

      body = lines
          .skip(1)
          .join('\n')
          .trim();
    }

    if (body.isEmpty) {
      return;
    }

    final JarvisCapabilityResult result =
        await _capabilityService.execute(
      requestId: requestId,
      callId: 'auto-print-${requestId}',
      action:
          'create_and_print_document',
      parameters: <String, dynamic>{
        'title': title,
        'document_text': body,
        'copies': 1,
      },
    );

    if (_disposed) {
      return;
    }

    final String statusText;
    if (result.ok) {
      final String target =
          result.result['target_device_name']
                  ?.toString() ??
              'printer host';
      final String printer =
          result.result['printer_name']
                  ?.toString() ??
              'printer';

      statusText =
          '\n\nJarvis print routing: sent to ${target} → ${printer}.';
    } else {
      statusText =
          '\n\nJarvis print routing failed: ${result.error ?? 'No printer-ready Android device is available.'}';
    }

    _currentResponseBuffer =
        body + statusText;
    _emitResponseBuffer();

    _emitState(
      JarvisChatState(
        status: result.ok
            ? JarvisChatStatus.completed
            : JarvisChatStatus.error,
        responseText:
            _currentResponseBuffer,
        requestId: requestId,
        errorMessage:
            result.ok ? null : result.error,
        retryable: !result.ok,
      ),
    );
  }

  void cancelCurrentResponse() {
    _ensureNotDisposed();

    final String? requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }

    _autoPrintRequestIds.remove(requestId);
    _activeRequestId = null;
    _expectedChunkIndex = 0;

    _emitState(
      JarvisChatState(
        status: JarvisChatStatus.cancelled,
        responseText: _currentResponseBuffer,
        requestId: requestId,
      ),
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
      final bool autoPrint =
          _autoPrintRequestIds.remove(
        event.requestId,
      );

      _emitState(
        JarvisChatState(
          status: JarvisChatStatus.completed,
          responseText: _currentResponseBuffer,
          requestId: event.requestId,
        ),
      );

      if (autoPrint) {
        unawaited(
          _routeCompletedDocumentForPrinting(
            requestId: event.requestId,
            rawResponse:
                _currentResponseBuffer,
          ),
        );
      }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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

    if (event.requestId != null) {
      _autoPrintRequestIds.remove(
        event.requestId,
      );
    }

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
    _autoPrintRequestIds.clear();

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _responseBufferController.close(),
      _themeModeController.close(),
    ]);
  }
}
