import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

final class JarvisVoiceIdentityMatch {
  const JarvisVoiceIdentityMatch({
    required this.matched,
    required this.personId,
    required this.similarity,
    required this.secondSimilarity,
    required this.separation,
    required this.threshold,
    required this.margin,
    required this.reason,
  });

  final bool matched;
  final String personId;
  final double similarity;
  final double secondSimilarity;
  final double separation;
  final double threshold;
  final double margin;
  final String reason;

  factory JarvisVoiceIdentityMatch.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisVoiceIdentityMatch(
      matched: raw['matched'] == true,
      personId:
          raw['personId']?.toString() ?? '',
      similarity:
          (raw['similarity'] as num?)
                  ?.toDouble() ??
              0,
      secondSimilarity:
          (raw['secondSimilarity'] as num?)
                  ?.toDouble() ??
              0,
      separation:
          (raw['separation'] as num?)
                  ?.toDouble() ??
              0,
      threshold:
          (raw['threshold'] as num?)
                  ?.toDouble() ??
              0,
      margin:
          (raw['margin'] as num?)
                  ?.toDouble() ??
              0,
      reason:
          raw['reason']?.toString() ?? '',
    );
  }
}

class JarvisVoiceIdentityService {
  static const MethodChannel _channel =
      MethodChannel('jarvis.voice_identity');

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform ==
          TargetPlatform.android;

  Future<bool> _ensureMicrophone() async {
    if (!isSupported) {
      return false;
    }

    final PermissionStatus current =
        await Permission.microphone.status;

    if (current.isGranted) {
      return true;
    }

    final PermissionStatus requested =
        await Permission.microphone.request();

    return requested.isGranted;
  }

  Future<void> enrollVoice(
    String personId,
  ) async {
    if (!isSupported) {
      throw StateError(
        'Voice identity is only available on Android.',
      );
    }

    if (!(await _ensureMicrophone())) {
      throw StateError(
        'Microphone permission is required to enroll a voice.',
      );
    }

    final String normalized =
        personId.trim();

    if (normalized.isEmpty) {
      throw ArgumentError(
        'A person ID is required.',
      );
    }

    await _channel.invokeMethod<dynamic>(
      'enrollVoice',
      <String, dynamic>{
        'personId': normalized,
      },
    );
  }

  Future<JarvisVoiceIdentityMatch>
      identifySpeaker() async {
    if (!isSupported) {
      return const JarvisVoiceIdentityMatch(
        matched: false,
        personId: '',
        similarity: 0,
        secondSimilarity: 0,
        separation: 0,
        threshold: 0,
        margin: 0,
        reason: 'unsupported',
      );
    }

    if (!(await _ensureMicrophone())) {
      return const JarvisVoiceIdentityMatch(
        matched: false,
        personId: '',
        similarity: 0,
        secondSimilarity: 0,
        separation: 0,
        threshold: 0,
        margin: 0,
        reason: 'microphone_denied',
      );
    }

    final Map<dynamic, dynamic>? raw =
        await _channel
            .invokeMapMethod<dynamic, dynamic>(
      'identifySpeaker',
    );

    if (raw == null) {
      throw StateError(
        'Android returned no voice identity result.',
      );
    }

    return JarvisVoiceIdentityMatch.fromMap(
      raw,
    );
  }

  Future<Set<String>>
      listVoiceProfileIds() async {
    if (!isSupported) {
      return const <String>{};
    }

    final List<dynamic>? raw =
        await _channel.invokeMethod<List<dynamic>>(
      'listVoiceProfileIds',
    );

    return (raw ?? const <dynamic>[])
        .map((dynamic value) => value.toString())
        .where((String value) => value.isNotEmpty)
        .toSet();
  }

  Future<bool> hasVoiceProfile(
    String personId,
  ) async {
    if (!isSupported) {
      return false;
    }

    return await _channel.invokeMethod<bool>(
          'hasVoiceProfile',
          <String, dynamic>{
            'personId': personId.trim(),
          },
        ) ??
        false;
  }

  Future<void> deleteVoiceProfile(
    String personId,
  ) async {
    if (!isSupported) {
      return;
    }

    await _channel.invokeMethod<void>(
      'deleteVoiceProfile',
      <String, dynamic>{
        'personId': personId.trim(),
      },
    );
  }
}
