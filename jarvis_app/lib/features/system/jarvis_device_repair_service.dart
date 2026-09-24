import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JarvisDeviceRepairService {
  const JarvisDeviceRepairService();

  static const MethodChannel _channel =
      MethodChannel('jarvis.device_repair');

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform ==
          TargetPlatform.android;

  Future<Map<String, dynamic>> diagnose() async {
    if (!isSupported) {
      return <String, dynamic>{
        'supported': false,
        'issues': <dynamic>[],
      };
    }

    try {
      final Map<dynamic, dynamic>? raw =
          await _channel.invokeMethod<
              Map<dynamic, dynamic>>(
        'diagnose',
      );

      return raw == null
          ? <String, dynamic>{}
          : _stringKeyMap(raw);
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'error':
            error.message ?? error.code,
        'issues': <dynamic>[],
      };
    } on MissingPluginException {
      return <String, dynamic>{
        'error':
            'Android repair bridge is unavailable.',
        'issues': <dynamic>[],
      };
    }
  }

  Future<List<Map<String, dynamic>>>
      scanApps() async {
    if (!isSupported) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic>? raw =
          await _channel.invokeMethod<
              List<dynamic>>(
        'scanApps',
      );

      if (raw == null) {
        return const <Map<String, dynamic>>[];
      }

      return raw
          .whereType<Map>()
          .map(
            (Map item) =>
                _stringKeyMap(item),
          )
          .toList(growable: false);
    } on PlatformException {
      return const <Map<String, dynamic>>[];
    } on MissingPluginException {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>>
      malwareSummary() async {
    final List<Map<String, dynamic>> apps =
        await scanApps();

    final List<Map<String, dynamic>> high =
        apps
            .where(
              (Map<String, dynamic> app) =>
                  app['riskLevel'] ==
                      'high',
            )
            .toList(growable: false);

    final List<Map<String, dynamic>>
        possibleMalware =
        apps
            .where(
              (Map<String, dynamic> app) =>
                  app['possibleMalware'] ==
                      true,
            )
            .toList(growable: false);

    final List<Map<String, dynamic>> medium =
        apps
            .where(
              (Map<String, dynamic> app) =>
                  app['riskLevel'] ==
                      'medium',
            )
            .toList(growable: false);

    return <String, dynamic>{
      'scanned_apps': apps.length,
      'high_risk_count': high.length,
      'medium_risk_count': medium.length,
      'possible_malware_count':
          possibleMalware.length,
      'possible_malware':
          possibleMalware,
      'high_risk_apps': high,
      'analysis_type':
          'local_heuristic',
      'note':
          'JARVIS reports suspicious behavior signals, not a guaranteed malware verdict. Removal requires Android confirmation.',
    };
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
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openRepairSettings(
    String target,
  ) async {
    if (!isSupported) {
      return false;
    }

    final String normalized =
        target.trim();

    if (normalized.isEmpty) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'openRepairSettings',
            <String, Object?>{
              'target': normalized,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> openAppDetails(
    String packageName,
  ) async {
    final String normalized =
        packageName.trim();

    if (!isSupported ||
        normalized.isEmpty) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'openAppDetails',
            <String, Object?>{
              'packageName': normalized,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestUninstall(
    String packageName,
  ) async {
    final String normalized =
        packageName.trim();

    if (!isSupported ||
        normalized.isEmpty) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'requestUninstall',
            <String, Object?>{
              'packageName': normalized,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isPackageInstalled(
    String packageName,
  ) async {
    final String normalized =
        packageName.trim();

    if (!isSupported ||
        normalized.isEmpty) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'isPackageInstalled',
            <String, Object?>{
              'packageName': normalized,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Map<String, dynamic>>
      repairTarget(
    String target,
  ) async {
    final String normalized =
        target.trim().toLowerCase();

    if (normalized ==
            'jarvis_cache' ||
        normalized == 'cache') {
      final bool cleared =
          await clearJarvisCache();

      return <String, dynamic>{
        'ok': cleared,
        'target': 'jarvis_cache',
        'action':
            'clear_jarvis_cache',
        'requires_user_action':
            false,
      };
    }

    final Set<String> settingsTargets =
        <String>{
      'storage',
      'internet',
      'bluetooth',
      'battery',
      'apps',
      'security',
      'settings',
    };

    if (!settingsTargets
        .contains(normalized)) {
      return <String, dynamic>{
        'ok': false,
        'target': normalized,
        'error':
            'Unsupported device repair target.',
      };
    }

    final bool opened =
        await openRepairSettings(
      normalized,
    );

    return <String, dynamic>{
      'ok': opened,
      'target': normalized,
      'action':
          'open_android_repair_settings',
      'requires_user_action':
          true,
    };
  }

  static Map<String, dynamic>
      _stringKeyMap(
    Map<dynamic, dynamic> raw,
  ) {
    final Map<String, dynamic> result =
        <String, dynamic>{};

    raw.forEach(
      (dynamic key, dynamic value) {
        result[key.toString()] =
            _normalize(value);
      },
    );

    return result;
  }

  static dynamic _normalize(
    dynamic value,
  ) {
    if (value is Map) {
      return _stringKeyMap(value);
    }

    if (value is List) {
      return value
          .map(_normalize)
          .toList(growable: false);
    }

    return value;
  }
}
