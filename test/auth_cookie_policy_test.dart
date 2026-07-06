import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/core/auth_cookie_policy.dart';

void main() {
  test('keeps real session cookie name-value only', () {
    expect(
      sessionCookieValueForStorage(
        'pyrita_session=abc123; Path=/; HttpOnly; Secure',
      ),
      'pyrita_session=abc123',
    );
  });

  test('does not persist cookie deletion headers', () {
    expect(
      sessionCookieValueForStorage('pyrita_session=; Path=/; Max-Age=0'),
      isNull,
    );
    expect(
      sessionCookieValueForStorage(
        'pyrita_session=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ),
      isNull,
    );
  });
}
