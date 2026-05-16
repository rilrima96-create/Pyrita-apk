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
    this.preferredProtocolId = 'reality',
  });

  final PyritaVpnState state;

  /// Текущий preferred protocol id (см. `/api/me/protocols` для catalog).
  /// Default 'reality'. Меняется через `VpnController.switchProtocol()`.
  /// UI использует чтобы отрисовать который protocol реально active в
  /// Pyrita-app — backend всегда говорит "Reality primary", это поле —
  /// клиентский override.
  final String preferredProtocolId;

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
    String? preferredProtocolId,
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
      preferredProtocolId: preferredProtocolId ?? this.preferredProtocolId,
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
  static const _defaultProtocol = 'reality';

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
    'domain:vk.com', 'domain:vk.ru', 'domain:vkontakte.ru', 'domain:vkuseraudio.net',
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

    // Hydrate preferredProtocolId из SharedPreferences. До первой записи
    // (юзер не switch'ал protocol) — default 'reality'.
    final preferred = await _getPreferredProtocol();
    if (mounted) {
      state = state.copyWith(preferredProtocolId: preferred);
    }
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
        // Plugin default — https://google.com/generate_204 — блокирован
        // RKN, через VPN handshake может fail. Используем Cloudflare
        // (нейтральный, не в RU bypass'е, идёт через tunnel).
        final ms = await _v2ray.getConnectedServerDelay(
          url: 'https://cloudflare.com/cdn-cgi/trace',
        );
        if (!mounted || !state.isConnected) return;
        // Plugin возвращает -1 при timeout / failure. Не пишем такие в
        // state — UI рендерит '—' если pingMs null, что точнее чем
        // показывать -1.
        if (ms <= 0) {
          debugPrint('[VPN] ping returned $ms (timeout or error)');
          return;
        }
        debugPrint('[VPN] ping=$ms ms');
        state = state.copyWith(serverPingMs: ms);
      } catch (e) {
        debugPrint('[VPN] ping exception: $e');
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

  /// Скачивает sub URL и возвращает плоский список parsable URL'ов.
  /// Reusable helper — используется как _buildXrayConfig (полный config),
  /// так и switchProtocol (pre-check что preferred protocol реально в
  /// подписке, иначе backend кэширует stale `available=true` flag).
  Future<List<String>> _fetchSubscriptionUrls(String subUrl) async {
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
    return urls;
  }

  /// Скачивает Pyrita sub URL, выбирает primary URL (с учётом
  /// `preferred_protocol`), строит JSON-config для Xray-core с включёнными
  /// правилами RU-bypass.
  ///
  /// Pyrita backend (Marzban) возвращает либо base64-encoded плоский
  /// список URL'ов (по одной строке), либо plain text. Поддерживаем оба.
  Future<String> _buildXrayConfig(String subUrl) async {
    final urls = await _fetchSubscriptionUrls(subUrl);

    final preferred = await _getPreferredProtocol();
    final vlessUrl = _pickPrimaryUrl(urls, preferred: preferred);

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
      'rules': [
        {
          'type': 'field',
          'network': 'udp',
          'port': '443',
          'outboundTag': 'blackhole',
        },
        {
          'type': 'field',
          'domain': _ruDomainsBypass,
          'outboundTag': 'direct',
        },
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

  /// Выбирает primary URL из списка с учётом preferred protocol.
  ///
  /// Phase D: реально parsable плагином → vless / vmess / trojan / ss /
  /// socks. Hy2 / TUIC требуют custom parser (Phase E).
  ///
  /// Алгоритм:
  ///   1. Если `preferred` указан и matching URL есть в подписке —
  ///      берём его (например 'xhttp' → vless+type=xhttp URL).
  ///   2. Если preferred недоступен (или 'reality' = default) →
  ///      приоритет: VLESS Reality > VLESS XHTTP > любой VLESS.
  ///   3. Если VLESS нет вовсе → fallback на любой parseable
  ///      (vmess/trojan/ss/socks) — это «recovery mode» если backend
  ///      сменил основной протокол.
  String _pickPrimaryUrl(List<String> urls, {String preferred = _defaultProtocol}) {
    // Step 1: попробовать matching preferred (если не default).
    if (preferred != _defaultProtocol) {
      final matched = _findByPreferred(urls, preferred);
      if (matched != null) return matched;
      // Preferred unavailable — fallback на стандартный порядок.
    }

    // Step 2: VLESS Reality (default primary).
    final reality = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('security=reality'),
      orElse: () => '',
    );
    if (reality.isNotEmpty) return reality;

    // Step 3: VLESS XHTTP.
    final xhttp = urls.firstWhere(
      (u) => u.startsWith('vless://') && u.contains('type=xhttp'),
      orElse: () => '',
    );
    if (xhttp.isNotEmpty) return xhttp;

    // Step 4: Любой VLESS.
    final anyVless = urls.firstWhere(
      (u) => u.startsWith('vless://'),
      orElse: () => '',
    );
    if (anyVless.isNotEmpty) return anyVless;

    // Step 5: Recovery mode — любой parseable URL (если backend сменил
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
        case 'tuic':
          // Custom protocols — plugin их не парсит. Возвращаем null,
          // caller fallback'нет на default. UI слой должен ДО switchProtocol
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
    // socks. Hy2 / TUIC требуют custom parser (Phase E). Блокируем
    // переключение чтобы не получить crash в _buildXrayConfig.
    const parseable = {'reality', 'xhttp', 'ss2022'};
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
      final urls = await _fetchSubscriptionUrls(subUrl);
      final matched = _findByPreferred(urls, id);
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

  /// Текущий preferred protocol id (для UI active-state). Async чтобы не
  /// блокировать build на SharedPreferences.
  Future<String> get preferredProtocol => _getPreferredProtocol();

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
