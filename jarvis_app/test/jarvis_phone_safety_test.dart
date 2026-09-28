import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/phone/jarvis_phone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('jarvis.phone');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('never enables silent cellular answering without voice bridge', () async {
    int enableCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'hasCellularVoiceBridge') return false;
      if (call.method == 'setAutoAnswer') {
        enableCalls++;
        return true;
      }
      return null;
    });
    final JarvisPhoneService phone = JarvisPhoneService();
    expect(await phone.hasCellularVoiceBridge(), isFalse);
    await expectLater(phone.setAutoAnswer(true), throwsStateError);
    expect(enableCalls, 0);
  });

  test('permits disabling any old auto-answer preference', () async {
    bool? requested;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'hasCellularVoiceBridge') return false;
      if (call.method == 'setAutoAnswer') {
        requested = (call.arguments as Map)['enabled'] as bool?;
        return true;
      }
      return null;
    });
    await JarvisPhoneService().setAutoAnswer(false);
    expect(requested, isFalse);
  });
}
