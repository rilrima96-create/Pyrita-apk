import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/core/vpn_controller.dart';
import 'package:pyrita_app/core/vpn_server_catalog.dart';

void main() {
  const fiReality =
      'vless://12345678-1234-1234-1234-123456789012@fi.pyrita.test:443'
      '?type=tcp&security=reality#Pyrita-FI';
  const usHy2 =
      'hysteria2://secret@us.pyrita.test:443?insecure=0#Pyrita-US-HY2';
  const usReality =
      'vless://12345678-1234-1234-1234-123456789012@us.pyrita.test:443'
      '?type=tcp&security=reality#Pyrita-US';

  test('keeps US Hy2 visible and supported', () {
    final body = base64Encode(utf8.encode('$fiReality\n$usHy2'));
    final urls = parseSubscriptionUrls(body, includeUnsupported: true);

    final profiles = buildVpnServerProfiles(urls);
    final fi = profiles.singleWhere((p) => p.id == 'fi');
    final us = profiles.singleWhere((p) => p.id == 'us');

    expect(fi.supported, isTrue);
    expect(fi.countryCode, 'FI');
    expect(us.supported, isTrue);
    expect(us.countryCode, 'US');
    expect(us.unsupportedReason, isNull);
  });

  test('prefers US Hy2 over generic VLESS in server picker', () {
    const usGenericVless =
        'vless://12345678-1234-1234-1234-123456789012@us.pyrita.test:443'
        '?type=ws&security=tls#Pyrita-US';
    final profiles = buildVpnServerProfiles([usGenericVless, usHy2]);
    final us = profiles.singleWhere((p) => p.id == 'us');

    expect(us.protocolLabel, 'Hysteria2');
    expect(us.url, usHy2);
  });

  test('prefers US Hy2 over US VLESS XHTTP in server picker', () {
    const usXhttp =
        'vless://12345678-1234-1234-1234-123456789012@us.pyrita.test:443'
        '?type=xhttp&security=tls#Pyrita-US-XHTTP';
    final profiles = buildVpnServerProfiles([usXhttp, usHy2]);
    final us = profiles.singleWhere((p) => p.id == 'us');

    expect(us.protocolLabel, 'Hysteria2');
    expect(us.url, usHy2);
  });

  test('filters supported URLs by selected server', () {
    final urls = parseSubscriptionUrls(
      '$fiReality\n$usReality\n$usHy2',
      includeUnsupported: true,
    );

    expect(supportedSubscriptionUrlsForServer(urls, 'us'), [
      usReality,
      usHy2,
    ]);
    expect(supportedSubscriptionUrlsForServer(urls, 'fi'), [fiReality]);
  });

  test('plain and base64 subscription bodies produce the same URL list', () {
    final plain = '$fiReality\n$usReality';
    final encoded = base64Encode(utf8.encode(plain));

    expect(parseSubscriptionUrls(encoded), parseSubscriptionUrls(plain));
  });

  test('server profile snapshot keeps safe picker data only', () {
    final profiles = buildVpnServerProfiles([fiReality, usReality]);
    final snapshot = encodeVpnServerProfilesSnapshot(profiles);
    final decoded = decodeVpnServerProfilesSnapshot(snapshot);

    expect(snapshot.contains('vless://'), isFalse);
    expect(decoded.map((p) => p.id), ['fi', 'us']);
    expect(decoded.map((p) => p.supported), [true, true]);
    expect(decoded.singleWhere((p) => p.id == 'us').url, isEmpty);
  });

  test('builds a Hysteria2 Xray config from subscription URL', () {
    final config = buildHysteria2XrayConfigMap(
      'hysteria2://example-pass@us.pyrita.test:443/'
      '?sni=www.bing.com&insecure=1&obfs=salamander'
      '&obfs-password=example-obfs#Pyrita-US-HY2',
    );

    final outbound = (config['outbounds'] as List).first as Map;
    final settings = outbound['settings'] as Map;
    final streamSettings = outbound['streamSettings'] as Map;
    final hysteriaSettings = streamSettings['hysteriaSettings'] as Map;
    final tlsSettings = streamSettings['tlsSettings'] as Map;
    final masks = streamSettings['udpmasks'] as List;

    expect(outbound['protocol'], 'hysteria');
    expect(settings['address'], 'us.pyrita.test');
    expect(settings['port'], 443);
    expect(hysteriaSettings['version'], 2);
    expect(hysteriaSettings['auth'], 'example-pass');
    expect(tlsSettings['serverName'], 'www.bing.com');
    expect(tlsSettings.containsKey('allowInsecure'), isFalse);
    expect(masks.first, {
      'type': 'salamander',
      'settings': {'password': 'example-obfs'},
    });
  });
}
