import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JarvisCallMessage {
  const JarvisCallMessage({
    required this.id,
    required this.phoneNumber,
    required this.timestamp,
    required this.status,
    required this.message,
  });

  final String id;
  final String phoneNumber;
  final DateTime timestamp;
  final String status;
  final String message;

  factory JarvisCallMessage.fromJson(
    Map<String, dynamic> json,
  ) {
    final int rawTimestamp =
        (json['timestamp'] as num?)?.toInt() ?? 0;

    return JarvisCallMessage(
      id: json['id']?.toString() ?? '',
      phoneNumber:
          json['phone_number']?.toString() ??
          'Unknown caller',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp,
      ),
      status: json['status']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class JarvisActiveCall {
  const JarvisActiveCall({
    required this.phoneNumber,
    required this.state,
    required this.isIncoming,
    required this.isMuted,
    required this.audioRoute,
  });

  final String phoneNumber;
  final String state;
  final bool isIncoming;
  final bool isMuted;
  final String audioRoute;

  bool get isRinging => state == 'ringing';
  bool get isActive => state == 'active';

  factory JarvisActiveCall.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisActiveCall(
      phoneNumber:
          raw['phoneNumber']?.toString() ??
              'Unknown caller',
      state:
          raw['state']?.toString() ??
              'unknown',
      isIncoming:
          raw['isIncoming'] == true,
      isMuted:
          raw['isMuted'] == true,
      audioRoute:
          raw['audioRoute']?.toString() ??
              'unknown',
    );
  }
}

class JarvisPhoneService {
  static const MethodChannel _channel =
      MethodChannel('jarvis.phone');

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<String> consumeLaunchTarget() async {
    if (!isSupported) return '';
    try {
      return await _channel.invokeMethod<String>(
            'consumeLaunchTarget',
          ) ??
          '';
    } on PlatformException {
      return '';
    }
  }

  Future<bool> isDefaultDialer() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isDefaultDialer',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestDefaultDialer() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestDefaultDialer',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> getAutoAnswer() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'getAutoAnswer',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setAutoAnswer(bool enabled) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'setAutoAnswer',
      <String, dynamic>{'enabled': enabled},
    );
  }

  Future<String> getGreeting() async {
    if (!isSupported) return '';
    try {
      return await _channel.invokeMethod<String>(
            'getGreeting',
          ) ??
          '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> setGreeting(String greeting) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'setGreeting',
      <String, dynamic>{'greeting': greeting},
    );
  }

  Future<List<JarvisCallMessage>>
      listCallMessages() async {
    if (!isSupported) {
      return const <JarvisCallMessage>[];
    }

    try {
      final String payload =
          await _channel.invokeMethod<String>(
                'listCallMessages',
              ) ??
              '[]';

      final Object? decoded = jsonDecode(payload);
      if (decoded is! List) {
        return const <JarvisCallMessage>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (Map raw) =>
                JarvisCallMessage.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          )
          .toList(growable: false);
    } on Object {
      return const <JarvisCallMessage>[];
    }
  }

  Future<JarvisActiveCall?> getActiveCall() async {
    if (!isSupported) return null;

    try {
      final Map<dynamic, dynamic>? raw =
          await _channel.invokeMethod<
              Map<dynamic, dynamic>>(
        'getActiveCall',
      );
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return JarvisActiveCall.fromMap(raw);
    } on PlatformException {
      return null;
    }
  }

  Future<bool> answerActiveCall() async {
    return _invokeCallControl('answerActiveCall');
  }

  Future<bool> rejectActiveCall() async {
    return _invokeCallControl('rejectActiveCall');
  }

  Future<bool> disconnectActiveCall() async {
    return _invokeCallControl(
      'disconnectActiveCall',
    );
  }

  Future<bool> setMuted(bool muted) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setMuted',
            <String, dynamic>{'muted': muted},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setSpeaker(bool enabled) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setSpeaker',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _invokeCallControl(
    String method,
  ) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            method,
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> clearCallMessages() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'clearCallMessages',
    );
  }
}
