import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves only bundled avatar files on the device's IPv4 loopback interface.
///
/// Android WebView treats file:// ES modules and GLB fetches as opaque,
/// potentially cross-origin resources. A single localhost HTTP origin lets
/// Three.js import its modules, textures, and glTF files without Internet
/// access or unsafe universal access to device files.
final class JarvisAvatarAssetServer {
  JarvisAvatarAssetServer._();

  static Future<Uri>? _starting;
  static HttpServer? _server;

  static const Set<String> _bundledAssets = <String>{
    'assets/avatar/jarvis_human_avatar.html',
    'assets/vendor/three/three.module.js',
    'assets/vendor/three/addons/loaders/GLTFLoader.js',
    'assets/vendor/three/addons/utils/BufferGeometryUtils.js',
    'assets/models/vitruvian_body.glb',
    'assets/models/vitruvian_head.glb',
    'assets/models/hairtool_cards.glb',
    'assets/models/vit_face_bc.png',
    'assets/models/vit_mouth.png',
    'assets/models/vit_sclera.png',
    'assets/models/vit_iris.png',
    'assets/models/vit_hair_atlas.png',
    'assets/models/vit_hair_opacity.png',
  };

  static const String _entry = 'assets/avatar/jarvis_human_avatar.html';

  /// The server binds to 127.0.0.1, never a publicly reachable interface.
  /// This same URL also works for the user-enabled Android floating overlay.
  static Future<Uri> avatarPage() {
    final Future<Uri>? pending = _starting;
    if (pending != null) return pending;
    final Future<Uri> started = _start();
    _starting = started;
    return started;
  }

  static Future<Uri> _start() async {
    try {
      // Verify that the asset actually exists before claiming the
      // server is available.
      await rootBundle.load(_entry);
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_serve);
      return Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/$_entry',
      );
    } on Object {
      _starting = null;
      rethrow;
    }
  }

  @visibleForTesting
  static Future<void> closeForTesting() async {
    final HttpServer? server = _server;
    _server = null;
    _starting = null;
    await server?.close(force: true);
  }

  static Future<void> _serve(HttpRequest request) async {
    final HttpResponse response = request.response;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Cache-Control', 'private, max-age=3600');
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    // No path traversal, arbitrary asset reads, or public network listener.
    final String key = request.uri.pathSegments.join('/');
    if (!_bundledAssets.contains(key)) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    try {
      final ByteData data = await rootBundle.load(key);
      if (key.endsWith('.html')) {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
      } else if (key.endsWith('.js')) {
        response.headers.contentType =
            ContentType('text', 'javascript', charset: 'utf-8');
      } else if (key.endsWith('.png')) {
        response.headers.contentType = ContentType('image', 'png');
      } else if (key.endsWith('.glb')) {
        response.headers.contentType = ContentType('model', 'gltf-binary');
      }
      response.contentLength = data.lengthInBytes;
      if (request.method == 'GET') {
        response.add(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
      }
    } on FlutterError {
      response.statusCode = HttpStatus.notFound;
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }
}
