import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/devices/jarvis_cloud_device_network.dart';

void main() {
  test('cloud devices preserve online presence and active avatar fields', () {
    final JarvisCloudDevice device = JarvisCloudDevice.fromJson(<String, dynamic>{
      'device_id': 'tablet-1',
      'device_name': 'Tablet',
      'online': true,
      'foreground': true,
      'active_avatar': true,
      'capabilities': <String, dynamic>{'speak_text': true},
      'last_seen_at': '2026-10-18T01:00:00Z',
    });
    final JarvisCloudDeviceState state =
        const JarvisCloudDeviceState.initial().copyWith(
      devices: <JarvisCloudDevice>[device],
    );

    expect(state.onlineCount, 1);
    expect(state.devices.single.deviceId, 'tablet-1');
    expect(state.devices.single.activeAvatar, isTrue);
    expect(state.devices.single.capabilities['speak_text'], isTrue);
  });

  test('cloud command timeout does not report a pending action as completed', () {
    final JarvisCloudCommandResult pending =
        JarvisCloudCommandResult.fromJson(<String, dynamic>{
      'id': 'command-1',
      'status': 'pending',
    });
    final JarvisCloudCommandResult timedOut = pending.withTimedOut();

    expect(timedOut.commandId, 'command-1');
    expect(timedOut.timedOut, isTrue);
    expect(timedOut.isTerminal, isFalse);
    expect(timedOut.completed, isFalse);
  });

  test('failed remote action remains terminal and exposes its error', () {
    final JarvisCloudCommandResult failed =
        JarvisCloudCommandResult.fromJson(<String, dynamic>{
      'id': 'command-2',
      'status': 'failed',
      'error': 'device offline',
    });

    expect(failed.isTerminal, isTrue);
    expect(failed.completed, isFalse);
    expect(failed.error, 'device offline');
  });
}
