import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/core/auth/jarvis_google_sign_in_diagnostics.dart';

void main() {
  test('Google Play services ApiException 10 is an OAuth setup error', () {
    final error = PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10: ',
    );
    expect(JarvisGoogleSignInDiagnostics.isOAuthConfigurationError(error), isTrue);
    expect(JarvisGoogleSignInDiagnostics.messageFor(error), contains('configuration error (10)'));
  });

  test('does not misdiagnose a canceled or unrelated Google sign-in', () {
    expect(
      JarvisGoogleSignInDiagnostics.isOAuthConfigurationError(
        PlatformException(code: 'sign_in_canceled', message: 'Canceled'),
      ),
      isFalse,
    );
    expect(JarvisGoogleSignInDiagnostics.isOAuthConfigurationError(StateError('offline')), isFalse);
  });

  test('reports Android error code safely for a non-OAuth failure', () {
    final error = PlatformException(
      code: 'sign_in_failed',
      message: 'Unhandled Play Services failure for private@example.com',
    );
    final summary = JarvisGoogleSignInDiagnostics.diagnosticSummary(error);
    expect(summary, contains('Android error code: sign_in_failed'));
    expect(summary, contains('Google API status: not reported'));
    expect(summary, isNot(contains('private@example.com')));
  });

  test('recognizes obfuscated Play Services status 10', () {
    final error = PlatformException(
      code: 'sign_in_failed',
      message: 'ra.b: 10: ',
    );
    expect(JarvisGoogleSignInDiagnostics.isOAuthConfigurationError(error), isTrue);
    expect(
      JarvisGoogleSignInDiagnostics.diagnosticSummary(error),
      contains('Google API status: 10'),
    );
  });

  test('distinguishes network status 7 without classifying it as OAuth setup', () {
    final error = PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 7: ',
    );
    expect(JarvisGoogleSignInDiagnostics.isOAuthConfigurationError(error), isFalse);
    expect(JarvisGoogleSignInDiagnostics.messageFor(error), contains('network error'));
    expect(
      JarvisGoogleSignInDiagnostics.diagnosticSummary(error, stage: 'google_id_token'),
      contains('Stage: google_id_token'),
    );
  });

  test('shows stable production identity, never a debug signing key', () {
    expect(JarvisGoogleSignInDiagnostics.googleCloudFields, contains('com.jarvis.project_jarvis'));
    expect(
      JarvisGoogleSignInDiagnostics.googleCloudFields,
      contains('39:96:F2:AD:FB:2E:E3:34:97:D7:64:C2:29:44:A8:C8:78:4F:C6:4E'),
    );
  });
  test('native Google result reports only approved diagnostic fields', () {
    final summary = JarvisGoogleSignInDiagnostics.nativeResultDiagnostic(
      <String, Object>{
        'status': 'google_error',
        'googleStatus': 10,
        'idToken': 'SECRET_GOOGLE_ID_TOKEN_NEVER_COPY',
        'email': 'private@example.com',
      },
    );
    expect(summary, contains('Stage: native_google_web_client'));
    expect(summary, contains('Result: google_error'));
    expect(summary, contains('Google API status: 10'));
    expect(summary, isNot(contains('SECRET_GOOGLE_ID_TOKEN_NEVER_COPY')));
    expect(summary, isNot(contains('private@example.com')));
  });

  test('Android-only result is distinguishable from Web-client errors', () {
    final summary = JarvisGoogleSignInDiagnostics.nativeResultDiagnostic(
      <String, Object>{'status': 'android_only_ok'},
      stage: 'android_only_google_probe',
    );
    expect(summary, contains('Stage: android_only_google_probe'));
    expect(summary, contains('Result: android_only_ok'));
    expect(summary, contains('Google API status: not reported'));
  });

}
