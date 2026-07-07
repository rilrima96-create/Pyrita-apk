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

  test('failed tunnel delay sample keeps the last good ping', () {
    const status = PyritaVpnStatus(
      state: PyritaVpnState.connected,
      serverPingMs: 61,
    );

    final updated = applyTunnelDelaySample(status, -1);

    expect(updated.serverPingMs, 61);
  });

  test('successful tunnel delay sample updates ping only while connected', () {
    const connected = PyritaVpnStatus(
      state: PyritaVpnState.connected,
      serverPingMs: 61,
    );
    const disconnected = PyritaVpnStatus(
      state: PyritaVpnState.disconnected,
      serverPingMs: 61,
    );

    expect(applyTunnelDelaySample(connected, 72).serverPingMs, 72);
    expect(applyTunnelDelaySample(disconnected, 72).serverPingMs, 61);
  });
}
