import 'dart:math';

sealed class JarvisEvent {
  const JarvisEvent({required this.type});
  final String type;
}

final class JarvisProtocolException implements Exception {
  const JarvisProtocolException(this.message);
  final String message;

  @override
  String toString() => 'JarvisProtocolException: $message';
}

final class UserTextQueryEvent {
  UserTextQueryEvent({
    required String text,
    String? requestId,
  })  : text = text.trim(),
        requestId = requestId ?? generateUuidV4() {
    if (this.text.isEmpty) {
      throw const JarvisProtocolException('User text cannot be empty.');
    }
  }

  static const String eventType = 'user_text';

  final String requestId;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': eventType,
        'request_id': requestId,
        'payload': <String, dynamic>{'text': text},
      };
}

final class CancelResponseEvent {
  const CancelResponseEvent({this.requestId});
  static const String eventType = 'cancel_response';
  final String? requestId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': eventType,
        if (requestId != null) 'request_id': requestId,
      };
}

final class ToolResultEvent {
  const ToolResultEvent({
    required this.requestId,
    required this.callId,
    required this.ok,
    required this.result,
    this.error,
  });

  static const String eventType = 'tool_result';
  final String requestId;
  final String callId;
  final bool ok;
  final Map<String, dynamic> result;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': eventType,
        'request_id': requestId,
        'call_id': callId,
        'payload': <String, dynamic>{
          'ok': ok,
          'result': result,
          if (error != null) 'error': error,
        },
      };
}

final class AgentTextChunkEvent extends JarvisEvent {
  const AgentTextChunkEvent({
    required this.requestId,
    required this.chunkIndex,
    required this.textChunk,
    required this.isFinal,
    this.responseId,
  }) : super(type: eventType);

  static const String eventType = 'agent_text_chunk';
  final String requestId;
  final String? responseId;
  final int chunkIndex;
  final String textChunk;
  final bool isFinal;
}

final class SystemCommandEvent extends JarvisEvent {
  const SystemCommandEvent({
    required this.requestId,
    required this.callId,
    required this.action,
    required this.parameters,
  }) : super(type: eventType);

  static const String eventType = 'system_command';
  final String requestId;
  final String callId;
  final String action;
  final Map<String, dynamic> parameters;
}

final class JarvisErrorEvent extends JarvisEvent {
  const JarvisErrorEvent({
    required this.code,
    required this.message,
    required this.retryable,
    this.requestId,
  }) : super(type: eventType);

  static const String eventType = 'error';
  final String? requestId;
  final String code;
  final String message;
  final bool retryable;
}

final class ResponseCancelledEvent extends JarvisEvent {
  const ResponseCancelledEvent({this.requestId})
      : super(type: eventType);

  static const String eventType = 'response_cancelled';
  final String? requestId;
}

final class UnknownJarvisEvent extends JarvisEvent {
  const UnknownJarvisEvent({
    required super.type,
    required this.data,
  });
  final Map<String, dynamic> data;
}

abstract final class JarvisEventParser {
  static JarvisEvent parse(Map<String, dynamic> raw) {
    final Object? rawType = raw['type'];

    if (rawType is! String || rawType.isEmpty) {
      throw const JarvisProtocolException('Inbound event has no valid type.');
    }

    return switch (rawType) {
      AgentTextChunkEvent.eventType => _parseText(raw),
      SystemCommandEvent.eventType => _parseCommand(raw),
      JarvisErrorEvent.eventType => JarvisErrorEvent(
          requestId: _optionalString(raw['request_id']),
          code: _optionalString(raw['code']) ?? 'unknown_error',
          message: _optionalString(raw['message']) ?? 'Unknown Jarvis error.',
          retryable: raw['retryable'] is bool ? raw['retryable'] as bool : false,
        ),
      ResponseCancelledEvent.eventType => ResponseCancelledEvent(
          requestId: _optionalString(raw['request_id']),
        ),
      _ => UnknownJarvisEvent(
          type: rawType,
          data: Map<String, dynamic>.unmodifiable(raw),
        ),
    };
  }

  static AgentTextChunkEvent _parseText(Map<String, dynamic> raw) {
    final payload = _requireMap(raw, 'payload');
    final Object? index = payload['chunk_index'];
    final Object? text = payload['text_chunk'];
    final Object? isFinal = payload['is_final'];

    if (index is! int || index < 0 || text is! String || isFinal is! bool) {
      throw const JarvisProtocolException('Invalid agent_text_chunk payload.');
    }

    return AgentTextChunkEvent(
      requestId: _requireString(raw, 'request_id'),
      responseId: _optionalString(raw['response_id']),
      chunkIndex: index,
      textChunk: text,
      isFinal: isFinal,
    );
  }

  static SystemCommandEvent _parseCommand(Map<String, dynamic> raw) {
    final payload = _requireMap(raw, 'payload');

    return SystemCommandEvent(
      requestId: _requireString(raw, 'request_id'),
      callId: _requireString(raw, 'call_id'),
      action: _requireString(payload, 'action'),
      parameters: _requireMap(payload, 'parameters'),
    );
  }

  static Map<String, dynamic> _requireMap(
    Map<String, dynamic> map,
    String key,
  ) {
    final Object? value = map[key];
    if (value is! Map) {
      throw JarvisProtocolException('Missing/invalid object field "$key".');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _requireString(
    Map<String, dynamic> map,
    String key,
  ) {
    final Object? value = map[key];
    if (value is! String || value.isEmpty) {
      throw JarvisProtocolException('Missing/invalid string field "$key".');
    }
    return value;
  }

  static String? _optionalString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }
}

String generateUuidV4() {
  final Random random = Random.secure();
  final List<int> bytes =
      List<int>.generate(16, (_) => random.nextInt(256), growable: false);

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');

  return '${bytes.sublist(0, 4).map(hex).join()}-'
      '${bytes.sublist(4, 6).map(hex).join()}-'
      '${bytes.sublist(6, 8).map(hex).join()}-'
      '${bytes.sublist(8, 10).map(hex).join()}-'
      '${bytes.sublist(10, 16).map(hex).join()}';
}
