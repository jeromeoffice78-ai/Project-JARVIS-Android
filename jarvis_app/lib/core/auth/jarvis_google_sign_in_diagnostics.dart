import 'package:flutter/services.dart';

/// Android OAuth details for the permanent production signing identity.
/// These public values are verified by the signed-release workflow.
/// Debug or third-party re-signed APKs have a different fingerprint.
abstract final class JarvisGoogleSignInDiagnostics {
  static const String androidPackage = 'com.jarvis.project_jarvis';
  static const String productionSigningSha1 =
      '39:96:F2:AD:FB:2E:E3:34:97:D7:64:C2:29:44:A8:C8:78:4F:C6:4E';

  static const String googleCloudFields =
      'OAuth client type: Android\n'
      'Package name: $androidPackage\n'
      'SHA-1 certificate fingerprint: $productionSigningSha1\n'
      'Create this Android client in the same Google Cloud project '
      'as the JARVIS web OAuth server client. '
      'Use the production-signed JARVIS APK, not a debug build.';

  static bool isOAuthConfigurationError(Object error) {
    if (error is! PlatformException) return false;
    final String details =
        '${error.code} ${error.message ?? ''} ${error.details ?? ''}';
    return RegExp(
      r'(?:ApiException:\s*10\b|DEVELOPER_ERROR|statusCode\s*[:=]\s*10\b)',
      caseSensitive: false,
    ).hasMatch(details);
  }

  static String messageFor(Object error) {
    if (isOAuthConfigurationError(error)) {
      return 'Google sign-in configuration error (10). '
          'This Android app must have an OAuth Android client registered '
          'for its exact package and signing SHA-1 in the same Google '
          'Cloud project as the JARVIS web client. '
          'Install the production-signed APK and use the buttons below '
          'to copy the required settings and open Google Cloud. '
          'Local features remain available while this is fixed.';
    }
    return 'Google sign-in could not complete. Check your connection '
        'and Google Play services, then try again. '
        'You can still continue with local features.';
  }
}
