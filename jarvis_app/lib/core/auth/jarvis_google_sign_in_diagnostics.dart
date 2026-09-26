import 'package:flutter/services.dart';

/// Safe, shareable diagnostics for Google Sign-In on production Android.
/// Never include identity tokens, backend bearer tokens, emails or exception
/// details verbatim in a user-visible diagnostic.
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

  static String? googleApiStatus(Object error) {
    if (error is! PlatformException) return null;
    final String message = error.message ?? '';
    final RegExpMatch? explicit = RegExp(
      r'(?:ApiException|status(?:Code)?)\s*[:=]\s*(\d{1,5})\b',
      caseSensitive: false,
    ).firstMatch(message);
    if (explicit != null) return explicit.group(1);

    // Some Android Play Services builds obfuscate ApiException as "ra.b: 10:".
    final RegExpMatch? obfuscated = RegExp(
      r'\b[A-Za-z][A-Za-z0-9_.]*:\s*(\d{1,5}):',
    ).firstMatch(message);
    return obfuscated?.group(1);
  }

  static bool isOAuthConfigurationError(Object error) {
    if (error is! PlatformException) return false;
    return googleApiStatus(error) == '10' ||
        (error.message ?? '').contains('DEVELOPER_ERROR');
  }

  /// Return only stage, stable platform error code and numeric Google status.
  /// An Android exception message may contain private account information,
  /// so it must never be copied verbatim.
  static String diagnosticSummary(
    Object error, {
    String stage = 'google_account_picker',
  }) {
    final String safeStage =
        stage.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (error is PlatformException) {
      final String safeCode = error.code
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final String status = googleApiStatus(error) ?? 'not reported';
      return 'Stage: $safeStage\n'
          'Android error code: $safeCode\n'
          'Google API status: $status';
    }
    // Exception type is enough to distinguish a local or transport failure
    // without inadvertently copying sensitive error descriptions.
    return 'Stage: $safeStage\n'
        'Error type: ${error.runtimeType}';
  }

  /// Whitelist only stable native result fields. Do not copy the native
  /// map verbatim because it may contain a live Google identity token.
  static String nativeResultDiagnostic(
    Map<dynamic, dynamic>? result, {
    String stage = 'native_google_web_client',
  }) {
    final String safeStage =
        stage.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final String rawResult = result?['status']?.toString() ?? 'no_result';
    const allowedResults = <String>{
      'ok',
      'no_id_token',
      'google_error',
      'native_unavailable',
      'android_only_ok',
    };
    final String safeResult =
        allowedResults.contains(rawResult) ? rawResult : 'unknown';
    final String rawCode = result?['googleStatus']?.toString() ?? '';
    final String safeCode = RegExp(r'^\d{1,5}
    if (isOAuthConfigurationError(error)) {
      return 'Google configuration error (10). Google Sign-In is blocked '
          'before it reaches JARVIS. Use SECURE EMAIL SIGN-IN below to '
          'activate your full account, or copy diagnostics for Google setup.';
    }
    if (error is PlatformException) {
      if (error.code == 'sign_in_canceled') {
        return 'Google sign-in was canceled. Tap Continue with Google '
            'when you are ready to choose an account.';
      }
      if (error.code == 'network_error' || googleApiStatus(error) == '7') {
        return 'Google reported a network error. Verify that the phone '
            'can reach Google Play services and retry.';
      }
      if (error.code == 'sign_in_required') {
        return 'Google requires an account on this phone. Add your '
            'approved account under Android Settings, then retry.';
      }
      return 'Android Google Sign-In failed before JARVIS could '
          'finish authentication. Copy the diagnostic code below '
          'to identify the cause.';
    }
    return 'Google sign-in did not complete. Copy the diagnostic code '
        'below to distinguish a device, token or network error.';
  }
}
).hasMatch(rawCode)
        ? rawCode
        : 'not reported';
    return 'Stage: $safeStage\n'
        'Result: $safeResult\n'
        'Google API status: $safeCode';
  }

  static String messageFor(Object error) {
    if (isOAuthConfigurationError(error)) {
      return 'Google configuration error (10). Google Sign-In is blocked '
          'before it reaches JARVIS. Use SECURE EMAIL SIGN-IN below to '
          'activate your full account, or copy diagnostics for Google setup.';
    }
    if (error is PlatformException) {
      if (error.code == 'sign_in_canceled') {
        return 'Google sign-in was canceled. Tap Continue with Google '
            'when you are ready to choose an account.';
      }
      if (error.code == 'network_error' || googleApiStatus(error) == '7') {
        return 'Google reported a network error. Verify that the phone '
            'can reach Google Play services and retry.';
      }
      if (error.code == 'sign_in_required') {
        return 'Google requires an account on this phone. Add your '
            'approved account under Android Settings, then retry.';
      }
      return 'Android Google Sign-In failed before JARVIS could '
          'finish authentication. Copy the diagnostic code below '
          'to identify the cause.';
    }
    return 'Google sign-in did not complete. Copy the diagnostic code '
        'below to distinguish a device, token or network error.';
  }
}
