import 'dart:convert';

const defaultVpnServerId = 'fi';
const defaultVpnServerName = 'Хельсинки';
const defaultVpnServerCountryCode = 'FI';

const _supportedSchemes = {
  'vless',
  'vmess',
  'trojan',
  'ss',
  'socks',
  'hy2',
  'hysteria2',
};
const _visibleUnsupportedSchemes = {'tuic'};

class VpnServerProfile {
  const VpnServerProfile({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.protocolLabel,
    required this.url,
    required this.supported,
    this.unsupportedReason,
  });

  final String id;
  final String name;
  final String countryCode;
  final String protocolLabel;
  final String url;
  final bool supported;
  final String? unsupportedReason;
}

List<String> parseSubscriptionUrls(
  String body, {
  bool includeUnsupported = false,
}) {
  final text = _decodeSubscriptionBody(body);
  final seen = <String>{};
  final urls = <String>[];

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final url = line.trim();
    if (url.isEmpty || !seen.add(url)) continue;

    final scheme = _schemeOf(url);
    if (_supportedSchemes.contains(scheme) ||
        (includeUnsupported && _visibleUnsupportedSchemes.contains(scheme))) {
      urls.add(url);
    }
  }

  return urls;
}

List<VpnServerProfile> buildVpnServerProfiles(List<String> urls) {
  final byServer = <String, List<String>>{};
  for (final url in urls) {
    final id = vpnServerIdForUrl(url);
    byServer.putIfAbsent(id, () => <String>[]).add(url);
  }

  final profiles = <VpnServerProfile>[];
  for (final entry in byServer.entries) {
    final supportedUrls =
        entry.value.where(isSupportedSubscriptionUrl).toList();
    final chosen = _pickRepresentativeUrl(
      supportedUrls.isNotEmpty ? supportedUrls : entry.value,
    );
    profiles.add(VpnServerProfile(
      id: entry.key,
      name: vpnServerNameFor(entry.key, chosen),
      countryCode: vpnServerCountryCodeFor(entry.key),
      protocolLabel: vpnProtocolLabelForUrl(chosen),
      url: chosen,
      supported: supportedUrls.isNotEmpty,
      unsupportedReason:
          supportedUrls.isEmpty ? unsupportedReasonForUrl(chosen) : null,
    ));
  }

  profiles.sort((a, b) {
    final aOrder = _serverSortOrder(a.id);
    final bOrder = _serverSortOrder(b.id);
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);
    return a.name.compareTo(b.name);
  });
  return profiles;
}

List<String> supportedSubscriptionUrlsForServer(
  List<String> urls,
  String serverId,
) {
  return urls
      .where(isSupportedSubscriptionUrl)
      .where((url) => vpnServerIdForUrl(url) == serverId)
      .toList();
}

String encodeVpnServerProfilesSnapshot(List<VpnServerProfile> profiles) {
  return jsonEncode(profiles
      .map((profile) => {
            'id': profile.id,
            'name': profile.name,
            'countryCode': profile.countryCode,
            'protocolLabel': profile.protocolLabel,
            'supported': profile.supported,
            if (profile.unsupportedReason != null)
              'unsupportedReason': profile.unsupportedReason,
          })
      .toList());
}

List<VpnServerProfile> decodeVpnServerProfilesSnapshot(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((raw) =>
            raw['id'] is String &&
            raw['name'] is String &&
            raw['countryCode'] is String &&
            raw['protocolLabel'] is String)
        .map(
          (raw) => VpnServerProfile(
            id: raw['id'] as String,
            name: raw['name'] as String,
            countryCode: raw['countryCode'] as String,
            protocolLabel: raw['protocolLabel'] as String,
            url: '',
            supported: raw['supported'] == true,
            unsupportedReason: raw['unsupportedReason'] as String?,
          ),
        )
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

bool isSupportedSubscriptionUrl(String url) {
  return _supportedSchemes.contains(_schemeOf(url));
}

bool isHysteria2SubscriptionUrl(String url) {
  final scheme = _schemeOf(url);
  return scheme == 'hysteria2' || scheme == 'hy2';
}

String vpnServerIdForUrl(String url) {
  final uri = Uri.tryParse(url);
  final remark = _decodedRemark(uri);
  final haystack = '${uri?.host ?? ''} $remark'.toLowerCase();

  if (_containsToken(haystack, ['us', 'usa']) ||
      haystack.contains('united states') ||
      haystack.contains('america') ||
      haystack.contains('ashburn') ||
      haystack.contains('miami') ||
      haystack.contains('new-york') ||
      haystack.contains('newyork') ||
      haystack.contains('nyc')) {
    return 'us';
  }
  if (_containsToken(haystack, ['fi', 'fin']) ||
      haystack.contains('finland') ||
      haystack.contains('helsinki') ||
      haystack.contains('хельсинки') ||
      haystack.contains('фин')) {
    return 'fi';
  }
  return defaultVpnServerId;
}

String vpnServerNameFor(String id, [String? url]) {
  return switch (id) {
    'fi' => 'Хельсинки',
    'us' => 'США',
    _ => _fallbackNameFromUrl(url) ?? id.toUpperCase(),
  };
}

String vpnServerCountryCodeFor(String id) {
  return switch (id) {
    'fi' => 'FI',
    'us' => 'US',
    _ => id.length == 2 ? id.toUpperCase() : defaultVpnServerCountryCode,
  };
}

String vpnProtocolLabelForUrl(String url) {
  final scheme = _schemeOf(url);
  if (scheme == 'vless') {
    if (url.contains('type=xhttp')) return 'VLESS XHTTP';
    if (url.contains('security=reality')) return 'VLESS Reality';
    return 'VLESS';
  }
  if (scheme == 'ss') return 'Shadowsocks';
  if (scheme == 'vmess') return 'VMess';
  if (scheme == 'trojan') return 'Trojan';
  if (scheme == 'hysteria2' || scheme == 'hy2') return 'Hysteria2';
  if (scheme == 'tuic') return 'TUIC';
  return scheme.toUpperCase();
}

String? unsupportedReasonForUrl(String url) {
  final scheme = _schemeOf(url);
  if (scheme == 'tuic') {
    return 'TUIC пока доступен только во внешнем клиенте';
  }
  if (!isSupportedSubscriptionUrl(url)) {
    return 'Этот протокол пока не поддерживается приложением';
  }
  return null;
}

String _decodeSubscriptionBody(String body) {
  try {
    final cleaned = body.replaceAll(RegExp(r'\s+'), '');
    return utf8.decode(base64.decode(base64.normalize(cleaned)));
  } catch (_) {
    return body;
  }
}

String _schemeOf(String url) {
  final index = url.indexOf('://');
  if (index <= 0) return '';
  return url.substring(0, index).toLowerCase();
}

String _pickRepresentativeUrl(List<String> urls) {
  if (urls.isEmpty) {
    throw StateError('В подписке нет серверов');
  }

  String firstWhere(bool Function(String) test) {
    return urls.firstWhere(test, orElse: () => '');
  }

  final reality = firstWhere(
    (url) => url.startsWith('vless://') && url.contains('security=reality'),
  );
  if (reality.isNotEmpty) return reality;

  final xhttp = firstWhere(
    (url) => url.startsWith('vless://') && url.contains('type=xhttp'),
  );
  if (xhttp.isNotEmpty) return xhttp;

  final vless = firstWhere((url) => url.startsWith('vless://'));
  if (vless.isNotEmpty) return vless;

  final ss = firstWhere((url) => url.startsWith('ss://'));
  if (ss.isNotEmpty) return ss;

  return urls.first;
}

String? _fallbackNameFromUrl(String? url) {
  if (url == null) return null;
  final remark = _decodedRemark(Uri.tryParse(url));
  if (remark.isEmpty) return null;
  return remark;
}

String _decodedRemark(Uri? uri) {
  final fragment = uri?.fragment ?? '';
  if (fragment.isEmpty) return '';
  try {
    return Uri.decodeComponent(fragment);
  } catch (_) {
    return fragment;
  }
}

bool _containsToken(String haystack, List<String> tokens) {
  for (final token in tokens) {
    if (RegExp('(^|[^a-z0-9])$token([^a-z0-9]|\$)').hasMatch(haystack)) {
      return true;
    }
  }
  return false;
}

int _serverSortOrder(String id) {
  return switch (id) {
    'fi' => 0,
    'us' => 1,
    _ => 10,
  };
}
