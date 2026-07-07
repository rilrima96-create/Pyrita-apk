import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/core/vpn_controller.dart';

void main() {
  test('copyWith can explicitly clear transient error and ping fields', () {
    const status = PyritaVpnStatus(
      state: PyritaVpnState.connected,
      errorMessage: 'old error',
      serverPingMs: 42,
    );

    final cleared = status.copyWith(
      state: PyritaVpnState.disconnected,
      errorMessage: null,
      serverPingMs: null,
    );

    expect(cleared.state, PyritaVpnState.disconnected);
    expect(cleared.errorMessage, isNull);
    expect(cleared.serverPingMs, isNull);
  });

  test('copyWith preserves transient fields when omitted', () {
    const status = PyritaVpnStatus(
      state: PyritaVpnState.connected,
      errorMessage: 'keep me',
      serverPingMs: 77,
    );

    final updated = status.copyWith(downloadSpeed: 1024);

    expect(updated.errorMessage, 'keep me');
    expect(updated.serverPingMs, 77);
    expect(updated.downloadSpeed, 1024);
  });
}
