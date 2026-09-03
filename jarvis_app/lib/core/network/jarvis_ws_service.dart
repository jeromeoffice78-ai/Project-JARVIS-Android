import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

enum JarvisConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  closing,
}

final class JarvisWsException implements Exception {
  const JarvisWsException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'JarvisWsException: $message';
    }
    return 'JarvisWsException: $message ($cause)';
  }
}

typedef JarvisTicketProvider = Future<String?> Function();

class JarvisWsService {
  JarvisWsService({
    required Uri wsUri,
    JarvisTicketProvider? ticketProvider,
    Duration initialReconnectDelay = const Duration(seconds: 1),
    Duration maximumReconnectDelay = const Duration(seconds: 30),
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _baseWsUri = wsUri,
        _ticketProvider = ticketProvider,
        _initialReconnectDelay = initialReconnectDelay,
        _maximumReconnectDelay = maximumReconnectDelay,
        _connectionTimeout = connectionTimeout;

  final Uri _baseWsUri;
  final JarvisTicketProvider? _ticketProvider;
  final Duration _initialReconnectDelay;
  final Duration _maximumReconnectDelay;
  final Duration _connectionTimeout;

  final StreamController<JarvisConnectionState> _stateController =
      StreamController<JarvisConnectionState>.broadcast();

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<JarvisWsException> _errorController =
      StreamController<JarvisWsException>.broadcast();

  final Random _random = Random.secure();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  JarvisConnectionState _state = JarvisConnectionState.disconnected;
  bool _intentionallyClosed = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  int _generation = 0;

  Stream<JarvisConnectionState> get connectionState =>
      _stateController.stream;

  Stream<Map<String, dynamic>> get incomingMessages =>
      _messageController.stream;

  Stream<JarvisWsException> get errors => _errorController.stream;

  JarvisConnectionState get currentState => _state;

  Future<void> connect() async {
    if (_disposed) {
      throw const JarvisWsException(
        'Cannot connect after JarvisWsService has been disposed.',
      );
    }

    if (_state == JarvisConnectionState.connecting ||
        _state == JarvisConnectionState.connected) {
      return;
    }

    _intentionallyClosed = false;
    _cancelReconnectTimer();

    final int generation = ++_generation;

    _setState(
      _reconnectAttempt > 0
          ? JarvisConnectionState.reconnecting
          : JarvisConnectionState.connecting,
    );

    try {
      final Uri uri = await _buildConnectionUri();
      final WebSocketChannel channel = WebSocketChannel.connect(uri);
      _channel = channel;

      await channel.ready.timeout(_connectionTimeout);

      if (_disposed ||
          _intentionallyClosed ||
          generation != _generation) {
        await channel.sink.close(
          ws_status.normalClosure,
          'stale_connection',
        );
        return;
      }

      await _subscription?.cancel();

      _subscription = channel.stream.listen(
        (dynamic message) => _handleRawMessage(message, generation),
        onError: (Object error, StackTrace stackTrace) {
          _emitError(
            JarvisWsException(
              'Jarvis WebSocket transport error.',
              cause: error,
            ),
          );
          unawaited(_handleDisconnect(generation));
        },
        onDone: () {
          unawaited(_handleDisconnect(generation));
        },
        cancelOnError: true,
      );
    } on Object catch (error) {
      _emitError(
        JarvisWsException(
          'Unable to establish Jarvis WebSocket connection.',
          cause: error,
        ),
      );
      await _handleDisconnect(generation);
    }
  }

  Future<Uri> _buildConnectionUri() async {
    final JarvisTicketProvider? provider = _ticketProvider;

    if (provider == null) {
      return _baseWsUri;
    }

    final String? ticket = await provider();

    if (ticket == null || ticket.trim().isEmpty) {
      throw const JarvisWsException(
        'No WebSocket authentication ticket was available.',
      );
    }

    final Map<String, String> query =
        Map<String, String>.from(_baseWsUri.queryParameters);
    query['ticket'] = ticket;

    return _baseWsUri.replace(queryParameters: query);
  }

  void _handleRawMessage(dynamic rawMessage, int generation) {
    if (_disposed || generation != _generation) {
      return;
    }

    try {
      if (rawMessage is! String) {
        throw const FormatException('Expected a WebSocket text frame.');
      }

      final Object? decoded = jsonDecode(rawMessage);

      if (decoded is! Map) {
        throw const FormatException('Jarvis event must be a JSON object.');
      }

      final Map<String, dynamic> event =
          Map<String, dynamic>.from(decoded);

      final Object? type = event['type'];

      if (type == 'ping') {
        final Object? pingId = event['ping_id'];

        if (pingId is String && pingId.isNotEmpty) {
          sendJson(<String, dynamic>{
            'type': 'pong',
            'ping_id': pingId,
          });
        }
        return;
      }

      if (type == 'system' &&
          event['message'] == 'Jarvis online.') {
        _reconnectAttempt = 0;
        _setState(JarvisConnectionState.connected);
      }

      if (!_messageController.isClosed) {
        _messageController.add(event);
      }
    } on Object catch (error) {
      _emitError(
        JarvisWsException(
          'Failed to process Jarvis WebSocket event.',
          cause: error,
        ),
      );
    }
  }

  void sendJson(Map<String, dynamic> event) {
    if (_disposed) {
      throw const JarvisWsException(
        'JarvisWsService has been disposed.',
      );
    }

    final WebSocketChannel? channel = _channel;

    if (channel == null) {
      throw const JarvisWsException(
        'Jarvis WebSocket is not connected.',
      );
    }

    if (!event.containsKey('type')) {
      throw const JarvisWsException(
        'Jarvis events require a "type" field.',
      );
    }

    channel.sink.add(jsonEncode(event));
  }

  Future<void> _handleDisconnect(int generation) async {
    if (generation != _generation) {
      return;
    }

    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;

    if (subscription != null) {
      try {
        await subscription.cancel();
      } on Object {
        // Continue cleanup.
      }
    }

    final WebSocketChannel? channel = _channel;
    _channel = null;

    if (channel != null) {
      try {
        await channel.sink.close();
      } on Object {
        // Continue cleanup.
      }
    }

    if (_disposed) {
      return;
    }

    _setState(JarvisConnectionState.disconnected);

    if (!_intentionallyClosed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed ||
        _intentionallyClosed ||
        (_reconnectTimer?.isActive ?? false)) {
      return;
    }

    _reconnectAttempt++;
    _setState(JarvisConnectionState.reconnecting);

    final int exponent = min(_reconnectAttempt - 1, 5);
    final int baseMs =
        _initialReconnectDelay.inMilliseconds * (1 << exponent);
    final int cappedMs = min(
      baseMs,
      _maximumReconnectDelay.inMilliseconds,
    );

    final int jitteredMs = min(
      (cappedMs * (1.0 + (_random.nextDouble() * 0.25))).round(),
      _maximumReconnectDelay.inMilliseconds,
    );

    _reconnectTimer = Timer(
      Duration(milliseconds: jitteredMs),
      () {
        _reconnectTimer = null;

        if (!_disposed && !_intentionallyClosed) {
          unawaited(connect());
        }
      },
    );
  }

  void _setState(JarvisConnectionState state) {
    if (_disposed || _stateController.isClosed || state == _state) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  void _emitError(JarvisWsException error) {
    if (!_disposed && !_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> disconnect() async {
    if (_disposed) {
      return;
    }

    _intentionallyClosed = true;
    _cancelReconnectTimer();
    _setState(JarvisConnectionState.closing);
    _generation++;

    await _subscription?.cancel();
    _subscription = null;

    final WebSocketChannel? channel = _channel;
    _channel = null;

    if (channel != null) {
      await channel.sink.close(
        ws_status.normalClosure,
        'client_disconnect',
      );
    }

    _setState(JarvisConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _intentionallyClosed = true;
    _cancelReconnectTimer();
    _generation++;

    await _subscription?.cancel();
    _subscription = null;

    final WebSocketChannel? channel = _channel;
    _channel = null;

    if (channel != null) {
      try {
        await channel.sink.close(
          ws_status.goingAway,
          'service_disposed',
        );
      } on Object {
        // Continue disposal.
      }
    }

    _disposed = true;

    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _messageController.close(),
      _errorController.close(),
    ]);
  }
}
