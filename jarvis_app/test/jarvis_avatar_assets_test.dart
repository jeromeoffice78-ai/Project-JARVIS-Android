import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/presence/jarvis_avatar_asset_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('avatar page loads from private localhost and uses offline assets',
      () async {
    final Uri page = await JarvisAvatarAssetServer.avatarPage();
    expect(page.scheme, 'http');
    expect(page.host, '127.0.0.1');
    expect(page.path, '/assets/avatar/jarvis_human_avatar.html');
    final String html = await rootBundle
        .loadString('assets/avatar/jarvis_human_avatar.html');
    expect(html, contains('three.module.js'));
    expect(html, contains('buildSimplified3DHuman'));
    expect(html, contains('__jarvisAvatarBackup'));
    expect(html, contains('jarvisSetState'));

    // A raw loopback socket is intentionally used: flutter_test overrides
    // HttpClient and can return artificial 400s unrelated to this asset server.
    final Socket socket =
        await Socket.connect(InternetAddress.loopbackIPv4, page.port);
    try {
      socket.write(
        'GET ${page.path} HTTP/1.1\r\n'
        'Host: 127.0.0.1:${page.port}\r\n'
        'Connection: close\r\n\r\n',
      );
      await socket.flush();
      final String response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      expect(response, startsWith('HTTP/1.1 200'));
      expect(response.toLowerCase(), contains('content-type: text/html'));
      expect(response, contains('Loading human JARVIS'));
    } finally {
      socket.destroy();
      await JarvisAvatarAssetServer.closeForTesting();
    }
  });

  test('avatar model and JavaScript module assets are present in bundle',
      () async {
    for (final String name in <String>[
      'assets/vendor/three/three.module.js',
      'assets/vendor/three/addons/loaders/GLTFLoader.js',
      'assets/vendor/three/addons/utils/BufferGeometryUtils.js',
      'assets/models/vitruvian_body.glb',
      'assets/models/vitruvian_head.glb',
      'assets/models/hairtool_cards.glb',
    ]) {
      final ByteData data = await rootBundle.load(name);
      expect(data.lengthInBytes, greaterThan(100), reason: name);
    }
  });
}
