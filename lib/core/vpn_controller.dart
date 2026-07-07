import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'notification_service.dart';
import 'vpn_server_catalog.dart';

/// Состояние VPN-туннеля для UI-слоя.
///
/// Маппится из `V2RayStatus.state` (плагин даёт UPPERCASE строки):
///   * `DISCONNECTED` → `disconnected`
///   * `CONNECTING` → `connecting`
///   * `CONNECTED` → `connected`
///   * прочее → `error`
enum PyritaVpnState { disconnected, connecting, connected, error }

const Object _copyWithUnset = Object();

/// Снимок состояния VPN на момент времени. Иммутабельный — Riverpod-friendly.
///
/// Поля скоростей и трафика приходят от Xray-core stats каждые ~1 сек, когда
/// state == connected. В idle/error — нули (плагин не эмитит обновления).
@immutable
class PyritaVpnStatus {
  const PyritaVpnStatus({
    required this.state,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.duration = '00:00:00',
    this.errorMessage,
    this.serverPingMs,
    this.preferredProtocolId = 'reality',
    this.preferredServerId = defaultVpnServerId,
    this.serverName = defaultVpnServerName,
    this.serverCountryCode = defaultVpnServerCountryCode,
  });

  final PyritaVpnState state;

  /// Текущий preferred protocol id (см. `/api/me/protocols` для catalog).
  /// Default 'reality'. Меняется через `VpnController.switchProtocol()`.
  /// UI использует чтобы отрисовать который protocol реально active в
  /// Pyrita-app — backend всегда говорит "Reality primary", это поле —
  /// клиентский override.
  final String preferredProtocolId;

  /// Клиентский выбор локации из подписки.
  final String preferredServerId;

  /// Локация, по которой сейчас строится или был построен туннель.
  final String serverName;

  /// ISO-like код для UI-флага.
  final String serverCountryCode;

  /// Текущая скорость отдачи, байт/сек.
  final int uploadSpeed;

  /// Текущая скорость загрузки, байт/сек.
  final int downloadSpeed;

  /// Всего отдано за текущую сессию, байт.
  final int uploadTotal;

  /// Всего получено за текущую сессию, байт.
  final int downloadTotal;

  /// Длительность сессии в формате 'HH:MM:SS' (от плагина).
  final String duration;

  /// Описание последней ошибки. null если state != error.
  final String? errorMessage;

  /// Latency до сервера, мс. Обновляется раз в ~5 сек когда connected.
  /// null = ещё не измерено или нерелевантно (idle/error).
  final int? serverPingMs;

  bool get isConnected => state == PyritaVpnState.connected;
  bool get isConnecting => state == PyritaVpnState.connecting;
  bool get isIdle => state == PyritaVpnState.disconnected;
  bool get isError => state == PyritaVpnState.error;

  PyritaVpnStatus copyWith({
    PyritaVpnState? state,
    int? uploadSpeed,
    int? downloadSpeed,
    int? uploadTotal,
    int? downloadTotal,
    String? duration,
    Object? errorMessage = _copyWithUnset,
    Object? serverPingMs = _copyWithUnset,
    String? preferredProtocolId,
    String? preferredServerId,
    String? serverName,
    String? serverCountryCode,
  }) {
    return PyritaVpnStatus(
      state: state ?? this.state,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      duration: duration ?? this.duration,
      errorMessage: identical(errorMessage, _copyWithUnset)
          ? this.errorMessage
          : errorMessage as String?,
      serverPingMs: identical(serverPingMs, _copyWithUnset)
          ? this.serverPingMs
          : serverPingMs as int?,
      preferredProtocolId: preferredProtocolId ?? this.preferredProtocolId,
      preferredServerId: preferredServerId ?? this.preferredServerId,
      serverName: serverName ?? this.serverName,
      serverCountryCode: serverCountryCode ?? this.serverCountryCode,
    );
  }
}

class _BuiltXrayConfig {
  const _BuiltXrayConfig({
    required this.config,
    required this.server,
  });

  final String config;
  final VpnServerProfile server;
}

@visibleForTesting
Map<String, dynamic> buildStableVpnDnsConfig() => <String, dynamic>{
      'queryStrategy': 'UseIPv4',
      'servers': [
        '1.1.1.1',
        '1.0.0.1',
        '9.9.9.9',
        '8.8.8.8',
      ],
    };

@visibleForTesting
Map<String, dynamic> buildHysteria2XrayConfigMap(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !isHysteria2SubscriptionUrl(url)) {
    throw ArgumentError('url is not Hysteria2');
  }

  final host = uri.host.trim();
  final port = uri.hasPort ? uri.port : 443;
  final auth = _decodeHysteriaUrlPart(uri.userInfo);
  if (host.isEmpty || port < 1 || port > 65535 || auth.isEmpty) {
    throw StateError('HY2-ссылка сервера неполная');
  }

  final query = uri.queryParameters;
  final sni = _trimOrNull(query['sni']) ?? host;
  final tlsSettings = <String, dynamic>{
    'serverName': sni,
  };

  final alpn = _splitHysteriaList(query['alpn']);
  if (alpn.isNotEmpty) {
    tlsSettings['alpn'] = alpn;
  }

  final streamSettings = <String, dynamic>{
    'network': 'hysteria',
    'security': 'tls',
    'tlsSettings': tlsSettings,
    'hysteriaSettings': <String, dynamic>{
      'version': 2,
      'auth': auth,
      'udpIdleTimeout': 60,
    },
  };

  final obfsType = _trimOrNull(query['obfs']);
  final obfsPassword = _trimOrNull(
    query['obfs-password'] ?? query['obfs_password'],
  );
  if ((obfsType == null) != (obfsPassword == null)) {
    throw StateError('HY2-ссылка содержит неполные obfs-параметры');
  }
  if (obfsType != null && obfsPassword != null) {
    streamSettings['udpmasks'] = [
      {
        'type': obfsType,
        'settings': {'password': obfsPassword},
      }
    ];
  }

  return <String, dynamic>{
    'log': {
      'access': '',
      'error': '',
      'loglevel': 'error',
      'dnsLog': false,
    },
    'inbounds': [
      {
        'tag': 'in_proxy',
        'port': 10808,
        'protocol': 'socks',
        'listen': '127.0.0.1',
        'settings': {
          'auth': 'noauth',
          'udp': true,
          'userLevel': 8,
        },
        'sniffing': {'enabled': false},
      }
    ],
    'outbounds': [
      {
        'tag': 'proxy',
        'protocol': 'hysteria',
        'settings': {
          'version': 2,
          'address': host,
          'port': port,
          // flutter_v2ray_client's Android wrapper reads `servers` to fill
          // notification/status metadata. Xray ignores unknown settings here.
          'servers': [
            {
              'address': host,
              'port': port,
            }
          ],
        },
        'streamSettings': streamSettings,
      },
      {
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'UseIp'},
      },
      {
        'tag': 'blackhole',
        'protocol': 'blackhole',
        'settings': {},
      },
    ],
    'dns': buildStableVpnDnsConfig(),
    'routing': {
      'domainStrategy': 'UseIp',
      'rules': [],
      'balancers': [],
    },
  };
}

@visibleForTesting
Map<String, dynamic> buildHttpProxyXrayConfigMap({
  required String host,
  required int port,
  required String username,
  required String password,
  required String locationId,
  required List<String> ruDomainsBypass,
  String scheme = 'http',
}) {
  final normalizedScheme = scheme.trim().toLowerCase();
  final normalizedHost = host.trim().toLowerCase();
  final normalizedUsername = username.trim();
  final normalizedPassword = password.trim();

  if (normalizedScheme != 'http') {
    throw StateError('Неподдерживаемая схема прокси: $scheme');
  }
  if (normalizedHost.isEmpty || port < 1 || port > 65535) {
    throw StateError('Прокси-сервер передан неполностью');
  }
  if (normalizedUsername.isEmpty || normalizedPassword.isEmpty) {
    throw StateError('Прокси-сервер не выдал авторизацию');
  }

  final rules = buildVpnRoutingRules(
    primaryUrl: 'http-proxy://$normalizedHost:$port#$locationId',
    ruDomainsBypass: ruDomainsBypass,
    blockQuic: false,
  );
  rules.add({
    'type': 'field',
    'network': 'udp',
    'outboundTag': 'direct',
  });

  return <String, dynamic>{
    'log': {
      'access': '',
      'error': '',
      'loglevel': 'debug',
      'dnsLog': false,
    },
    'inbounds': [
      {
        'tag': 'in_proxy',
        'port': 10808,
        'protocol': 'socks',
        'listen': '127.0.0.1',
        'settings': {
          'auth': 'noauth',
          'udp': true,
          'userLevel': 8,
        },
        'sniffing': {'enabled': false},
      }
    ],
    'outbounds': [
      {
        'tag': 'proxy',
        'protocol': 'http',
        'settings': {
          'servers': [
            {
              'address': normalizedHost,
              'port': port,
              'users': [
                {
                  'user': normalizedUsername,
                  'pass': normalizedPassword,
                }
              ],
            }
          ],
        },
      },
      {
        'tag': 'direct',
        'protocol': 'freedom',
        'settings': {'domainStrategy': 'UseIp'},
      },
      {
        'tag': 'blackhole',
        'protocol': 'blackhole',
        'settings': {},
      },
    ],
    'dns': buildStableVpnDnsConfig(),
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
      'balancers': [],
    },
  };
}

@visibleForTesting
void stripRemovedXraySettings(Map<String, dynamic> configMap) {
  void visit(Object? value) {
    if (value is Map) {
      value.remove('allowInsecure');
      for (final child in value.values) {
        visit(child);
      }
      return;
    }
    if (value is Iterable) {
      for (final child in value) {
        visit(child);
      }
    }
  }

  visit(configMap);
}

@visibleForTesting
List<String> vpnBootstrapDomainsForUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return const [];

  final hosts = <String>{};
  void addHost(String? value) {
    final host = _trimOrNull(value)?.toLowerCase();
    if (host == null || _looksLikeIpAddress(host)) return;
    hosts.add('full:$host');
  }

  addHost(uri.host);
  addHost(uri.queryParameters['sni']);
  addHost(uri.queryParameters['host']);

  return hosts.toList(growable: false);
}

@visibleForTesting
List<Map<String, dynamic>> buildVpnRoutingRules({
  required String primaryUrl,
  required List<String> ruDomainsBypass,
  bool blockQuic = true,
}) {
  final bootstrapDomains = vpnBootstrapDomainsForUrl(primaryUrl);
  return <Map<String, dynamic>>[
    {
      'type': 'field',
      'network': 'tcp,udp',
      'port': '53',
      'outboundTag': 'direct',
    },
    if (bootstrapDomains.isNotEmpty)
      {
        'type': 'field',
        'domain': bootstrapDomains,
        'outboundTag': 'direct',
      },
    if (blockQuic)
      {
        'type': 'field',
        'network': 'udp',
        'port': '443',
        'outboundTag': 'blackhole',
      },
    {
      'type': 'field',
      'domain': ruDomainsBypass,
      'outboundTag': 'direct',
    },
    {
      'type': 'field',
      'ip': ['geoip:private'],
      'outboundTag': 'direct',
    },
  ];
}

bool _looksLikeIpAddress(String host) {
  return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
      host.contains(':');
}

String _decodeHysteriaUrlPart(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

List<String> _splitHysteriaList(String? value) {
  final raw = _trimOrNull(value);
  if (raw == null) return const [];
  return raw
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

/// Riverpod-managed VPN controller — единая точка управления туннелем.
///
/// Под капотом — `V2ray` instance из `flutter_v2ray_client` (Xray-core
/// MPL-2.0). Плагин держит native Android VpnService, MethodChannel и
/// EventChannel внутри — наш код просто проводит status в Riverpod-state
/// и реализует Pyrita-specific логику (sub URL fetch, RU bypass routing,
/// pre-onboarding gate).
///
/// Lifecycle:
///   * Конструктор — создаёт V2ray + запускает фоновую initialize()
///   * `start()` — fetch /api/me → парсит sub URL → строит Xray config →
///     `_v2ray.startV2Ray(...)`. Plugin emit'ит status через callback,
///     обновляем state.
///   * `stop()` — `_v2ray.stopV2Ray()`. Status callback emit'нет
///     `DISCONNECTED` сам.
class VpnController extends StateNotifier<PyritaVpnStatus> {
  VpnController()
      : super(const PyritaVpnStatus(state: PyritaVpnState.disconnected)) {
    _v2ray = V2ray(onStatusChanged: _onStatusChanged);
    _initFuture = _init();
    _wireConnectivity();
  }

  late final V2ray _v2ray;
  late final Future<void> _initFuture;

  /// Кэшированный Xray-config для быстрого auto-reconnect без повторного
  /// `/api/me` + `/api/sub` round-trip'а при network change.
  String? _lastConfigForReconnect;

  String? _lastServerNameForReconnect;

  List<VpnServerProfile>? _serverProfilesCache;

  /// Period-таймер для обновления server ping каждые 5 сек когда connected.
  Timer? _pingTimer;

  int _consecutivePingFailures = 0;

  String? _pendingTunnelFailureMessage;

  /// Subscription на connectivity_plus events. Cancel в dispose().
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// Был ли VPN активен непосредственно перед потерей сети. Это сигнал
  /// что нужен auto-reconnect когда сеть вернётся.
  bool _wasConnectedBeforeNetLoss = false;

  /// v0.1.16: Completer которым start() ждёт CONNECTED status от плагина.
  /// _onStatusChanged комплитит его при PyritaVpnState.connected. Permission
  /// для timeout escape когда протокол broken (XHTTP без ALPN — типичный
  /// пример: TCP up, traffic flows, но plugin не emit'ит CONNECTED).
  Completer<void>? _connectedCompleter;

  static const _prefKeyPermissionRequested = 'vpn_permission_requested';
  static const _prefKeyServerProfilesSnapshot = 'server_profiles_snapshot_v1';

  /// SharedPreferences key для предпочитаемого протокола. Один из id'шников
  /// из `/api/me/protocols` (см. ProtocolInfo.id):
  ///   * `'reality'`   — VLESS+Reality (default, DPI-устойчивый)
  ///   * `'xhttp'`     — VLESS+XHTTP (если backend начнёт класть в подписку)
  ///   * `'hysteria2'` — Hy2 (currently плагин не парсит — fallback на reality)
  ///   * `'tuic'`      — TUIC (currently плагин не парсит — fallback на reality)
  ///   * `'ss2022'`    — Shadowsocks 2022 (плагин парсит ss://, но AEAD-2022
  ///                     ключи могут нужно дополнительной обработки)
  ///
  /// Phase D scope: реально переключаемся только между protocol которые
  /// одновременно (а) есть в подписке Marzban'а и (б) parseFromURL не
  /// бросает ArgumentError. Если preferred недоступен → fallback на Reality
  /// с snackbar-warning'ом из UI слоя.
  static const _prefKeyPreferredProtocol = 'preferred_protocol';
  static const _prefKeyPreferredServer = 'preferred_server';
  static const _defaultProtocol = 'reality';
  static const _tunnelHealthCheckUrl =
      'http://clients3.google.com/generate_204';

  /// Курированный список RU-доменов которые должны идти direct (без VPN
  /// туннеля). Без этого банки / госуслуги / маркетплейсы видят финский IP
  /// (Helsinki — наш Marzban-сервер) и блокируют / показывают captcha.
  ///
  /// Этот список — pragmatic workaround вместо bundled geoip/geosite.dat
  /// (которые добавили бы ~30 MB к каждому APK и потребовали бы override
  /// plugin's stale bundled geo files). Long tail RU доменов всё равно
  /// идёт через VPN — большинство сайтов работают через FI IP, проблема
  /// только с финансовыми и государственными сервисами.
  ///
  /// Phase E: заменить на bundled geo files (`geosite:ru` + `geoip:ru`)
  /// после prep'а custom-trimmed `.dat` файлов (~5 MB combined).
  ///
  /// Categorized для maintainability. Использует Xray's `domain:` prefix
  /// — matches «домен и все поддомены» (sberbank.ru, www.sberbank.ru,
  /// online.sberbank.ru, etc).
  static const List<String> _ruDomainsBypass = [
    // Банки + СБП
    'domain:sberbank.ru', 'domain:sber.ru', 'domain:sbrf.ru',
    'domain:tinkoff.ru', 'domain:t-bank.ru', 'domain:tcsbank.ru',
    'domain:vtb.ru', 'domain:vtb24.ru',
    'domain:alfabank.ru', 'domain:alfabank.com',
    'domain:gazprombank.ru',
    'domain:raiffeisen.ru',
    'domain:psbank.ru',
    'domain:rshb.ru',
    'domain:open.ru', 'domain:openbank.ru',
    'domain:rosbank.ru',
    'domain:mkb.ru',
    'domain:sovcombank.ru', 'domain:halvacard.ru',
    'domain:yoomoney.ru', 'domain:yookassa.ru',
    'domain:qiwi.com', 'domain:qiwi.ru',
    'domain:nspk.ru',
    // Госуслуги, налоги
    'domain:gosuslugi.ru',
    'domain:nalog.ru', 'domain:nalog.gov.ru',
    'domain:gibdd.ru',
    'domain:pfr.gov.ru', 'domain:sfr.gov.ru',
    'domain:fssp.gov.ru',
    'domain:mos.ru', 'domain:mosreg.ru',
    'domain:rosreestr.ru', 'domain:rosreestr.gov.ru',
    'domain:roskazna.ru',
    'domain:rt.ru',
    'domain:mvd.ru', 'domain:мвд.рф',
    'domain:rkn.gov.ru',
    'domain:fns.ru',
    'domain:zakupki.gov.ru',
    'domain:roszdravnadzor.gov.ru',
    'domain:mos.ru',
    // Мобильные операторы
    'domain:mts.ru', 'domain:mts.by',
    'domain:beeline.ru',
    'domain:megafon.ru',
    'domain:tele2.ru',
    'domain:yota.ru',
    // Yandex экосистема
    'domain:yandex.ru', 'domain:yandex.com', 'domain:yandex.net',
    'domain:ya.ru', 'domain:yandex.cloud',
    'domain:kinopoisk.ru', 'domain:dzen.ru',
    // Mail.ru / VK группа
    'domain:mail.ru', 'domain:list.ru', 'domain:inbox.ru', 'domain:bk.ru',
    'domain:vk.com', 'domain:vk.ru', 'domain:vkontakte.ru',
    'domain:vkuseraudio.net',
    'domain:ok.ru', 'domain:odnoklassniki.ru',
    'domain:my.com',
    // Маркетплейсы
    'domain:ozon.ru',
    'domain:wildberries.ru', 'domain:wb.ru',
    'domain:dns-shop.ru',
    'domain:citilink.ru',
    'domain:eldorado.ru', 'domain:mvideo.ru',
    'domain:lamoda.ru',
    'domain:lenta.com',
    'domain:perekrestok.ru',
    'domain:magnit.ru',
    'domain:pyaterochka.ru',
    'domain:vkusvill.ru',
    'domain:detmir.ru',
    'domain:utkonos.ru',
    'domain:samokat.ru',
    'domain:sbermarket.ru',
    'domain:dostavista.ru',
    // Авто, недвижимость, работа
    'domain:avito.ru',
    'domain:auto.ru',
    'domain:drom.ru',
    'domain:cian.ru',
    'domain:domclick.ru',
    'domain:hh.ru', 'domain:superjob.ru',
    // Доставка еды, такси
    'domain:delivery-club.ru',
    'domain:yandex-eda.ru', 'domain:eda.yandex',
    // Стриминг, медиа
    'domain:rutube.ru',
    'domain:premier.one',
    'domain:okko.tv',
    'domain:ivi.ru',
    'domain:wink.ru',
    'domain:smotrim.ru',
    'domain:1tv.ru',
    'domain:russia.tv',
    // СМИ (для read access без captcha)
    'domain:rbc.ru',
    'domain:lenta.ru',
    'domain:ria.ru',
    'domain:tass.ru',
    'domain:kommersant.ru',
    'domain:rg.ru',
    'domain:vedomosti.ru',
    'domain:gazeta.ru',
    'domain:iz.ru',
    'domain:meduza.io',
    // Аэропорты, ЖД
    'domain:rzd.ru',
    'domain:aeroflot.ru',
    'domain:pobeda.aero',
    's7.ru',
    'domain:utair.ru',
    'domain:airunion.ru',
    // Учебные, медицинские, прочие критичные
    'domain:moodle.org',
    'domain:rg.ru',
    'domain:sechenov.ru',
    'domain:doctorpiter.ru',
    'domain:invitro.ru',
    'domain:medsi.ru',
    // Pyrita-собственные домены — иначе self-traffic зацикливается через VPN
    'domain:pyrita.com',
    'domain:api.pyrita.com',
  ];

  Future<void> _init() async {
    // Notification icon — monochrome silhouette (drawable/ic_notification.xml).
    // НЕ launcher icon: launcher это adaptive-with-background, Android
    // показывает его в status bar как белый квадрат (некрасиво).
    // ic_notification — VectorDrawable hexagon, рендерится корректно
    // в notification bar / lockscreen / шторке.
    await _v2ray.initialize(
      notificationIconResourceType: 'drawable',
      notificationIconResourceName: 'ic_notification',
    );

    // Hydrate local preferences. До первой записи — Reality + Helsinki.
    final preferred = await _getPreferredProtocol();
    final preferredServer = await _getPreferredServer();
    if (mounted) {
      state = state.copyWith(
        preferredProtocolId: preferred,
        preferredServerId: preferredServer,
        serverName: vpnServerNameFor(preferredServer),
        serverCountryCode: vpnServerCountryCodeFor(preferredServer),
      );
    }

    // Кастомная notification поверх plugin's PRIORITY_MIN. Slушаем
    // disconnect-tap из шторки → routes сюда → stop() как если бы юзер
    // тапнул pulse.
    //
    // v0.1.13: wrap'аем в try-catch потому что flutter_local_notifications
    // throws PlatformException(invalid_icon) на некоторых Samsung-устройствах
    // в release build даже когда resource ic_notification реально присутствует
    // в drawable*/ folders. Это блокировало весь _init() → start() catches →
    // юзер видел «Не удалось подключиться» без возможности запустить VPN
    // вообще. Если notification setup fails — продолжаем без него, юзер
    // видит plugin's стандартный PRIORITY_MIN notification (без custom title/
    // disconnect button — но VPN работает).
    try {
      await PyritaNotificationService.instance.init();
      _disconnectSub =
          PyritaNotificationService.instance.disconnectRequests.listen((_) {
        if (mounted && state.isConnected) {
          unawaited(stop());
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('[Pyrita-VPN] notification overlay init failed (non-fatal): $e');
    }
  }

  StreamSubscription<void>? _disconnectSub;

  void _onStatusChanged(V2RayStatus s) {
    if (!mounted) return;
    final previous = state;
    final mapped = switch (s.state.toUpperCase()) {
      'CONNECTED' => PyritaVpnState.connected,
      'CONNECTING' => PyritaVpnState.connecting,
      'DISCONNECTED' => PyritaVpnState.disconnected,
      _ => PyritaVpnState.error,
    };

    final pendingFailure = _pendingTunnelFailureMessage;
    if (mapped == PyritaVpnState.disconnected && pendingFailure != null) {
      _pendingTunnelFailureMessage = null;
      _stopPingTimer();
      _consecutivePingFailures = 0;
      state = PyritaVpnStatus(
        state: PyritaVpnState.error,
        errorMessage: pendingFailure,
        preferredProtocolId: previous.preferredProtocolId,
        preferredServerId: previous.preferredServerId,
        serverName: previous.serverName,
        serverCountryCode: previous.serverCountryCode,
      );
      unawaited(PyritaNotificationService.instance.hide());
      return;
    }

    state = state.copyWith(
      state: mapped,
      uploadSpeed: s.uploadSpeed,
      downloadSpeed: s.downloadSpeed,
      uploadTotal: s.upload,
      downloadTotal: s.download,
      duration: s.duration,
      // Сбрасываем ping при не-connected state (UI рендерит '—' в idle).
      serverPingMs:
          mapped == PyritaVpnState.connected ? state.serverPingMs : null,
      // Очищаем error message при успешном connect.
      errorMessage:
          mapped == PyritaVpnState.connected ? null : state.errorMessage,
    );

    // Ping-timer работает только когда туннель активен.
    if (mapped == PyritaVpnState.connected) {
      // v0.1.16: разблокируем start()'s await on CONNECTED.
      if (_connectedCompleter != null && !_connectedCompleter!.isCompleted) {
        _connectedCompleter!.complete();
      }
      if (!previous.isConnected) {
        _consecutivePingFailures = 0;
        _startPingTimer();
        // Кастомная notification: ставим как только Xray-core эмитит
        // CONNECTED. Updates на каждом ping tick'е через
        // PyritaNotificationService.updatePing (debounced там же).
        unawaited(PyritaNotificationService.instance.showConnected(
          serverName: state.serverName,
          pingMs: state.serverPingMs,
        ));
      }
    } else {
      _stopPingTimer();
      _consecutivePingFailures = 0;
      if (mapped == PyritaVpnState.connecting) {
        unawaited(PyritaNotificationService.instance.showConnecting(
          serverName: state.serverName,
        ));
      } else {
        // disconnected / error — убираем notification полностью.
        unawaited(PyritaNotificationService.instance.hide());
      }
    }
  }

  // ─────────────────────────────── Live ping ───────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // Plugin делает HEAD-like request через Xray-core и измеряет
        // round-trip. Test URL должен (1) идти через tunnel (не direct),
        // (2) быть consistently available, (3) возвращать 2xx/3xx
        // быстро.
        //
        // History: plugin default `google.com/generate_204` блочится
        // RKN на mobile carriers (юзер сообщил 2026-05-15). Попробовали
        // `cloudflare.com/cdn-cgi/trace` — тоже не сработало (-1
        // в logs). Сейчас `clients3.google.com/generate_204` — endpoint
        // Android'а для captive-portal detection, доступен из любой
        // юрисдикции через VPN egress.
        final ms = await _measureTunnelDelay();
        if (!mounted || !state.isConnected) return;
        // Plugin возвращает -1 при timeout / failure. Не пишем такие в
        // state — UI рендерит '—' если pingMs null, что точнее чем
        // показывать -1.
        if (ms <= 0) {
          _consecutivePingFailures += 1;
          // ignore: avoid_print
          print(
            '[Pyrita-VPN] ping returned $ms '
            '(failure $_consecutivePingFailures/3)',
          );
          state = state.copyWith(serverPingMs: null);
          unawaited(PyritaNotificationService.instance.updatePing(
            serverName: state.serverName,
            pingMs: null,
          ));
          return;
        }
        _consecutivePingFailures = 0;
        // ignore: avoid_print
        print('[Pyrita-VPN] ping=$ms ms');
        state = state.copyWith(serverPingMs: ms);
        // Notification debounce'ит само если ping не сильно изменился.
        unawaited(PyritaNotificationService.instance.updatePing(
          serverName: state.serverName,
          pingMs: ms,
        ));
      } catch (e) {
        // ignore: avoid_print
        print('[Pyrita-VPN] ping exception: $e');
      }
    });
  }

  Future<int> _measureTunnelDelay() async {
    try {
      return await _v2ray
          .getConnectedServerDelay(url: _tunnelHealthCheckUrl)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => -1,
          );
    } catch (_) {
      return -1;
    }
  }

  Future<int?> _waitForTunnelHealth() async {
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      final ms = await _measureTunnelDelay();
      if (ms > 0) return ms;

      // ignore: avoid_print
      print('[Pyrita-VPN] startup healthcheck failed ($attempt/3)');
      if (attempt < 3) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    return null;
  }

  // ignore: unused_element
  Future<void> _stopWithTunnelFailure(String message) async {
    if (_pendingTunnelFailureMessage != null) return;
    _pendingTunnelFailureMessage = message;
    _stopPingTimer();
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {
      // If native stop fails, still move UI to a truthful error state below.
    }

    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted || _pendingTunnelFailureMessage != message) return;
    _pendingTunnelFailureMessage = null;
    _consecutivePingFailures = 0;
    state = PyritaVpnStatus(
      state: PyritaVpnState.error,
      errorMessage: message,
      preferredProtocolId: state.preferredProtocolId,
      preferredServerId: state.preferredServerId,
      serverName: state.serverName,
      serverCountryCode: state.serverCountryCode,
    );
    unawaited(PyritaNotificationService.instance.hide());
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ─────────────────────────── Auto-reconnect ─────────────────────────────

  void _wireConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((events) {
      final hasNetwork = events.any((e) => e != ConnectivityResult.none);

      if (!hasNetwork) {
        // Сеть пропала. Plugin'у нужно ~10-30 сек чтобы понять что
        // tunnel умер и emit'нуть DISCONNECTED — в это время state
        // visual'но остаётся 'connected', а юзер уже видит «нет
        // интернета» в браузере (фактический tunnel down).
        //
        // Forcing state в connecting сразу: visual feedback совпадает
        // с реальностью, ping снимается, UI показывает «ожидание сети».
        // Когда сеть вернётся → _autoReconnect полностью перевзведёт
        // tunnel; если сеть так и не вернулась → state остаётся
        // connecting + errorMessage пока юзер не tap'нет «отключить».
        if (state.isConnected) {
          _wasConnectedBeforeNetLoss = true;
          // Прямой конструктор — copyWith использует null-coalescing
          // и не позволяет очистить serverPingMs (null остаётся sticky).
          // Также resetим upload/downloadSpeed чтобы UI «zero stream»
          // matched no-network reality.
          state = PyritaVpnStatus(
            state: PyritaVpnState.connecting,
            errorMessage: 'Ожидание сети…',
            preferredProtocolId: state.preferredProtocolId,
            preferredServerId: state.preferredServerId,
            serverName: state.serverName,
            serverCountryCode: state.serverCountryCode,
          );
          _stopPingTimer();
        }
        return;
      }

      // Сеть вернулась. Если до потери был connected, но Xray уже не
      // держит туннель (он обычно падает при network change) — поднимаем
      // заново. 2 сек паузы дают сетевому стеку стабилизироваться.
      if (_wasConnectedBeforeNetLoss && !state.isConnected) {
        _wasConnectedBeforeNetLoss = false;
        unawaited(_autoReconnect());
      } else if (state.isConnected) {
        // Туннель пережил change (редко, но бывает на iOS-стиле seamless
        // hand-off). Очищаем флаг.
        _wasConnectedBeforeNetLoss = false;
      }
    });
  }

  Future<void> _autoReconnect() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Быстрый path: используем кэшированный config (не дёргаем /api/me).
    final cached = _lastConfigForReconnect;
    if (cached != null) {
      try {
        final serverName = _lastServerNameForReconnect ?? state.serverName;
        state = PyritaVpnStatus(
          state: PyritaVpnState.connecting,
          preferredProtocolId: state.preferredProtocolId,
          preferredServerId: state.preferredServerId,
          serverName: serverName,
          serverCountryCode: state.serverCountryCode,
        );
        await _v2ray.startV2Ray(
          remark: 'Pyrita · $serverName',
          config: cached,
          proxyOnly: false,
          notificationDisconnectButtonName: 'Отключить',
        );
        return;
      } catch (_) {
        // Кэш протух (например, серверный uuid ротировался) —
        // откатываемся на полный start() с refresh подписки.
      }
    }
    await start();
  }

  @override
  void dispose() {
    _stopPingTimer();
    _connSub?.cancel();
    _connSub = null;
    _disconnectSub?.cancel();
    _disconnectSub = null;
    super.dispose();
  }

  /// Запрашивает VpnService.prepare() — system dialog «Разрешить Pyrita
  /// настраивать VPN». Returns true если пользователь принял (или уже
  /// был принят ранее). Параллельно сохраняем флаг «запрос был сделан»
  /// для pre-onboarding-гейта.
  Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyPermissionRequested, true);
    return _v2ray.requestPermission();
  }

  /// Запрашивался ли VpnService.prepare() хоть раз?
  /// Использует pre-onboarding screen для показа explanation только
  /// первый раз (после accept-flow или deny — больше не показываем).
  Future<bool> hasPermissionEverBeenRequested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyPermissionRequested) ?? false;
  }

  /// Поднимает туннель.
  ///
  /// Шаги:
  ///   1. Дожидаемся `_init` завершения (защита от race-tap)
  ///   2. State → connecting (UI рисует pulsing sonar)
  ///   3. Fetch /api/me → достаём subscription_url
  ///   4. Скачиваем содержимое sub URL → base64-decode → массив URL
  ///   5. Выбираем VLESS+Reality (или fallback на любой VLESS)
  ///   6. Парсим через `V2ray.parseFromURL` → строим Xray-config
  ///   7. Добавляем RU bypass routing rules
  ///   8. Передаём config в `_v2ray.startV2Ray(...)`
  ///   9. Плагин emit'ит CONNECTED через onStatusChanged callback —
  ///      state обновляется автоматически.
  Future<void> start() async {
    // Защитный timeout на initialize() — если plugin init hangs (например,
    // MethodChannel registration упал на native стороне), без этого
    // дальнейший код никогда не выполнится.
    try {
      await _initFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Не удалось инициализировать VPN-движок за 15 сек. '
          'Plugin native side не отвечает. '
          'Попробуйте перезапустить приложение.',
          const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      state = PyritaVpnStatus(
        state: PyritaVpnState.error,
        errorMessage: _humanizeError(e),
        preferredProtocolId: state.preferredProtocolId,
        preferredServerId: state.preferredServerId,
        serverName: state.serverName,
        serverCountryCode: state.serverCountryCode,
      );
      return;
    }
    if (!mounted) return;

    state = PyritaVpnStatus(
      state: PyritaVpnState.connecting,
      preferredProtocolId: state.preferredProtocolId,
      preferredServerId: state.preferredServerId,
      serverName: state.serverName,
      serverCountryCode: state.serverCountryCode,
    );
    try {
      final me = await ApiClient.instance.getMe();
      final subUrl = me['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        throw StateError('Не удалось получить subscription_url');
      }

      final built = await _buildXrayConfig(subUrl);
      _lastConfigForReconnect = built.config;
      _lastServerNameForReconnect = built.server.name;
      if (built.server.id != state.preferredServerId) {
        await _setPreferredServer(built.server.id);
      }
      state = state.copyWith(
        preferredServerId: built.server.id,
        serverName: built.server.name,
        serverCountryCode: built.server.countryCode,
      );

      // Race-condition guard для VPN handoff. Когда Android grants permission
      // нашему app'у, он СНАЧАЛА убивает текущий active VPN (Hiddify etc.),
      // и только потом наш VpnService может поднять туннель. Без задержки
      // plugin может crash'ить пытаясь create TUN interface пока Android
      // ещё не освободил VPN-слот. 1.5 сек обычно достаточно.
      await Future.delayed(const Duration(milliseconds: 1500));

      // startV2Ray() обычно resolve-ится за <500ms — plugin запускает
      // Xray в фоне и возвращает control. CONNECTED status приходит
      // через onStatusChanged callback позже, когда Xray handshake'ит
      // с сервером (Reality+TLS может занимать 5-30 сек на медленных
      // сетях; user network может быть RKN-filtered → handshake slow).
      //
      // 60 сек timeout — только для случая если plugin worker process
      // crashes и Future никогда не resolve'ится.
      // Готовим Completer для CONNECTED-await ПЕРЕД startV2Ray чтобы не
      // miss'нуть fast-path emit'а (некоторые сети handshake'ятся <100ms).
      _connectedCompleter ??= Completer<void>();

      await _v2ray
          .startV2Ray(
            remark: 'Pyrita · ${built.server.name}',
            config: built.config,
            proxyOnly: false,
            notificationDisconnectButtonName: 'Отключить',
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
              'VPN-движок не ответил за 60 сек. Возможно процесс упал.',
              const Duration(seconds: 60),
            ),
          );

      // ignore: avoid_print
      print('[Pyrita-VPN] startV2Ray returned, awaiting CONNECTED status');

      // v0.1.16: 30-сек deadline на CONNECTED status. Без этого юзер,
      // переключившийся на сломанный протокол (например XHTTP с ALPN
      // mismatch на старом backend) застревает в forever-CONNECTING:
      // big button не реагирует, Settings не прогружаются (HTTP-запросы
      // тайм-аутят через dead tunnel), recovery возможен только через
      // adb force-stop или uninstall.
      //
      // На timeout: stop tunnel + revert preferred protocol на 'reality'
      // (которая всегда работает) + throw error. Юзер видит понятный
      // banner «Протокол не отвечает, вернули Reality».
      try {
        await _connectedCompleter!.future.timeout(
          const Duration(seconds: 30),
        );
      } on TimeoutException {
        final failedProtocol = await _getPreferredProtocol();
        // ignore: avoid_print
        print(
            '[Pyrita-VPN] CONNECTED timeout (30s) for protocol=$failedProtocol; reverting to reality');
        await _v2ray.stopV2Ray().catchError((_) {});
        // Reset preferred → Reality чтобы next start() взял рабочий
        // протокол. Если failed = reality сам — оставляем (значит сеть
        // в целом плохая, fallback'ать некуда).
        if (failedProtocol != _defaultProtocol) {
          await _setPreferredProtocol(_defaultProtocol);
          if (mounted) {
            state = state.copyWith(preferredProtocolId: _defaultProtocol);
          }
        }
        throw TimeoutException(
          failedProtocol == _defaultProtocol
              ? 'Сервер не ответил за 30 сек. Проверьте сеть.'
              : 'Протокол ${_protocolHumanName(failedProtocol)} не подключается. '
                  'Вернули VLESS Reality.',
          const Duration(seconds: 30),
        );
      } finally {
        _connectedCompleter = null;
      }

      final initialPingMs = await _waitForTunnelHealth();
      if (!mounted || !state.isConnected) return;
      _consecutivePingFailures = 0;
      state = state.copyWith(serverPingMs: initialPingMs);
      unawaited(PyritaNotificationService.instance.updatePing(
        serverName: state.serverName,
        pingMs: initialPingMs,
      ));
    } catch (e, st) {
      // ignore: avoid_print
      print('[Pyrita-VPN] start() exception: ${e.runtimeType}: $e');
      // ignore: avoid_print
      print(
          '[Pyrita-VPN] stack: ${st.toString().split('\n').take(5).join(' | ')}');
      if (!mounted) return;
      state = PyritaVpnStatus(
        state: PyritaVpnState.error,
        errorMessage: _humanizeError(e),
        preferredProtocolId: state.preferredProtocolId,
        preferredServerId: state.preferredServerId,
        serverName: state.serverName,
        serverCountryCode: state.serverCountryCode,
      );
    }
  }

  /// Запрашивает последние Xray logs от плагина для UI debug-screen.
  /// Возвращает пустой список при ошибке (например, plugin не инициализирован).
  /// 3-сек timeout — _v2ray.getLogs() это MethodChannel call который
  /// может блокировать main thread (ANR) если plugin's worker process
  /// занят Xray handshake'ом.
  Future<List<String>> fetchLogs() async {
    try {
      return await _v2ray.getLogs().timeout(
            const Duration(seconds: 3),
            onTimeout: () =>
                ['(getLogs timeout — plugin busy, попробуй позже)'],
          );
    } catch (_) {
      return [];
    }
  }

  /// Текущий cached config, если есть. Для debug-screen.
  String? get currentConfig => _lastConfigForReconnect;

  Future<List<VpnServerProfile>> loadServerProfiles() async {
    final cached = await _readServerProfilesCache();
    if (state.isConnected && cached.isNotEmpty) {
      return cached;
    }

    try {
      return await _loadServerProfilesFresh().timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<VpnServerProfile>> _loadServerProfilesFresh() async {
    final me = await ApiClient.instance.getMe();
    final subUrl = me['subscription_url'] as String?;
    if (subUrl == null || subUrl.isEmpty) {
      throw StateError('Не удалось получить subscription_url');
    }

    final urls = await _fetchSubscriptionUrls(
      subUrl,
      includeUnsupported: true,
    );
    final profiles = buildVpnServerProfiles(urls);
    if (profiles.isEmpty) {
      throw StateError('В подписке нет серверов');
    }
    await _rememberServerProfiles(profiles);
    return profiles;
  }

  Future<void> _rememberServerProfiles(List<VpnServerProfile> profiles) async {
    _serverProfilesCache = profiles;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyServerProfilesSnapshot,
      encodeVpnServerProfilesSnapshot(profiles),
    );
  }

  Future<List<VpnServerProfile>> _readServerProfilesCache() async {
    final memory = _serverProfilesCache;
    if (memory != null && memory.isNotEmpty) return memory;

    final prefs = await SharedPreferences.getInstance();
    final snapshot = prefs.getString(_prefKeyServerProfilesSnapshot);
    if (snapshot == null || snapshot.isEmpty) return const [];

    final profiles = decodeVpnServerProfilesSnapshot(snapshot);
    if (profiles.isNotEmpty) {
      _serverProfilesCache = profiles;
    }
    return profiles;
  }

  /// Останавливает туннель. Plugin emit'ит DISCONNECTED через callback.
  Future<void> stop() async {
    // Явный stop пользователем — отменяем потенциальный auto-reconnect.
    // Иначе сценарий: сеть пропадает → юзер тапает «отключить» → сеть
    // возвращается → tunnel сам поднимается (нежелательно).
    _wasConnectedBeforeNetLoss = false;
    _pendingTunnelFailureMessage = null;
    _consecutivePingFailures = 0;
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {
      // Если уже остановлен или ещё не стартовал — молча игнорируем.
    }
  }

  /// Скачивает sub URL и возвращает плоский список parsable URL'ов.
  /// Reusable helper — используется как _buildXrayConfig (полный config),
  /// так и switchProtocol (pre-check что preferred protocol реально в
  /// подписке, иначе backend кэширует stale `available=true` flag).
  Future<List<String>> _fetchSubscriptionUrls(
    String subUrl, {
    bool includeUnsupported = false,
  }) async {
    // Backend 2026-05-16 добавил `?format=singbox` в default subscription_url
    // (для Hiddify Pro/Max Shield filters). Pyrita-app использует Xray-core
    // через flutter_v2ray_client и парсит **base64-список** VLESS URL'ов —
    // sing-box JSON парсить не умеет. Strip query чтобы получить legacy
    // формат от backend's fallback path.
    final parsedUri = Uri.parse(subUrl);
    final legacyUri = parsedUri.replace(queryParameters: const {});
    final cleanUrl = legacyUri.toString();

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final resp = await dio.get<String>(
      cleanUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'User-Agent': 'Pyrita-app/Phase-C'},
      ),
    );
    final raw = (resp.data ?? '').trim();
    if (raw.isEmpty) {
      throw StateError('Подписка вернула пустой ответ');
    }

    final urls = parseSubscriptionUrls(
      raw,
      includeUnsupported: includeUnsupported,
    );
    if (urls.isEmpty) {
      // Diagnostic: если backend опять изменит формат, юзер увидит первые
      // 200 chars body'а — поможет быстро понять что прилетело.
      final preview = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
      throw StateError(
        'В подписке не найдено ни одного протокола. '
        'Backend ответил: $preview',
      );
    }
    return urls;
  }

  String _proxyLocationIdForServer(String serverId) {
    return switch (serverId) {
      'us' => 'us',
      _ => 'finland',
    };
  }

  String _proxyServerIdForPreference(String serverId) {
    return serverId == 'us' ? 'us' : defaultVpnServerId;
  }

  VpnServerProfile _proxyServerProfile(
    String serverId,
    List<VpnServerProfile> profiles,
  ) {
    for (final profile in profiles) {
      if (profile.id == serverId) {
        return VpnServerProfile(
          id: profile.id,
          name: profile.name,
          countryCode: profile.countryCode,
          protocolLabel: 'HTTP Proxy',
          url: 'http-proxy://${_proxyLocationIdForServer(serverId)}',
          supported: true,
        );
      }
    }
    return VpnServerProfile(
      id: serverId,
      name: vpnServerNameFor(serverId),
      countryCode: vpnServerCountryCodeFor(serverId),
      protocolLabel: 'HTTP Proxy',
      url: 'http-proxy://${_proxyLocationIdForServer(serverId)}',
      supported: true,
    );
  }

  Future<_BuiltXrayConfig?> _tryBuildHttpProxyConfig(
    String serverId,
    List<VpnServerProfile> profiles,
  ) async {
    final locationId = _proxyLocationIdForServer(serverId);
    try {
      final data = await ApiClient.instance
          .getProxyConfig(locationId: locationId)
          .timeout(const Duration(seconds: 10));
      final proxyValue = data['proxy'];
      if (proxyValue is! Map) {
        throw StateError('API не вернул proxy');
      }
      final proxy = Map<String, dynamic>.from(proxyValue);
      final host = proxy['host'] as String?;
      final username = proxy['username'] as String?;
      final password = proxy['password'] as String?;
      final scheme = (proxy['scheme'] as String?) ?? 'http';
      final portValue = proxy['port'];
      final port = portValue is int
          ? portValue
          : portValue is num
              ? portValue.toInt()
              : int.tryParse('${portValue ?? ''}');
      if (host == null ||
          username == null ||
          password == null ||
          port == null) {
        throw StateError('API вернул неполный proxy');
      }

      final configMap = buildHttpProxyXrayConfigMap(
        host: host,
        port: port,
        username: username,
        password: password,
        scheme: scheme,
        locationId: locationId,
        ruDomainsBypass: _ruDomainsBypass,
      );

      return _BuiltXrayConfig(
        config: jsonEncode(configMap),
        server: _proxyServerProfile(serverId, profiles),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[Pyrita-VPN] HTTP proxy route unavailable for $locationId: $e');
      return null;
    }
  }

  /// Скачивает Pyrita sub URL, выбирает primary URL (с учётом
  /// `preferred_protocol`), строит JSON-config для Xray-core с включёнными
  /// правилами RU-bypass.
  ///
  /// Pyrita backend (Marzban) возвращает либо base64-encoded плоский
  /// список URL'ов (по одной строке), либо plain text. Поддерживаем оба.
  Future<_BuiltXrayConfig> _buildXrayConfig(String subUrl) async {
    final preferredServer = _proxyServerIdForPreference(
      await _getPreferredServer(),
    );
    final cachedProfiles = await _readServerProfilesCache();
    final proxyBuilt = await _tryBuildHttpProxyConfig(
      preferredServer,
      cachedProfiles,
    );
    if (proxyBuilt != null) return proxyBuilt;

    final urls = await _fetchSubscriptionUrls(
      subUrl,
      includeUnsupported: true,
    );
    final profiles = buildVpnServerProfiles(urls);
    if (profiles.isNotEmpty) {
      await _rememberServerProfiles(profiles);
    }

    var selectedServerId = preferredServer;
    var serverUrls = supportedSubscriptionUrlsForServer(urls, selectedServerId);

    if (serverUrls.isEmpty && selectedServerId != defaultVpnServerId) {
      selectedServerId = defaultVpnServerId;
      serverUrls = supportedSubscriptionUrlsForServer(urls, selectedServerId);
    }

    if (serverUrls.isEmpty) {
      serverUrls = urls.where(isSupportedSubscriptionUrl).toList();
      if (serverUrls.isEmpty) {
        throw StateError(
          'В подписке есть только протоколы, которые это приложение пока не поддерживает',
        );
      }
    }

    final preferred = await _getPreferredProtocol();
    final primaryUrl = _pickPrimaryUrl(serverUrls, preferred: preferred);
    final server = buildVpnServerProfiles([primaryUrl]).first;

    final Map<String, dynamic> configMap;
    if (isHysteria2SubscriptionUrl(primaryUrl)) {
      configMap = buildHysteria2XrayConfigMap(primaryUrl);
    } else {
      // Парсинг через factory плагина — определяет протокол по prefix.
      // Для VLESS+Reality возвращает `VlessURL` с заполненными
      // realitySettings (publicKey, shortId, fingerprint).
      final parsed = V2ray.parseFromURL(primaryUrl);

      // КРИТИЧЕСКИ ВАЖНО: используем getFullConfiguration() (метод), а не
      // fullConfiguration (raw Map). Метод дополнительно вызывает
      // removeNulls() — без этого config содержит десятки null полей
      // в outbound1/outbound2/outbound3 settings (servers: null, response: null,
      // address: null, port: null, secretKey: null, peers: null и т.п.).
      // Xray-core на parse такого JSON может вести себя undefined: ранее
      // зависал на startV2Ray() Future в pending state — обнаружено
      // на Android 16 при первом acceptance test.
      final cleanJson = parsed.getFullConfiguration();
      configMap = jsonDecode(cleanJson) as Map<String, dynamic>;
    }
    stripRemovedXraySettings(configMap);
    configMap['dns'] = buildStableVpnDnsConfig();

    // Поднимаем log level до 'debug' — Xray начнёт писать detail'ы
    // handshake'а (TCP connect, TLS, Reality auth). Это нужно для
    // диагностики «вечного connecting» — мы видим где handshake
    // застрял или какие frames Xray отправляет.
    configMap['log'] = <String, dynamic>{
      'loglevel': 'debug',
      'access': '',
      'error': '',
    };

    // PLUGIN BUG WORKAROUND #1 — port mismatch between Xray inbound и tun2socks:
    //
    // Plugin's V2RayURL base class defaults inbound.port = 1080.
    // Plugin's V2rayConfig.LOCAL_SOCKS5_PORT = 10808 (hardcoded в Java).
    // Plugin's V2rayVPNService spawns tun2socks с `--socks-server-addr
    // 127.0.0.1:10808`.
    //
    // Net effect: Xray listens 1080, tun2socks dials 10808 — никто на
    // 10808 не слушает → packets никуда не идут → state forever
    // CONNECTING без признаков activity.
    //
    // Это plugin design bug — мы override port на 10808 чтобы Xray
    // listened на тот же port что и tun2socks dials.
    final inbounds = configMap['inbounds'] as List?;
    if (inbounds != null && inbounds.isNotEmpty) {
      final firstInbound = inbounds[0];
      if (firstInbound is Map) {
        firstInbound['port'] = 10808;
      }
    }

    // REVERTED XTLS strip — VLESS+Reality сервер ожидает
    // flow=xtls-rprx-vision как часть Reality протокола. Strip ломает
    // handshake silent — server reject'ит non-XTLS клиента fail-closed.
    // Симптом: tunnel up, Xray proxy logs идут, но никакой response от
    // server'а — browser hangs «Соединение прервано».
    //
    // Sticking with flow=xtls-rprx-vision (preserved from subscription URL).
    // Plugin's libv2ray.aar v26.4.17 должна support XTLS — verified что
    // Xray Go binary стартует и pipes traffic через uplink.

    // PLUGIN BUG WORKAROUND #2 — XHTTP transport support:
    //
    // flutter_v2ray_client v3.2.0 plugin's `populateTransportSettings` ничего
    // не знает про `type=xhttp` (поддержки до сих пор не вмёрджено в plugin —
    // xray-core 1.8.10+ её добавил, plugin отстаёт). Plugin'овский parser
    // выставляет `streamSettings.network = 'xhttp'` (вот это работает —
    // network устанавливается «как есть» из URL query 'type'), но **не**
    // добавляет `xhttpSettings` блок, без которого xray-core не знает path/host
    // для HTTP/2 stream'а → connect fails с `unable to use xhttp transport
    // without proper settings`.
    //
    // Мы вручную инжектим xhttpSettings блок из URL query params после
    // parseFromURL. Также убираем `streamSettings.tcpSettings` если оно
    // случайно осталось (фалбэк-результат tcp-branch'а в plugin).
    //
    // SNI/TLS: plugin'овский populateTlsSettings ставит `serverName = sni` и
    // `fingerprint` корректно — оставляем как есть.
    if (primaryUrl.startsWith('vless://') &&
        primaryUrl.contains('type=xhttp')) {
      _injectXHttpSettings(configMap, primaryUrl);
    }

    // Routing:
    //
    // 1. UDP/443 → blackhole. КРИТИЧЕСКИ ВАЖНО для XTLS Vision.
    //    XTLS-Vision (flow=xtls-rprx-vision) поддерживает ТОЛЬКО TCP.
    //    UDP/443 (QUIC / HTTP/3) отвергается с ошибкой
    //    'XTLS rejected UDP/443 traffic' — браузер hangs пытаясь
    //    HTTP/3 first. Hiddify применяет тот же block.
    //    После block браузер fallback'нет на TCP/443 (regular HTTPS),
    //    которое идёт через XTLS Vision успешно.
    //
    // 2. Hardcoded RU domain list → direct (real IP, не через Helsinki).
    //    Банки и mobile carriers REJECT'ят запросы с финского IP
    //    (T-Bank выдаёт 403, Sberbank лагает, Yandex показывает captcha).
    //    Bundled geo files откладываются в Phase E (~30 MB APK overhead +
    //    plugin's old bundled geo.dat несовместим с Xray 26.4).
    //
    //    Список курирован вручную: топ-сервисы которые юзер реально
    //    использует ежедневно. Long tail RU доменов оставлен через
    //    VPN — большинство сайтов работают через FI IP, банки нет.
    //
    // 3. Private IPs → direct (localhost, LAN).
    //
    // 4. Всё остальное → proxy (VPN tunnel).
    configMap['routing'] = <String, dynamic>{
      'domainStrategy': 'IPIfNonMatch',
      'rules': buildVpnRoutingRules(
        primaryUrl: primaryUrl,
        ruDomainsBypass: _ruDomainsBypass,
      ),
    };

    return _BuiltXrayConfig(
      config: jsonEncode(configMap),
      server: server,
    );
  }

  /// Patches the outbound's streamSettings с правильным `xhttpSettings`
  /// блоком из query params VLESS XHTTP URL. См. PLUGIN BUG WORKAROUND #2
  /// в [_buildXrayConfig].
  ///
  /// Структура xhttpSettings ожидаемая xray-core 1.8.10+:
  ///
  /// ```json
  /// "streamSettings": {
  ///   "network": "xhttp",          // уже выставлено plugin'ом
  ///   "security": "tls",           // уже выставлено plugin'ом
  ///   "tlsSettings": { ... },      // уже выставлено plugin'ом
  ///   "xhttpSettings": {           // <-- мы добавляем это
  ///     "path": "/pyrita-x-...",
  ///     "host": "pyrita.com",
  ///     "mode": "auto"
  ///   }
  /// }
  /// ```
  ///
  /// Если URL malformed (нет path / host params) — оставляем как есть
  /// (xray-core sам decline'нет, ошибка увидится в _humanizeError).
  void _injectXHttpSettings(Map<String, dynamic> configMap, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final path = uri.queryParameters['path'];
    if (path == null || !path.startsWith('/')) {
      // Без path xray-core не сможет route'ить request — лог-warning,
      // но не throw'аем (let xray-core fail с понятной ошибкой).
      // ignore: avoid_print
      print('[Pyrita-VPN] XHTTP URL missing valid path: $url');
      return;
    }
    final hostHeader =
        uri.queryParameters['host'] ?? uri.queryParameters['sni'] ?? uri.host;
    final mode = uri.queryParameters['mode'] ?? 'auto';

    final outbounds = configMap['outbounds'] as List?;
    if (outbounds == null || outbounds.isEmpty) return;
    final firstOut = outbounds.firstWhere(
      (o) => o is Map && (o['tag'] == 'proxy' || o['protocol'] == 'vless'),
      orElse: () => outbounds[0],
    );
    if (firstOut is! Map) return;

    final streamSettings = firstOut['streamSettings'];
    if (streamSettings is! Map) return;

    // Чистим tcpSettings если оно есть — plugin может ошибочно выставить
    // как fallback (default branch в populateTransportSettings).
    streamSettings.remove('tcpSettings');

    streamSettings['xhttpSettings'] = <String, dynamic>{
      'path': path,
      'host': hostHeader,
      'mode': mode,
    };

    // Defense-in-depth: если URL не передал alpn (backend bug или старая
    // подписка) — добавляем h2,http/1.1 потому что server-side обычно
    // требует HTTP/2 для xhttp transport. ALPN missing на TLS-handshake →
    // server reject'ит connection silently → user видит «вечный connecting».
    final tlsSettings = streamSettings['tlsSettings'];
    if (tlsSettings is Map) {
      final currentAlpn = tlsSettings['alpn'];
      if (currentAlpn == null || (currentAlpn is List && currentAlpn.isEmpty)) {
        tlsSettings['alpn'] = <String>['h2', 'http/1.1'];
        // ignore: avoid_print
        print('[Pyrita-VPN] XHTTP TLS alpn injected (default h2,http/1.1)');
      }
    }

    // ignore: avoid_print
    print(
        '[Pyrita-VPN] XHTTP settings injected: path=$path host=$hostHeader mode=$mode');
  }

  /// Выбирает primary URL из списка с учётом preferred protocol.
  ///
  /// Phase D: реально parsable плагином → vless / vmess / trojan / ss /
  /// socks. Hy2 / TUIC требуют custom parser (Phase E).
  ///
  /// Алгоритм:
  ///   1. Если `preferred` указан и matching URL есть в подписке —
  ///      берём его (например 'xhttp' → vless+type=xhttp URL).
  ///   2. Если preferred недоступен (или 'reality' = default) →
  ///      приоритет: VLESS Reality > Hysteria2 > VLESS XHTTP > любой VLESS.
  ///   3. Если VLESS нет вовсе → fallback на любой parseable
  ///      (vmess/trojan/ss/socks) — это «recovery mode» если backend
  ///      сменил основной протокол.
  String _pickPrimaryUrl(List<String> urls,
      {String preferred = _defaultProtocol}) {
    // Step 1: попробовать matching preferred (если не default).
    if (preferred != _defaultProtocol) {
      final matched = _findByPreferred(urls, preferred);
      if (matched != null) return matched;
      // Preferred unavailable — fallback на стандартный порядок.
    }

    // Step 2: US safety override. The current Android failure mode is a green
    // VPN over US VLESS/WebSocket with dead HTTPS traffic. If the subscription
    // contains the tested US-HY2 profile, use it before any US VLESS fallback.
    if (urls.any((u) => vpnServerIdForUrl(u) == 'us')) {
      final usHysteria2 = urls.firstWhere(
        isHysteria2SubscriptionUrl,
        orElse: () => '',
      );
      if (usHysteria2.isNotEmpty) return usHysteria2;
    }

    // Step 3: VLESS Reality (default primary).
    final reality = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('security=reality'),
      orElse: () => '',
    );
    if (reality.isNotEmpty) return reality;

    // Step 4: Hysteria2. Если Reality нет, это лучший Android-кандидат для
    // US: обычные VLESS/WS профили уже давали green VPN без usable traffic.
    final anyHysteria2 = urls.firstWhere(
      isHysteria2SubscriptionUrl,
      orElse: () => '',
    );
    if (anyHysteria2.isNotEmpty) return anyHysteria2;

    // Step 5: VLESS XHTTP.
    final xhttp = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('type=xhttp'),
      orElse: () => '',
    );
    if (xhttp.isNotEmpty) return xhttp;

    // Step 6: Любой VLESS.
    final anyVless = urls.firstWhere(
      (u) => u.startsWith('vless://'),
      orElse: () => '',
    );
    if (anyVless.isNotEmpty) return anyVless;

    // Step 7: Recovery mode — любой parseable URL (если backend сменил
    // primary protocol на trojan/ss/vmess — клиент пытается подключиться
    // через него вместо упорного crash'а с «VLESS не найден»).
    final anyParseable = urls.firstWhere(
      (u) =>
          u.startsWith('vmess://') ||
          u.startsWith('trojan://') ||
          u.startsWith('ss://'),
      orElse: () => throw StateError(
        'В подписке нет ни одного протокола который умеет наш клиент',
      ),
    );
    return anyParseable;
  }

  /// Маппинг protocol-id (из `/api/me/protocols`) → URL filter в base64-
  /// подписке. Возвращает первый matching URL или `null` если такого
  /// нет (тогда caller fallback'нет на default order).
  String? _findByPreferred(List<String> urls, String preferred) {
    bool match(String u) {
      switch (preferred) {
        case 'reality':
          return u.startsWith('vless://') && u.contains('security=reality');
        case 'xhttp':
          return u.startsWith('vless://') && u.contains('type=xhttp');
        case 'ss2022':
          // Shadowsocks 2022 — может маркироваться как ss:// с 2022-blake3-*
          // method. Plugin shadowsocks.dart парсит ss:// generic, но 2022
          // method ciphers могут потребовать дополнительной отладки.
          return u.startsWith('ss://');
        case 'hysteria2':
          return isHysteria2SubscriptionUrl(u);
        case 'tuic':
          // TUIC требует отдельный core/parser. Возвращаем null, caller
          // fallback'нет на default. UI слой должен ДО switchProtocol
          // проверить что preferred parseable.
          return false;
        default:
          return false;
      }
    }

    final found = urls.firstWhere(match, orElse: () => '');
    return found.isEmpty ? null : found;
  }

  /// Читает preferred protocol id из SharedPreferences. Возвращает
  /// `_defaultProtocol` ('reality') если ничего не сохранено.
  Future<String> _getPreferredProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyPreferredProtocol) ?? _defaultProtocol;
  }

  /// Сохраняет preferred protocol id. Caller должен gracefully fallback'ать
  /// если protocol недоступен в подписке (UI dialog).
  Future<void> _setPreferredProtocol(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyPreferredProtocol, id);
  }

  Future<String> _getPreferredServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyPreferredServer) ?? defaultVpnServerId;
  }

  Future<void> _setPreferredServer(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyPreferredServer, id);
  }

  /// Human-readable имя протокола для error-banner'ов. Hardcoded короткий
  /// маппинг — без API round-trip'а в момент error-display'а.
  String _protocolHumanName(String id) => switch (id) {
        'reality' => 'VLESS Reality',
        'xhttp' => 'VLESS XHTTP',
        'hysteria2' => 'Hysteria 2',
        'tuic' => 'TUIC',
        'ss2022' => 'Shadowsocks 2022',
        _ => id,
      };

  /// Переключает preferred protocol. Если currently connected — gracefully
  /// reconnect через 1.5 сек (даёт Xray time на cleanup TUN-interface'а).
  ///
  /// `protocolsCatalog` — список доступных протоколов из `/api/me/protocols`.
  /// Используется для validation: если `id` не в catalog или `!available`,
  /// throws StateError с понятным message'ом — UI ловит и показывает
  /// snackbar «Этот протокол не доступен».
  ///
  /// Returns:
  ///   * `true` — switched successfully (reconnected if was connected)
  ///   * `false` — switched but не reconnect'или (был disconnected)
  Future<bool> switchProtocol(
    String id, {
    required List<ProtocolInfo> protocolsCatalog,
  }) async {
    final entry = protocolsCatalog.firstWhere(
      (p) => p.id == id,
      orElse: () => throw StateError('Неизвестный протокол: $id'),
    );
    if (!entry.available) {
      throw StateError(
        'Протокол ${entry.name} ещё не настроен на сервере. '
        'Pyrita-сервер не положил его в подписку.',
      );
    }
    // Plugin's parseFromURL поддерживает только vless / vmess / trojan / ss /
    // socks. Hy2 собираем вручную ниже; TUIC требует отдельный core/parser.
    const parseable = {'reality', 'xhttp', 'ss2022', 'hysteria2'};
    if (!parseable.contains(id)) {
      throw StateError(
        'Протокол ${entry.name} пока не поддерживается на этом устройстве. '
        'Появится в следующих версиях.',
      );
    }

    // Pre-check: backend's `available` flag может быть stale — серверный
    // catalog говорит «XHTTP доступен», но в base64-подписке его реально
    // нет (backend B.1 task в pyrita-web repo). Без этой проверки
    // switchProtocol успешно сохранил бы preference, restart'нул бы Xray,
    // но `_pickPrimaryUrl` silently fallback'нул на Reality — юзер видит
    // «переключился и через секунду вернулся на Reality».
    try {
      final me = await ApiClient.instance.getMe();
      final subUrl = me['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        throw StateError('Не удалось получить subscription_url');
      }
      final urls = await _fetchSubscriptionUrls(
        subUrl,
        includeUnsupported: true,
      );
      final serverUrls = supportedSubscriptionUrlsForServer(
        urls,
        state.preferredServerId,
      );
      final urlsToCheck = serverUrls.isNotEmpty
          ? serverUrls
          : urls.where(isSupportedSubscriptionUrl).toList();
      final matched = _findByPreferred(urlsToCheck, id);
      if (matched == null) {
        throw StateError(
          '${entry.name} помечен как доступный, но сервер не положил его '
          'в подписку. Сообщите в поддержку (Pyrita backend B.1 task).',
        );
      }
    } on DioException {
      throw StateError(
        'Не удалось проверить подписку. Проверьте интернет и попробуйте снова.',
      );
    }

    await _setPreferredProtocol(id);
    state = state.copyWith(preferredProtocolId: id);

    // Если connected → reconnect c новым preferred. Cache invalidate'ится
    // потому что full start() заново строит config.
    if (state.isConnected) {
      await stop();
      await Future.delayed(const Duration(milliseconds: 1500));
      _lastConfigForReconnect = null; // force rebuild
      await start();
      return true;
    }
    return false;
  }

  Future<bool> switchServer(
    String id, {
    List<VpnServerProfile>? profiles,
  }) async {
    if (state.isConnecting) {
      throw StateError('Дождитесь завершения текущего подключения');
    }

    final catalog = profiles ?? await loadServerProfiles();
    final entry = catalog.firstWhere(
      (profile) => profile.id == id,
      orElse: () => throw StateError('Неизвестный сервер: $id'),
    );
    if (!entry.supported) {
      throw StateError(
        entry.unsupportedReason ??
            'Этот сервер пока нельзя запустить в приложении',
      );
    }

    if (id == state.preferredServerId) {
      state = state.copyWith(
        serverName: entry.name,
        serverCountryCode: entry.countryCode,
      );
      return false;
    }

    final wasConnected = state.isConnected;
    await _setPreferredServer(id);
    state = state.copyWith(
      preferredServerId: id,
      serverName: entry.name,
      serverCountryCode: entry.countryCode,
    );

    if (wasConnected) {
      await stop();
      await Future.delayed(const Duration(milliseconds: 1500));
      _lastConfigForReconnect = null;
      _lastServerNameForReconnect = null;
      await start();
      return true;
    }
    return false;
  }

  /// Текущий preferred protocol id (для UI active-state). Async чтобы не
  /// блокировать build на SharedPreferences.
  Future<String> get preferredProtocol => _getPreferredProtocol();

  Future<String> get preferredServer => _getPreferredServer();

  String _humanizeError(Object e) {
    // ignore: avoid_print
    print('[Pyrita-VPN] _humanizeError input: ${e.runtimeType}: $e');
    if (e is ApiException) return e.message;
    if (e is StateError) return e.message;
    if (e is DioException) return 'Сеть недоступна. Проверьте соединение.';
    if (e is TimeoutException) {
      return e.message ?? 'Превышено время ожидания.';
    }
    return 'Не удалось подключиться: $e';
  }
}

/// Singleton-провайдер для использования в UI:
///
///     final status = ref.watch(vpnControllerProvider);
///     ref.read(vpnControllerProvider.notifier).start();
final vpnControllerProvider =
    StateNotifierProvider<VpnController, PyritaVpnStatus>(
  (ref) => VpnController(),
);
