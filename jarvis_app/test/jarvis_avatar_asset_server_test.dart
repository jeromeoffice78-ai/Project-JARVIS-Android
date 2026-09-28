import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/presence/jarvis_avatar_asset_server.dart';

Future<String> rawLocalRequest(Uri page, String method, String path) async {
  // Flutter test overrides HttpClient and manufactures HTTP 400 responses.
  // Raw loopback sockets exercise the actual private in-app asset server.
  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4, page.port,
  );
  try {
    socket.write(
      '$method $path HTTP/1.1\r\n'
      'Host: 127.0.0.1:${page.port}\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    return await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
  } finally {
    socket.destroy();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(JarvisAvatarAssetServer.closeForTesting);

  test('bundled human avatar is served on a same-origin localhost URL',
      () async {
    final Uri page = await JarvisAvatarAssetServer.avatarPage();

    expect(page.scheme, 'http');
    expect(page.host, '127.0.0.1');
    expect(page.path, '/assets/avatar/jarvis_human_avatar.html');

    final String success = await rawLocalRequest(page, 'GET', page.path);
    expect(success, startsWith('HTTP/1.1 200'));
    expect(success.toLowerCase(), contains('content-type: text/html'));
    expect(success, contains("import * as THREE from 'three'"));

    final String blocked = await rawLocalRequest(
      page, 'GET', '/assets/private-owner-token.txt',
    );
    expect(blocked, startsWith('HTTP/1.1 404'));

    final String denied = await rawLocalRequest(page, 'POST', page.path);
    expect(denied, startsWith('HTTP/1.1 405'));
  });
}
