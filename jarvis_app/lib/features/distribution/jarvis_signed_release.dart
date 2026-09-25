import 'dart:convert';

import 'package:http/http.dart' as http;

/// Only verified production-signed JARVIS AI Assistant GitHub releases
/// are eligible for cross-device installation. Debug builds are excluded.
class JarvisSignedRelease {
  const JarvisSignedRelease({
    required this.tag,
    required this.apkUrl,
    required this.releaseUrl,
    required this.publishedAt,
  });

  static const String _repo =
      'jeromeoffice78-ai/Project-JARVIS-Android';
  static const String _assetName =
      'JARVIS-AI-ASSISTANT-FINAL-ARM64.apk';
  static const String _tagPrefix =
      'jarvis-ai-assistant-signed-';

  static const String _verifiedTag =
      'jarvis-ai-assistant-signed-v1.3.0-build-79';

  /// A production-signed APK confirmed in the repository's signed release.
  /// The live releases feed replaces this when a newer signed build exists.
  static JarvisSignedRelease get verifiedFallback =>
      JarvisSignedRelease(
        tag: _verifiedTag,
        apkUrl:
            'https://github.com/$_repo/releases/download/$_verifiedTag/$_assetName',
        releaseUrl:
            'https://github.com/$_repo/releases/tag/$_verifiedTag',
        publishedAt:
            DateTime.utc(2026, 9, 25, 16, 36),
      );

  final String tag;
  final String apkUrl;
  final String releaseUrl;
  final DateTime publishedAt;

  static JarvisSignedRelease? fromGitHub(
    Map<String, dynamic> release,
  ) {
    final String tag =
        release['tag_name']?.toString() ?? '';
    if (!tag.startsWith(_tagPrefix) ||
        !RegExp(r'^[a-zA-Z0-9._-]+$')
            .hasMatch(tag) ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      return null;
    }

    final DateTime? published = DateTime.tryParse(
      release['published_at']?.toString() ?? '',
    );
    if (published == null) return null;

    final String assetPath =
        '/$_repo/releases/download/$tag/$_assetName';
    final Object? assets = release['assets'];
    if (assets is! List) return null;

    for (final Object? raw in assets) {
      if (raw is! Map) continue;
      if (raw['name'] != _assetName ||
          (raw['size'] is num &&
              (raw['size'] as num) < 20000000)) {
        continue;
      }
      final Uri? uri = Uri.tryParse(
        raw['browser_download_url']?.toString() ??
            '',
      );
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.path != assetPath) {
        continue;
      }
      return JarvisSignedRelease(
        tag: tag,
        apkUrl: uri.toString(),
        releaseUrl:
            'https://github.com/$_repo/releases/tag/$tag',
        publishedAt: published,
      );
    }
    return null;
  }

  static JarvisSignedRelease selectLatest(
    List<dynamic> releases,
  ) {
    final List<JarvisSignedRelease> signed =
        releases
            .whereType<Map>()
            .map(
              (Map entry) => fromGitHub(
                Map<String, dynamic>.from(entry),
              ),
            )
            .whereType<JarvisSignedRelease>()
            .toList();

    if (signed.isEmpty) {
      return verifiedFallback;
    }

    signed.sort(
      (JarvisSignedRelease a,
              JarvisSignedRelease b) =>
          b.publishedAt.compareTo(a.publishedAt),
    );

    return signed.first.publishedAt.isAfter(
      verifiedFallback.publishedAt,
    )
        ? signed.first
        : verifiedFallback;
  }
}

class JarvisSignedReleaseService {
  JarvisSignedReleaseService({
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<JarvisSignedRelease> latest() async {
    try {
      final http.Response response =
          await _client
              .get(
                Uri.https(
                  'api.github.com',
                  '/repos/jeromeoffice78-ai/Project-JARVIS-Android/releases',
                  const <String, String>{
                    'per_page': '100',
                  },
                ),
                headers: const <String, String>{
                  'accept':
                      'application/vnd.github+json',
                },
              )
              .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return JarvisSignedRelease.verifiedFallback;
      }

      final Object? decoded =
          jsonDecode(response.body);
      if (decoded is! List) {
        return JarvisSignedRelease.verifiedFallback;
      }

      return JarvisSignedRelease.selectLatest(
        decoded,
      );
    } on Object {
      return JarvisSignedRelease.verifiedFallback;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
