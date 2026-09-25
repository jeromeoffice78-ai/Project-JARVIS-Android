import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/features/distribution/jarvis_signed_release.dart';

Map<String, dynamic> signedRelease(
  String tag,
  String date, {
  bool draft = false,
  bool prerelease = false,
  bool includeVerificationFiles = true,
}) {
  const String asset =
      'JARVIS-AI-ASSISTANT-FINAL-ARM64.apk';
  const String base =
      'https://github.com/jeromeoffice78-ai/Project-JARVIS-Android/releases/download/';
  return <String, dynamic>{
    'tag_name': tag,
    'published_at': date,
    'draft': draft,
    'prerelease': prerelease,
    'assets': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': asset,
        'size': 83000000,
        'browser_download_url':
            base + tag + '/' + asset,
      },
      if (includeVerificationFiles) ...<
          Map<String, dynamic>>[
        <String, dynamic>{
          'name': asset + '.sha256',
        },
        <String, dynamic>{
          'name':
              'OAUTH-ANDROID-IDENTITY.txt',
        },
      ],
    ],
  };
}

void main() {
  test(
    'rejects debug and unverified APKs',
    () {
      expect(
        JarvisSignedRelease.fromGitHub(
          signedRelease(
            'jarvis-ai-assistant-v1.3-build-206',
            '2026-09-25T17:00:00Z',
          ),
        ),
        isNull,
      );
      expect(
        JarvisSignedRelease.fromGitHub(
          signedRelease(
            'jarvis-ai-assistant-signed-v1.3.0-build-90',
            '2026-09-25T17:00:00Z',
            includeVerificationFiles: false,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'rejects draft and prerelease releases',
    () {
      const String tag =
          'jarvis-ai-assistant-signed-v1.3.0-build-90';
      expect(
        JarvisSignedRelease.fromGitHub(
          signedRelease(
            tag,
            '2026-09-25T17:00:00Z',
            draft: true,
          ),
        ),
        isNull,
      );
      expect(
        JarvisSignedRelease.fromGitHub(
          signedRelease(
            tag,
            '2026-09-25T17:00:00Z',
            prerelease: true,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'selects the newest verified signed release',
    () {
      final JarvisSignedRelease release =
          JarvisSignedRelease.selectLatest(
        <dynamic>[
          signedRelease(
            'jarvis-ai-assistant-v1.3-build-300',
            '2026-09-25T21:00:00Z',
          ),
          signedRelease(
            'jarvis-ai-assistant-signed-v1.3.0-build-79',
            '2026-09-25T16:36:20Z',
          ),
          signedRelease(
            'jarvis-ai-assistant-signed-v1.3.0-build-100',
            '2026-09-25T19:00:00Z',
          ),
          signedRelease(
            'jarvis-ai-assistant-signed-v1.3.0-build-95',
            '2026-09-25T18:00:00Z',
          ),
        ],
      );
      expect(
        release.tag,
        'jarvis-ai-assistant-signed-v1.3.0-build-100',
      );
      expect(
        release.apkUrl,
        contains(
          '/jarvis-ai-assistant-signed-v1.3.0-build-100/',
        ),
      );
    },
  );

  test(
    'falls back to a known production-signed build',
    () {
      final JarvisSignedRelease release =
          JarvisSignedRelease.selectLatest(
        const <dynamic>[],
      );
      expect(
        release.tag,
        'jarvis-ai-assistant-signed-v1.3.0-build-79',
      );
      expect(
        release.apkUrl,
        endsWith(
          '/JARVIS-AI-ASSISTANT-FINAL-ARM64.apk',
        ),
      );
    },
  );
}
