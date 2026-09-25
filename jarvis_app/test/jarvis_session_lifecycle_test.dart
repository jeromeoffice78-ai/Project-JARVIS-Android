import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/core/auth/jarvis_chairman_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud clients receive sign-in and sign-out notifications', () async {
    final int firstRevision = JarvisAuthSession.sessionRevision.value;
    final List<int> received = <int>[];
    void listener() {
      received.add(JarvisAuthSession.sessionRevision.value);
    }

    JarvisAuthSession.sessionRevision.addListener(listener);
    try {
      await JarvisAuthSession.save(
        token: 'test-session-token',
        expiresAt: '2099-01-01T00:00:00Z',
        email: 'test@example.com',
      );
      expect(JarvisAuthSession.currentToken, 'test-session-token');
      expect(
        JarvisAuthSession.sessionRevision.value,
        firstRevision + 1,
      );

      await JarvisAuthSession.clear();
      expect(JarvisAuthSession.currentToken, isEmpty);
      expect(
        JarvisAuthSession.sessionRevision.value,
        firstRevision + 2,
      );
      expect(received, <int>[firstRevision + 1, firstRevision + 2]);
    } finally {
      JarvisAuthSession.sessionRevision.removeListener(listener);
      await JarvisAuthSession.clear();
    }
  });
}
