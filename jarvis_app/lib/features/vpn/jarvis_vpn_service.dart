import 'package:flutter/services.dart';

final class JarvisVpnStatus {
  const JarvisVpnStatus({
    required this.active,
    required this.validated,
    required this.metered,
    required this.transport,
  });

  final bool active;
  final bool validated;
  final bool metered;
  final String transport;

  factory JarvisVpnStatus.fromMap(Map<Object?, Object?> map) {
    return JarvisVpnStatus(
      active: map['active'] == true,
      validated: map['validated'] == true,
      metered: map['metered'] == true,
      transport: map['transport']?.toString() ?? 'unknown',
    );
  }
}

class JarvisVpnService {
  static const MethodChannel _channel =
      MethodChannel('jarvis.vpn');

  Future<JarvisVpnStatus> getStatus() async {
    final Map<Object?, Object?>? payload =
        await _channel.invokeMapMethod<Object?, Object?>(
      'getStatus',
    );

    return JarvisVpnStatus.fromMap(
      payload ?? const <Object?, Object?>{},
    );
  }

  Future<void> openVpnSettings() async {
    await _channel.invokeMethod<void>('openVpnSettings');
  }

  Future<Map<Object?, Object?>> getPlatformSupport() async {
    return await _channel.invokeMapMethod<Object?, Object?>(
          'getPlatformSupport',
        ) ??
        const <Object?, Object?>{};
  }

  Future<Map<Object?, Object?>> getWarpStatus() async {
    return await _channel.invokeMapMethod<Object?, Object?>(
          'getWarpStatus',
        ) ??
        const <Object?, Object?>{};
  }

  Future<void> openWarp() async {
    await _channel.invokeMethod<void>('openWarp');
  }

  Future<bool> provisionIkev2({
    required String server,
    required String identity,
    required String authentication,
    String username = '',
    String password = '',
    String preSharedKey = '',
  }) async {
    final bool? started = await _channel.invokeMethod<bool>(
      'provisionIkev2',
      <String, Object>{
        'server': server.trim(),
        'identity': identity.trim(),
        'authentication': authentication,
        'username': username,
        'password': password,
        'preSharedKey': preSharedKey,
      },
    );
    return started == true;
  }

  Future<void> startProvisionedVpn() async {
    await _channel.invokeMethod<void>('startProvisionedVpn');
  }

  Future<void> stopProvisionedVpn() async {
    await _channel.invokeMethod<void>('stopProvisionedVpn');
  }

  Future<void> deleteProvisionedVpn() async {
    await _channel.invokeMethod<void>('deleteProvisionedVpn');
  }
}
