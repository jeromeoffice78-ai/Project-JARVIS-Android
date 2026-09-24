import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JarvisDeviceIssue {
  const JarvisDeviceIssue({
    required this.code,
    required this.severity,
    required this.summary,
    required this.repair,
  });

  final String code;
  final String severity;
  final String summary;
  final String repair;

  factory JarvisDeviceIssue.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisDeviceIssue(
      code: raw['code']?.toString() ?? '',
      severity:
          raw['severity']?.toString() ??
              'unknown',
      summary:
          raw['summary']?.toString() ??
              'Device issue detected.',
      repair:
          raw['repair']?.toString() ??
              'settings',
    );
  }
}

class JarvisAppThreat {
  const JarvisAppThreat({
    required this.label,
    required this.packageName,
    required this.systemApp,
    required this.installer,
    required this.riskScore,
    required this.riskLevel,
    required this.possibleMalware,
    required this.analysisType,
    required this.reasons,
  });

  final String label;
  final String packageName;
  final bool systemApp;
  final String? installer;
  final int riskScore;
  final String riskLevel;
  final bool possibleMalware;
  final String analysisType;
  final List<String> reasons;

  bool get needsReview =>
      riskScore >= 3;

  factory JarvisAppThreat.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    final List<dynamic> reasons =
        raw['reasons'] as List<dynamic>? ??
            const <dynamic>[];

    return JarvisAppThreat(
      label:
          raw['label']?.toString() ??
              raw['packageName']
                  ?.toString() ??
              'App',
      packageName:
          raw['packageName']
                  ?.toString() ??
              '',
      systemApp:
          raw['systemApp'] == true,
      installer:
          raw['installer']?.toString(),
      riskScore:
          (raw['riskScore'] as num?)
                  ?.toInt() ??
              0,
      riskLevel:
          raw['riskLevel']?.toString() ??
              'low',
      possibleMalware:
          raw['possibleMalware'] == true,
      analysisType:
          raw['analysisType']
                  ?.toString() ??
              'local_heuristic',
      reasons: reasons
          .map(
            (dynamic item) =>
                item.toString(),
          )
          .toList(growable: false),
    );
  }
}

class JarvisDeviceDiagnosis {
  const JarvisDeviceDiagnosis({
    required this.raw,
    required this.issues,
  });

  final Map<String, dynamic> raw;
  final List<JarvisDeviceIssue> issues;

  bool get healthy => issues.isEmpty;
}

class JarvisRepairResult {
  const JarvisRepairResult({
    required this.ok,
    required this.target,
    required this.action,
    required this.requiresUserAction,
    required this.message,
  });

  final bool ok;
  final String target;
  final String action;
  final bool requiresUserAction;
  final String message;

  factory JarvisRepairResult.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisRepairResult(
      ok: raw['ok'] == true,
      target: raw['target']?.toString() ?? '',
      action: raw['action']?.toString() ?? '',
      requiresUserAction:
          raw['requiresUserAction'] == true,
      message:
          raw['message']?.toString() ??
              'Repair action completed.',
    );
  }
}

class JarvisDeviceRepairService {
  const JarvisDeviceRepairService();

  static const MethodChannel _channel =
      MethodChannel(
    'jarvis.device_repair',
  );

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform ==
          TargetPlatform.android;

  Future<JarvisDeviceDiagnosis>
      diagnose() async {
    if (!isSupported) {
      return const JarvisDeviceDiagnosis(
        raw: <String, dynamic>{},
        issues: <JarvisDeviceIssue>[],
      );
    }

    try {
      final Map<dynamic, dynamic>? raw =
          await _channel.invokeMethod<
              Map<dynamic, dynamic>>(
        'diagnose',
      );

      final Map<String, dynamic> data =
          <String, dynamic>{};

      raw?.forEach(
        (dynamic key, dynamic value) {
          data[key.toString()] = value;
        },
      );

      final List<dynamic> issues =
          data['issues'] as List<dynamic>? ??
              const <dynamic>[];

      return JarvisDeviceDiagnosis(
        raw: data,
        issues: issues
            .whereType<Map>()
            .map(
              (Map item) =>
                  JarvisDeviceIssue
                      .fromMap(item),
            )
            .toList(growable: false),
      );
    } on PlatformException catch (error) {
      throw StateError(
        'Android device diagnosis is unavailable: ${error.message ?? error.code}',
      );
    }
  }

  Future<List<JarvisAppThreat>>
      scanApps() async {
    if (!isSupported) {
      return const <JarvisAppThreat>[];
    }

    try {
      final List<dynamic>? raw =
          await _channel.invokeMethod<
              List<dynamic>>(
        'scanApps',
      );

      if (raw == null) {
        return const <JarvisAppThreat>[];
      }

      return raw
          .whereType<Map>()
          .map(
            (Map item) =>
                JarvisAppThreat
                    .fromMap(item),
          )
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw StateError(
        'Android security scan is unavailable: ${error.message ?? error.code}',
      );
    }
  }

  Future<bool> clearJarvisCache() async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'clearJarvisCache',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<JarvisRepairResult> repairIssue(
    String target,
  ) async {
    if (!isSupported) {
      return JarvisRepairResult(
        ok: false,
        target: target,
        action: 'unsupported',
        requiresUserAction: false,
        message:
            'Device repair is available on Android.',
      );
    }

    try {
      final Map<dynamic, dynamic>? raw =
          await _channel.invokeMethod<
              Map<dynamic, dynamic>>(
        'repairIssue',
        <String, Object?>{
          'target': target,
        },
      );

      return JarvisRepairResult.fromMap(
        raw ?? const <dynamic, dynamic>{},
      );
    } on PlatformException catch (error) {
      return JarvisRepairResult(
        ok: false,
        target: target,
        action: 'platform_error',
        requiresUserAction: false,
        message:
            'Repair action failed: ${error.message ?? error.code}',
      );
    }
  }

  Future<bool> openRepairSettings(
    String target,
  ) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'openRepairSettings',
            <String, Object?>{
              'target': target,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openAppDetails(
    String packageName,
  ) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'openAppDetails',
            <String, Object?>{
              'packageName': packageName,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestUninstall(
    String packageName,
  ) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'requestUninstall',
            <String, Object?>{
              'packageName': packageName,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool?> isPackageInstalled(
    String packageName,
  ) async {
    if (!isSupported) {
      return null;
    }

    try {
      return await _channel.invokeMethod<bool>(
        'isPackageInstalled',
        <String, Object?>{
          'packageName': packageName,
        },
      );
    } on PlatformException {
      return null;
    }
  }
}
