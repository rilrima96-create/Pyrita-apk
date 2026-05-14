import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Состояние VPN-туннеля для UI-слоя.
///
/// Маппится из `V2RayStatus.state` (плагин даёт UPPERCASE строки):
///   * `DISCONNECTED` → `disconnected`
///   * `CONNECTING` → `connecting`
///   * `CONNECTED` → `connected`
///   * прочее → `error`
enum PyritaVpnState { disconnected, connecting, connected, error }

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
  });

  final PyritaVpnState state;

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
    String? errorMessage,
    int? serverPingMs,
  }) {
    return PyritaVpnStatus(
      state: state ?? this.state,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      duration: duration ?? this.duration,
      errorMessage: errorMessage ?? this.errorMessage,
      serverPingMs: serverPingMs ?? this.serverPingMs,
    );
  }
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

  /// Period-таймер для обновления server ping каждые 5 сек когда connected.
  Timer? _pingTimer;

  /// Subscription на connectivity_plus events. Cancel в dispose().
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// Был ли VPN активен непосредственно перед потерей сети. Это сигнал
  /// что нужен auto-reconnect когда сеть вернётся.
  bool _wasConnectedBeforeNetLoss = false;

  static const _prefKeyPermissionRequested = 'vpn_permission_requested';

  Future<void> _init() async {
    // Notification icon — используем launcher-иконку приложения. Та же
    // что в pubspec.yaml → flutter_launcher_icons → icon-b-pyrite.png.
    await _v2ray.initialize(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
  }

  void _onStatusChanged(V2RayStatus s) {
    if (!mounted) return;
    final mapped = switch (s.state.toUpperCase()) {
      'CONNECTED' => PyritaVpnState.connected,
      'CONNECTING' => PyritaVpnState.connecting,
      'DISCONNECTED' => PyritaVpnState.disconnected,
      _ => PyritaVpnState.error,
    };
    state = state.copyWith(
      state: mapped,
      uploadSpeed: s.uploadSpeed,
      downloadSpeed: s.downloadSpeed,
      uploadTotal: s.upload,
      downloadTotal: s.download,
      duration: s.duration,
      // Сбрасываем ping при не-connected state (UI рендерит '—' в idle).
      serverPingMs: mapped == PyritaVpnState.connected ? state.serverPingMs : null,
      // Очищаем error message при успешном connect.
      errorMessage: mapped == PyritaVpnState.connected ? null : state.errorMessage,
    );

    // Ping-timer работает только когда туннель активен.
    if (mapped == PyritaVpnState.connected) {
      _startPingTimer();
    } else {
      _stopPingTimer();
    }
  }

  // ─────────────────────────────── Live ping ───────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final ms = await _v2ray.getConnectedServerDelay();
        if (!mounted || !state.isConnected) return;
        state = state.copyWith(serverPingMs: ms);
      } catch (_) {
        // Timeout / measurement error — игнорим, в следующий тик попробуем.
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ─────────────────────────── Auto-reconnect ─────────────────────────────

  void _wireConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((events) {
      final hasNetwork =
          events.any((e) => e != ConnectivityResult.none);

      if (!hasNetwork) {
        // Сеть пропала. Запоминаем что туннель был активен — пригодится
        // когда сеть восстановится.
        if (state.isConnected) {
          _wasConnectedBeforeNetLoss = true;
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
        state = const PyritaVpnStatus(state: PyritaVpnState.connecting);
        await _v2ray.startV2Ray(
          remark: 'Pyrita · Хельсинки',
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
      );
      return;
    }
    if (!mounted) return;

    state = const PyritaVpnStatus(state: PyritaVpnState.connecting);
    try {
      final me = await ApiClient.instance.getMe();
      final subUrl = me['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        throw StateError('Не удалось получить subscription_url');
      }

      final config = await _buildXrayConfig(subUrl);
      _lastConfigForReconnect = config;

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
      await _v2ray.startV2Ray(
        remark: 'Pyrita · Хельсинки',
        config: config,
        proxyOnly: false,
        notificationDisconnectButtonName: 'Отключить',
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(
          'VPN-движок не ответил за 60 сек. Возможно процесс упал.',
          const Duration(seconds: 60),
        ),
      );

      // НЕ делаем premature check на state==connected. Plugin сам
      // emit'ит CONNECTED через onStatusChanged когда handshake завершится.
      // До этого state остаётся connecting (UI показывает пульсирующий
      // sonar). Если за минуту CONNECTED не пришёл — это уже network/
      // server issue, не plugin crash — юзер может сам нажать кнопку
      // «Долго подключаемся? Показать логи» для диагностики.
    } catch (e) {
      if (!mounted) return;
      state = PyritaVpnStatus(
        state: PyritaVpnState.error,
        errorMessage: _humanizeError(e),
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
        onTimeout: () => ['(getLogs timeout — plugin busy, попробуй позже)'],
      );
    } catch (_) {
      return [];
    }
  }

  /// Текущий cached config, если есть. Для debug-screen.
  String? get currentConfig => _lastConfigForReconnect;

  /// Останавливает туннель. Plugin emit'ит DISCONNECTED через callback.
  Future<void> stop() async {
    // Явный stop пользователем — отменяем потенциальный auto-reconnect.
    // Иначе сценарий: сеть пропадает → юзер тапает «отключить» → сеть
    // возвращается → tunnel сам поднимается (нежелательно).
    _wasConnectedBeforeNetLoss = false;
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {
      // Если уже остановлен или ещё не стартовал — молча игнорируем.
    }
  }

  /// Скачивает Pyrita sub URL, выбирает VLESS+Reality, строит JSON-config
  /// для Xray-core с включёнными правилами RU-bypass.
  ///
  /// Pyrita backend (Marzban) возвращает либо base64-encoded плоский
  /// список URL'ов (по одной строке), либо plain text. Поддерживаем оба.
  Future<String> _buildXrayConfig(String subUrl) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final resp = await dio.get<String>(
      subUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'User-Agent': 'Pyrita-app/Phase-C'},
      ),
    );
    final raw = (resp.data ?? '').trim();
    if (raw.isEmpty) {
      throw StateError('Подписка вернула пустой ответ');
    }

    final urls = _parseSubscriptionBody(raw);
    if (urls.isEmpty) {
      throw StateError('В подписке не найдено ни одного протокола');
    }

    final vlessUrl = _pickPrimaryUrl(urls);

    // Парсинг через factory плагина — определяет протокол по prefix.
    // Для VLESS+Reality возвращает `VlessURL` с заполненными
    // realitySettings (publicKey, shortId, fingerprint).
    final parsed = V2ray.parseFromURL(vlessUrl);

    // КРИТИЧЕСКИ ВАЖНО: используем getFullConfiguration() (метод), а не
    // fullConfiguration (raw Map). Метод дополнительно вызывает
    // removeNulls() — без этого config содержит десятки null полей
    // в outbound1/outbound2/outbound3 settings (servers: null, response: null,
    // address: null, port: null, secretKey: null, peers: null и т.п.).
    // Xray-core на parse такого JSON может вести себя undefined: ранее
    // зависал на startV2Ray() Future в pending state — обнаружено
    // на Android 16 при первом acceptance test.
    final cleanJson = parsed.getFullConfiguration();
    final configMap = jsonDecode(cleanJson) as Map<String, dynamic>;

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

    // Routing: RU bypass для приватных IP (localhost / 192.168 / 10.x).
    //
    // ВАЖНО: geosite:ru правило УБРАНО — plugin bundles geosite.dat
    // без поддержки RU-кода (Xray crash на startup с
    // 'failed to check code RU from geosite.dat > EOF'). Verified
    // через диалог-диагностику в acceptance test.
    //
    // geoip:ru тоже не используется по той же причине (geoip.dat может
    // быть несовместим). Только loopback/private + default proxy.
    //
    // Это значит yandex.ru / sberbank.ru / gosuslugi.ru пойдут ЧЕРЕЗ
    // VPN-туннель — банк может REJECT FI IP. Phase D — добавить
    // bundled свежие geo files в app assets и копировать в filesDir
    // на первом запуске.
    configMap['routing'] = <String, dynamic>{
      'domainStrategy': 'AsIs',
      'rules': [
        {
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        },
      ],
    };

    return jsonEncode(configMap);
  }

  /// Marzban sub может прийти как plain text или base64 (зависит от
  /// настроек). Пытаемся декодировать base64; если не получается —
  /// считаем что это уже plain text.
  List<String> _parseSubscriptionBody(String body) {
    String text;
    try {
      // Чистим whitespace и переносы — base64 может приходить «склеенным»
      final cleaned = body.replaceAll(RegExp(r'\s+'), '');
      text = utf8.decode(base64.decode(cleaned));
    } catch (_) {
      text = body;
    }

    return text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty &&
            (l.startsWith('vless://') ||
                l.startsWith('vmess://') ||
                l.startsWith('trojan://') ||
                l.startsWith('ss://')))
        .toList();
  }

  /// Выбирает primary URL из списка. Phase C поддерживает:
  ///   1. VLESS+Reality (highest priority — primary protocol)
  ///   2. VLESS+XHTTP — fallback на случай если backend начнёт его класть
  ///      в подписку (сейчас нет: legacy base64 не содержит xhttp URL,
  ///      Hiddify его не понимает, Pyrita backend пока его выдаёт только
  ///      через /api/me/protocols, а не в /api/sub). Branch на будущее.
  ///   3. Любой VLESS (last resort)
  ///
  /// Hysteria 2 / TUIC / SS-2022 не используем в Phase C — нет parser'а
  /// в плагине (отложено в Phase D).
  String _pickPrimaryUrl(List<String> urls) {
    // 1. VLESS Reality
    final reality = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('security=reality'),
      orElse: () => '',
    );
    if (reality.isNotEmpty) return reality;

    // 2. VLESS XHTTP
    final xhttp = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('type=xhttp'),
      orElse: () => '',
    );
    if (xhttp.isNotEmpty) return xhttp;

    // 3. Любой VLESS
    return urls.firstWhere(
      (u) => u.startsWith('vless://'),
      orElse: () => throw StateError(
        'В подписке не нашли VLESS — embedded клиент не сможет подключиться',
      ),
    );
  }

  String _humanizeError(Object e) {
    if (e is ApiException) return e.message;
    if (e is StateError) return e.message;
    if (e is DioException) return 'Сеть недоступна. Проверьте соединение.';
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
