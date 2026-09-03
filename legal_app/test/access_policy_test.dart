import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_legal_enterprise/legal_core.dart';

void main() {
  group('Chairman entitlement', () {
    const AccessPolicy policy = AccessPolicy();

    test('chairman always has full access without a subscription', () {
      expect(
        policy.hasFullAccess(
          role: chairmanRole,
          subscriptionActive: false,
        ),
        isTrue,
      );
    });

    test('client without subscription is blocked', () {
      expect(
        policy.hasFullAccess(
          role: 'client',
          subscriptionActive: false,
        ),
        isFalse,
      );
    });

    test('client with active subscription is allowed', () {
      expect(
        policy.hasFullAccess(
          role: 'client',
          subscriptionActive: true,
        ),
        isTrue,
      );
    });
  });
}
