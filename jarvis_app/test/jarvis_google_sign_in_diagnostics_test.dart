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

  test('shows stable production identity, never a debug signing key', () {
    expect(JarvisGoogleSignInDiagnostics.googleCloudFields, contains('com.jarvis.project_jarvis'));
    expect(
      JarvisGoogleSignInDiagnostics.googleCloudFields,
      contains('39:96:F2:AD:FB:2E:E3:34:97:D7:64:C2:29:44:A8:C8:78:4F:C6:4E'),
    );
  });
}
