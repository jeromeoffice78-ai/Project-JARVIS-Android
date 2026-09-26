import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/presence/jarvis_avatar_asset_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(JarvisAvatarAssetServer.closeForTesting);

  test('bundled human avatar is served on a same-origin localhost URL',
      () async {
    final Uri page = await JarvisAvatarAssetServer.avatarPage();

    expect(page.scheme, 'http');
    expect(page.host, '127.0.0.1');
    expect(page.path, '/assets/avatar/jarvis_human_avatar.html');

    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(page)).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      final String html = await response.transform(utf8.decoder).join();
      expect(html, contains("import * as THREE from 'three'"));

      // Do not expose arbitrary application files from the local server.
      final HttpClientResponse blocked = await (await client
          .getUrl(page.resolve('/assets/private-owner-token.txt'))).close();
      expect(blocked.statusCode, HttpStatus.notFound);

      final HttpClientRequest denied = await client.postUrl(page);
      final HttpClientResponse deniedResponse = await denied.close();
      expect(deniedResponse.statusCode, HttpStatus.methodNotAllowed);
    } finally {
      client.close(force: true);
    }
  });
}
