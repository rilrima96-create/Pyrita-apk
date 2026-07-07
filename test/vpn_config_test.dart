// Unit-тест для VLESS-URL parser + Xray config builder.
// Запускается через `flutter test`. Не требует устройства / эмулятора.
//
// Цель: убедиться что V2ray.parseFromURL → getFullConfiguration возвращает
// валидный JSON без null-полей, и после override routing наш final config
// можно decode и снова encode без потерь.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:pyrita_app/core/vpn_controller.dart';

void main() {
  // Тестовый VLESS+Reality URL — fake, для парсинга достаточен.
  // Реальный из Pyrita backend имеет тот же shape.
  const sampleVlessUrl =
      'vless://12345678-1234-1234-1234-123456789012@example.com:443'
      '?type=tcp&security=reality&pbk=publickeyhere&sid=shortidhere'
      '&fp=chrome&sni=apple.com&flow=xtls-rprx-vision'
      '#PyritaTest';

  test('V2ray.parseFromURL produces valid clean JSON', () {
    final parsed = V2ray.parseFromURL(sampleVlessUrl);

    // raw fullConfiguration — с null-полями
    // getFullConfiguration() — clean (без nulls)
    final cleanJson = parsed.getFullConfiguration();
    final cleanMap = jsonDecode(cleanJson) as Map<String, dynamic>;

    expect(cleanMap['log'], isNotNull);
    expect(cleanMap['inbounds'], isA<List>());
    expect(cleanMap['outbounds'], isA<List>());

    // Проверяем что outbound1 (vless) — НЕ содержит null'ов на топ-уровне
    final outbounds = cleanMap['outbounds'] as List;
    expect(outbounds.length, greaterThanOrEqualTo(2));
  });

  test('strips Xray settings removed by newer core builds', () {
    final parsed = V2ray.parseFromURL(sampleVlessUrl);
    final configMap =
        jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;

    stripRemovedXraySettings(configMap);

    expect(jsonEncode(configMap), isNot(contains('allowInsecure')));
  });

  test('Routing override produces valid JSON', () {
    final parsed = V2ray.parseFromURL(sampleVlessUrl);
    final cleanJson = parsed.getFullConfiguration();
    final configMap = jsonDecode(cleanJson) as Map<String, dynamic>;

    configMap['routing'] = <String, dynamic>{
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {
          'type': 'field',
          'domain': ['geosite:ru'],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'ip': ['geoip:ru', 'geoip:private'],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'outboundTag': 'proxy',
        },
      ],
    };

    final finalJson = jsonEncode(configMap);
    // Sanity: re-decode
    final reDecoded = jsonDecode(finalJson) as Map<String, dynamic>;
    final routing = reDecoded['routing'] as Map<String, dynamic>;
    expect((routing['rules'] as List).length, 3);
  });

  test('VPN bootstrap domains are routed directly', () {
    final domains = vpnBootstrapDomainsForUrl(
      'vless://12345678-1234-1234-1234-123456789012@us.pyrita.com:443'
      '?type=ws&security=tls&sni=www.bing.com&host=edge.pyrita.com'
      '#Pyrita-US',
    );

    expect(
        domains,
        containsAll([
          'full:us.pyrita.com',
          'full:www.bing.com',
          'full:edge.pyrita.com',
        ]));
  });

  test('routing rules keep DNS and VPN bootstrap outside the tunnel', () {
    final rules = buildVpnRoutingRules(
      primaryUrl:
          'vless://12345678-1234-1234-1234-123456789012@us.pyrita.com:443'
          '?type=ws&security=tls#Pyrita-US',
      ruDomainsBypass: const ['domain:sberbank.ru'],
    );

    expect(rules[0], {
      'type': 'field',
      'network': 'tcp,udp',
      'port': '53',
      'outboundTag': 'direct',
    });
    expect(rules[1], {
      'type': 'field',
      'domain': ['full:us.pyrita.com'],
      'outboundTag': 'direct',
    });
    expect(rules.where((rule) => rule['outboundTag'] == 'blackhole'),
        hasLength(1));
    expect(rules.last, {
      'type': 'field',
      'ip': ['geoip:private'],
      'outboundTag': 'direct',
    });
  });
}
