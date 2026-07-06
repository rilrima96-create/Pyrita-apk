import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/features/splash/auth_bootstrap_decision.dart';

void main() {
  group('shouldSendBootstrapFailureToLogin', () {
    test('sends real auth failures to login', () {
      expect(shouldSendBootstrapFailureToLogin(401), isTrue);
      expect(shouldSendBootstrapFailureToLogin(403), isTrue);
    });

    test('keeps a stored session on transient network or server failures', () {
      expect(shouldSendBootstrapFailureToLogin(0), isFalse);
      expect(shouldSendBootstrapFailureToLogin(500), isFalse);
      expect(shouldSendBootstrapFailureToLogin(-1), isFalse);
    });
  });
}
