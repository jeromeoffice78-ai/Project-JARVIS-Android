import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_jarvis/core/auth/jarvis_chairman_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('owner sign-in is explicit and password-free', () {
    final int revision = JarvisAuthSession.signInRequests.value;
    JarvisAuthSession.requestSignIn();
    expect(JarvisAuthSession.signInRequests.value, revision + 1);
  });

  testWidgets('Jarvis opens locally without a password or sign-in gate',
      (WidgetTester tester) async {
    await JarvisAuthSession.clear();
    await tester.pumpWidget(
      const MaterialApp(
        home: JarvisChairmanAuthGate(
          child: Scaffold(
            body: Center(child: Text('Local Jarvis is ready')),
          ),
        ),
      ),
    );

    expect(find.text('Local Jarvis is ready'), findsOneWidget);
    expect(find.textContaining('RESET MY PASSWORD'), findsNothing);

    // Protected cloud features retain optional identity verification.
    JarvisAuthSession.requestSignIn();
    await tester.pump();

    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
    expect(find.text('SEND VERIFICATION EMAIL'), findsOneWidget);
    expect(find.textContaining('RESET MY PASSWORD'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
