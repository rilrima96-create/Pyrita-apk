import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Кастомная VPN-статус notification поверх plugin's PRIORITY_MIN.
///
/// **Зачем нужна:** flutter_v2ray_client plugin создаёт foreground service
/// notification с `NotificationCompat.PRIORITY_MIN`. Samsung One UI и
/// некоторые AOSP-варианты прячут такие notifications под generic
/// "приложение выполняется" — юзер не видит ни статуса VPN, ни кнопки
/// Disconnect. Юзер не знает что VPN работает и не может его отключить
/// из шторки.
///
/// **Решение:** показываем **вторую** notification рядом с plugin'овой
/// (она остаётся live — нужна для foreground-service lifecycle). Наша:
///   * PRIORITY_LOW — visible в шторке без звука/vibrate
///   * Title: "Pyrita · Хельсинки" / "Отключено"
///   * Body: "Подключено · 25 мс" / "Ожидание сети…"
///   * Action button: "Отключить" → нативный handler в MainActivity.kt
///     route'ит intent broadcast в наш Dart side через method channel
///     → VpnController.stop()
///   * Spark icon (`drawable/ic_notification`)
///
/// **Lifecycle:**
///   1. App start → `init()` (one-time setup)
///   2. VPN connect → `showConnected(serverName, pingMs)`
///   3. VPN ping update → `updateConnected(pingMs)` (debounced)
///   4. VPN disconnect → `hide()`
///   5. Tap "Отключить" → action_disconnect intent → handled in MainActivity
class PyritaNotificationService {
  PyritaNotificationService._();
  static final instance = PyritaNotificationService._();

  static const _channelId = 'pyrita_vpn_status';
  static const _channelName = 'Pyrita VPN Status';
  static const _channelDescription =
      'Статус VPN-подключения и кнопка отключения';
  static const _notificationId = 1001;

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _pluginUnusable = false; // v0.1.14: stop spamming logs if init failed
  int? _lastPingMs;

  /// One-time setup: создаёт notification channel + registriрует
  /// action handler. Безопасно вызывать многократно.
  ///
  /// v0.1.13: ловим PlatformException(invalid_icon) который иногда
  /// бросает plugin на release-сборках Samsung (resource ic_notification
  /// в drawable folders, но plugin's getIdentifier() возвращает 0).
  /// Каждый из плагиновых call'ов wrap'нут отдельным catch чтобы partial
  /// success — например initialize() OK, createChannel fails — оставлял
  /// app в functional state. Полный fail тоже non-fatal: VpnController
  /// просто не получит disconnectRequests stream, юзер видит plugin's
  /// PRIORITY_MIN notification (стандартное Android поведение).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // v0.1.14: переключились на `ic_launcher_foreground` потому что наш
    // `ic_notification.png/.xml` по неизвестной причине не попадает в
    // release APK (aapt2 dump подтвердил отсутствие resource'а несмотря на
    // git tracking + правильные размеры PNG в drawable-*dpi). Возможно AGP
    // 8.11.1 строит resource graph и оптимизирует "unused" PNGs которые
    // не referenced ни одним XML.
    //
    // `ic_launcher_foreground` гарантированно в APK (создаётся
    // flutter_launcher_icons из assets/images/icon-launcher-foreground.png).
    // Status bar на API 21+ использует только alpha-channel — даёт
    // silhouette pyrite cube'а на белом, читается корректно.
    const androidInit = AndroidInitializationSettings('ic_launcher_foreground');
    const initSettings = InitializationSettings(android: androidInit);

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onActionTapped,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] plugin.initialize() failed (non-fatal): $e');
      _pluginUnusable = true; // v0.1.14: don't retry on every showConnected
      return; // нет смысла продолжать к createChannel — plugin не готов
    }

    try {
      // Создаём channel явно (Android 8+). Не делаем на channel'е
      // звуки/vibrate — это persistent status notification, не alert.
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.low, // = PRIORITY_LOW
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] createNotificationChannel failed (non-fatal): $e');
    }
  }

  /// Callback на нашу dart-side. Юзер тапнул "Отключить" → action ID
  /// прилетает сюда. Реальный `controller.stop()` вызывается в caller'е
  /// который подписан на `disconnectRequests` stream.
  static final _disconnectRequests = StreamController<void>.broadcast();

  /// Слушать чтобы реагировать на tap кнопки "Отключить" в notification.
  /// VpnController подписывается и вызывает stop().
  Stream<void> get disconnectRequests => _disconnectRequests.stream;

  static void _onActionTapped(NotificationResponse response) {
    if (response.actionId == 'action_disconnect') {
      _disconnectRequests.add(null);
    }
  }

  /// Показать notification «Подключено» с текущим ping'ом.
  /// v0.1.13: catch'аем PlatformException чтобы failure не break'нула
  /// VPN flow (см. comment в init()).
  Future<void> showConnected(
      {String serverName = 'Хельсинки', int? pingMs}) async {
    await init();
    if (_pluginUnusable) return; // v0.1.14: skip silently if init failed
    _lastPingMs = pingMs;
    final pingStr = pingMs != null ? ' · $pingMs мс' : '';
    try {
      await _plugin.show(
        _notificationId,
        'Pyrita · $serverName',
        'Подключено$pingStr',
        _details(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] showConnected failed (non-fatal): $e');
      _pluginUnusable = true; // если show() кидает — больше не пытаемся
    }
  }

  /// Update только если ping реально изменился (debounce шторки от
  /// frequent re-render'ов каждые 5 сек). Tolerance 5 мс — sub-noise
  /// не релевантен юзеру.
  Future<void> updatePing({
    String serverName = 'Хельсинки',
    int? pingMs,
  }) async {
    if (!_initialized || _pluginUnusable) return;
    final prev = _lastPingMs;
    if (pingMs == null && prev == null) return;
    if (pingMs != null && prev != null && (pingMs - prev).abs() < 5) return;
    _lastPingMs = pingMs;
    final pingStr = pingMs != null ? ' · $pingMs мс' : '';
    try {
      await _plugin.show(
        _notificationId,
        'Pyrita · $serverName',
        'Подключено$pingStr',
        _details(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] updatePing failed (non-fatal): $e');
      _pluginUnusable = true;
    }
  }

  /// Показать «Подключение…» — без disconnect action (юзер ещё не
  /// connected, отключать нечего; ставит pulse в idle).
  Future<void> showConnecting({String serverName = 'Хельсинки'}) async {
    await init();
    if (_pluginUnusable) return;
    _lastPingMs = null;
    try {
      await _plugin.show(
        _notificationId,
        'Pyrita · $serverName',
        'Подключение…',
        _details(includeAction: false),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] showConnecting failed (non-fatal): $e');
      _pluginUnusable = true;
    }
  }

  /// Скрыть notification полностью (VPN disconnected).
  Future<void> hide() async {
    if (!_initialized) return;
    _lastPingMs = null;
    try {
      await _plugin.cancel(_notificationId);
    } catch (e) {
      // ignore: avoid_print
      print('[PyritaNotif] hide failed (non-fatal): $e');
    }
  }

  NotificationDetails _details({bool includeAction = true}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        ongoing: true, // persistent — нельзя smahnut'ь
        autoCancel: false,
        showWhen: false,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
        icon: 'ic_launcher_foreground', // v0.1.14: см. comment в init()
        actions: includeAction
            ? <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  'action_disconnect',
                  'Отключить',
                  cancelNotification: false,
                  // v0.1.17: showsUserInterface=true НЕОБХОДИМ чтобы
                  // tap из background panel'а сработал. С false-ом
                  // flutter_local_notifications routes action callback
                  // ТОЛЬКО в foreground isolate (onDidReceiveNotification-
                  // Response). Если app свёрнут — callback в background
                  // isolate, которого мы не зарегали → tap молча теряется.
                  //
                  // С true=, тап брингает activity в foreground (через
                  // standard launch intent), потом foreground callback
                  // фиренёт _onActionTapped → emit'нёт в disconnectRequests
                  // stream → VpnController.stop() actually runs.
                  showsUserInterface: true,
                ),
              ]
            : <AndroidNotificationAction>[],
      ),
    );
  }

  /// Для debugging — print через `print`, не debugPrint (release-visible).
  // ignore: avoid_print, unused_element
  void _log(String msg) => print('[PyritaNotif] $msg');

  /// Освобождаем подписки. Вызывается в VpnController.dispose() (хотя
  /// app rarely disposes — это singleton).
  // ignore: unused_element
  void dispose() {
    _disconnectRequests.close();
  }
}

// Внутреннее использование: `kDebugMode` для conditional logging без
// предупреждений analyzer'а. Не публичный API.
// ignore: unused_element
bool get _debug => kDebugMode;
