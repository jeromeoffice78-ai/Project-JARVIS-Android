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
}
