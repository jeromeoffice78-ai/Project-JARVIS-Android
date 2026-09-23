import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JarvisBondedBluetoothDevice {
  const JarvisBondedBluetoothDevice({
    required this.name,
    required this.address,
    required this.type,
    required this.bondState,
  });

  final String name;
  final String address;
  final int type;
  final int bondState;

  factory JarvisBondedBluetoothDevice.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisBondedBluetoothDevice(
      name: raw['name']?.toString() ??
          'Bluetooth device',
      address:
          raw['address']?.toString() ?? '',
      type: (raw['type'] as num?)?.toInt() ?? 0,
      bondState:
          (raw['bondState'] as num?)?.toInt() ?? 0,
    );
  }
}

class JarvisSystemControlService {
  static const MethodChannel _channel =
      MethodChannel('jarvis.system_control');

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform ==
          TargetPlatform.android;

  Future<bool> isAccessibilityEnabled() async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'isAccessibilityEnabled',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!isSupported) {
      return;
    }

    await _channel.invokeMethod<void>(
      'openAccessibilitySettings',
    );
  }

  Future<bool> performGlobalAction(
    String action,
  ) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'globalAction',
            <String, dynamic>{
              'action': action,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> tap({
    required double x,
    required double y,
  }) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'tap',
            <String, dynamic>{
              'x': x,
              'y': y,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> swipe({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    int durationMs = 350,
  }) async {
    if (!isSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'swipe',
            <String, dynamic>{
              'startX': startX,
              'startY': startY,
              'endX': endX,
              'endY': endY,
              'durationMs': durationMs,
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<String> captureScreenshot() async {
    if (!isSupported) {
      throw StateError(
        'Screen capture is only available on Android.',
      );
    }

    final String? encoded =
        await _channel.invokeMethod<String>(
      'captureScreenshot',
    );

    if (encoded == null || encoded.isEmpty) {
      throw StateError(
        'Android returned no screenshot.',
      );
    }

    return encoded;
  }

  Future<List<JarvisBondedBluetoothDevice>>
      listBondedBluetoothDevices() async {
    if (!isSupported) {
      return const <
          JarvisBondedBluetoothDevice>[];
    }

    try {
      final List<dynamic>? raw =
          await _channel.invokeMethod<
              List<dynamic>>(
        'listBondedBluetoothDevices',
      );

      if (raw == null) {
        return const <
            JarvisBondedBluetoothDevice>[];
      }

      return raw
          .whereType<Map>()
          .map(
            (Map item) =>
                JarvisBondedBluetoothDevice
                    .fromMap(item),
          )
          .toList(growable: false);
    } on PlatformException {
      return const <
          JarvisBondedBluetoothDevice>[];
    }
  }

  Future<void> openBluetoothSettings() async {
    if (!isSupported) {
      return;
    }

    await _channel.invokeMethod<void>(
      'openBluetoothSettings',
    );
  }
}
