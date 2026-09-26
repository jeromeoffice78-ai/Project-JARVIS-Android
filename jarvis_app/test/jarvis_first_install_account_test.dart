import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project_jarvis/core/auth/jarvis_chairman_auth.dart';
import 'package:project_jarvis/core/auth/jarvis_password_account_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new installation requires account and does not skip sign-in',
      (WidgetTester tester) async {
    await JarvisAuthSession.clear();
    final http.Client httpClient = MockClient(
      (http.Request request) async => http.Response('Not authorized', 401),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JarvisPasswordAccountGate(
          client: httpClient,
          child: const Scaffold(
            body: Text('Protected Jarvis command center'),
          ),
        ),
      ),
    );
    for (int attempt = 0; attempt < 15; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('SIGN IN TO JARVIS').evaluate().isNotEmpty) break;
    }
    expect(find.text('SIGN IN TO JARVIS'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Protected Jarvis command center'), findsNothing);
    await tester.tap(find.text('FIRST TIME? CREATE ACCOUNT'));
    await tester.pump();
    expect(find.text('CREATE YOUR JARVIS ACCOUNT'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    await tester.tap(find.text('BACK TO SIGN IN'));
    await tester.pump();
    await tester.tap(find.text('FORGOT PASSWORD?'));
    await tester.pump();
    expect(find.text('RESET JARVIS PASSWORD'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    httpClient.close();
  });
}
