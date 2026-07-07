import 'package:dio/dio.dart';
import 'auth_cookie_policy.dart';
import 'auth_storage.dart';

/// Singleton-doer для всех HTTP-запросов к api.pyrita.com.
///
/// Под капотом — Dio + cookie-jar (через interceptor'ы, потому что
/// iron-session использует HttpOnly cookies). Каждый запрос:
///   1. Auto-attach session-cookie из AuthStorage (если есть)
///   2. Если ответ Set-Cookie — обновить в AuthStorage
///   3. Network errors превращаем в типизированные ApiException'ы
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // Не follow redirects automatically — мы хотим знать что 303 = success
      // (например для /api/auth/confirm-email).
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
    ));

    _dio.interceptors.add(_AuthCookieInterceptor());
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;

  // TODO: вынести в env когда добавим разработческий / staging env'ы.
  // Сейчас прод-хардкод.
  static const _baseUrl = "https://api.pyrita.com";

  // ──────────────────────────────────────────────────────────────────────
  // Auth endpoints
  // ──────────────────────────────────────────────────────────────────────

  /// POST /api/login. На success → server ставит iron-session cookie
  /// (handled by _AuthCookieInterceptor). Возвращает true на 200.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        "/api/login",
        data: {"email": email, "password": password},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      if (res.statusCode == 200) {
        await AuthStorage.setCachedEmail(email);
        return true;
      }
      final body = res.data;
      final errorMsg = (body is Map && body["error"] is String)
          ? body["error"] as String
          : null;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: errorMsg ?? "Ошибка входа",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me. Возвращает текущего юзера + subscription_url +
  /// subscription_status. Если не залогинен — 401 (бросаем ApiException).
  Future<Map<String, dynamic>> getMe() async {
    try {
      final res = await _dio.get("/api/me");
      if (res.statusCode == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось получить данные аккаунта",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/proxy-config. Возвращает short-lived credentials для
  /// browser-proxy edge, но авторизация идёт обычной app session-cookie.
  Future<Map<String, dynamic>> getProxyConfig({String? locationId}) async {
    try {
      final res = await _dio.get(
        "/api/me/proxy-config",
        queryParameters: {
          if (locationId != null && locationId.trim().isNotEmpty)
            "location": locationId.trim(),
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      final body = res.data;
      final errorMsg = (body is Map && body["error"] is String)
          ? body["error"] as String
          : null;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: errorMsg ?? "Не удалось получить прокси-сервер",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/logout. Серверная сессия завершается + клиентский session
  /// cookie очищается. Возвращает true даже на ошибку (от юзера точка
  /// зрения — он "вышел").
  Future<void> logout() async {
    try {
      await _dio.post("/api/logout");
    } catch (_) {
      // Игнорируем — клиентский clearAll() мы всё равно сделаем
    }
    await AuthStorage.clearAll();
  }

  /// POST /api/register. Создаёт юзера + сразу логинит (session-cookie
  /// в Set-Cookie). `accept` всегда true — экран должен иметь обязательный
  /// checkbox, без него не отправляем запрос.
  Future<void> register({
    required String email,
    required String password,
    String? displayName,
    String? refCode,
  }) async {
    try {
      final res = await _dio.post(
        "/api/register",
        data: {
          "email": email,
          "password": password,
          "accept": true,
          if (displayName != null && displayName.trim().isNotEmpty)
            "display_name": displayName.trim(),
          if (refCode != null && refCode.trim().isNotEmpty)
            "ref": refCode.trim(),
        },
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      if (res.statusCode == 200) {
        await AuthStorage.setCachedEmail(email);
        return;
      }
      final body = res.data;
      final errorMsg = (body is Map && body["error"] is String)
          ? body["error"] as String
          : null;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: errorMsg ?? "Не удалось зарегистрироваться",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/auth/request-password-reset. Сервер privacy-by-design
  /// возвращает 200 даже для несуществующих email'ов.
  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post(
        "/api/auth/request-password-reset",
        data: {"email": email},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PATCH /api/me/newsletter. Включает/выключает рассылки.
  Future<void> setNewsletterOptIn(bool optIn) async {
    try {
      final res = await _dio.patch(
        "/api/me/newsletter",
        data: {"opt_in": optIn},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      if (res.statusCode == 200) return;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось обновить настройку",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/auth/resend-confirmation. Re-send confirmation email.
  /// 409 = already confirmed, 429 = rate-limited.
  Future<void> resendEmailConfirmation() async {
    try {
      final res = await _dio.post("/api/auth/resend-confirmation");
      if (res.statusCode == 200) return;
      if (res.statusCode == 409) {
        throw ApiException(
          statusCode: 409,
          message: "Email уже подтверждён",
        );
      }
      if (res.statusCode == 429) {
        throw ApiException(
          statusCode: 429,
          message: "Слишком часто. Попробуйте через минуту.",
        );
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось отправить письмо",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/checkout/create. Создаёт invoice + возвращает redirect URL
  /// на pay-page провайдера. Caller открывает URL в Chrome Custom Tab.
  ///
  /// `planId` — один из 'pro-1m', 'pro-3m', 'pro-6m', 'pro-12m',
  /// 'max-1m', 'max-3m', 'max-6m', 'max-12m' (3-tier 2026-05-15
  /// migration). Legacy '1m'/'3m'/'6m'/'12m' тоже принимаются — backend
  /// маппит их в pro-*. Phase E удалит legacy.
  ///
  /// `provider` — 'cryptocloud' (default) или 'lava'.
  ///   * cryptocloud — крипта (USDT/BTC/etc), без РФ-карт
  ///   * lava — СБП/карты, удобнее для РФ-юзеров
  ///
  /// Если BILLING_ENABLED=0 на сервере → 404. Caller должен handle.
  Future<({int paymentId, String redirectUrl})> createCheckout(
    String planId, {
    String provider = 'lava',
  }) async {
    try {
      final res = await _dio.post(
        "/api/checkout/create",
        data: {"plan_id": planId, "provider": provider},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      if (res.statusCode == 404) {
        throw ApiException(
          statusCode: 404,
          message: "Оплата временно недоступна. Попробуйте позже.",
        );
      }
      if (res.statusCode == 200 && res.data is Map) {
        final m = res.data as Map;
        final paymentId = m["payment_id"] as int?;
        final redirectUrl = m["redirect_url"] as String?;
        if (paymentId != null && redirectUrl != null) {
          return (paymentId: paymentId, redirectUrl: redirectUrl);
        }
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось создать счёт",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /api/me. Удаляет аккаунт. Идемпотентно (повторный delete на
  /// уже-удалённый возвращает 200/ok).
  Future<void> deleteAccount() async {
    try {
      final res = await _dio.delete("/api/me");
      if (res.statusCode == 200) {
        await AuthStorage.clearAll();
        return;
      }
      final body = res.data;
      final errorMsg = (body is Map && body["error"] is String)
          ? body["error"] as String
          : null;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: errorMsg ?? "Не удалось удалить аккаунт",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /api/me/regenerate-sub. Ротирует subscription token (если юзер
  /// думает что URL утёк).
  Future<String> regenerateSubscription() async {
    try {
      final res = await _dio.post("/api/me/regenerate-sub");
      if (res.statusCode == 200 && res.data is Map) {
        final url = (res.data as Map)["subscription_url"] as String?;
        if (url != null) return url;
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось перевыпустить ссылку",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/protocols. Список VPN-протоколов которые раздаёт Pyrita
  /// через subscription URL. Phase A — read-only display; Phase C будет
  /// позволять переключать active.
  Future<List<ProtocolInfo>> getProtocols() async {
    try {
      final res = await _dio.get("/api/me/protocols");
      if (res.statusCode == 200 && res.data is Map) {
        final raw = (res.data as Map)["protocols"];
        if (raw is! List) return const [];
        return raw
            .whereType<Map>()
            .map((m) => ProtocolInfo.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось загрузить список протоколов",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/referral. Реферальный код юзера + статистика приведённых.
  /// Код lazy-генерируется на сервере при первом запросе — стабильный после.
  Future<ReferralData> getReferral() async {
    try {
      final res = await _dio.get("/api/me/referral");
      if (res.statusCode == 200 && res.data is Map) {
        return ReferralData.fromJson(
            Map<String, dynamic>.from(res.data as Map));
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось загрузить реферальную программу",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/devices. Список устройств юзера + лимит (для counter «3/5»).
  Future<DeviceListResult> getDevices() async {
    try {
      final res = await _dio.get("/api/me/devices");
      if (res.statusCode == 200 && res.data is Map) {
        final m = Map<String, dynamic>.from(res.data as Map);
        final raw = m['devices'];
        final devices = raw is List
            ? raw
                .whereType<Map>()
                .map(
                    (e) => DeviceSession.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : <DeviceSession>[];
        final limit = (m['limit'] as num?)?.toInt() ?? 5;
        return DeviceListResult(devices: devices, limit: limit);
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось загрузить устройства",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /api/me/devices?id=<n>. «Забыть» устройство из списка.
  Future<void> forgetDevice(int id) async {
    try {
      final res =
          await _dio.delete("/api/me/devices", queryParameters: {"id": id});
      if (res.statusCode == 200) return;
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось забыть устройство",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/stats. Usage статистика юзера: трафик (Marzban), часы
  /// онлайн (Phase C), заблокированные угрозы (Phase C). null-значения
  /// — нормально, Account показывает «—».
  Future<UsageStats> getStats() async {
    try {
      final res = await _dio.get("/api/me/stats");
      if (res.statusCode == 200 && res.data is Map) {
        return UsageStats.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось загрузить статистику",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /api/me/payments. История последних successful payments юзера.
  /// Возвращает до 10 записей, отсортированных по paid_at DESC. Pending/
  /// failed/expired/refunded не возвращаются — серверная фильтрация.
  Future<List<PaymentRecord>> getPayments() async {
    try {
      final res = await _dio.get("/api/me/payments");
      if (res.statusCode == 200 && res.data is Map) {
        final raw = (res.data as Map)["payments"];
        if (raw is! List) return const [];
        return raw
            .whereType<Map>()
            .map((m) => PaymentRecord.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      throw ApiException(
        statusCode: res.statusCode ?? -1,
        message: "Не удалось загрузить историю платежей",
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Usage stats juzera для Account-экрана. Поля nullable — backend может
/// вернуть null когда данные ещё не собраны (Phase C для online/threats)
/// или Marzban лежит. Flutter рендерит null как «—».
class UsageStats {
  const UsageStats({
    this.trafficUsedGb,
    this.trafficLimitGb,
    this.onlineHours,
    this.threatsBlocked,
  });

  final double? trafficUsedGb;

  /// null = безлимит (или Marzban не вернул). UI показывает «без лимита».
  final double? trafficLimitGb;

  /// TODO Phase C: sing-box stats. Сейчас всегда null.
  final int? onlineHours;

  /// TODO Phase C: sing-box geosite:category-ads-all counter. Сейчас null.
  final int? threatsBlocked;

  factory UsageStats.fromJson(Map<String, dynamic> m) => UsageStats(
        trafficUsedGb: (m['traffic_used_gb'] as num?)?.toDouble(),
        trafficLimitGb: (m['traffic_limit_gb'] as num?)?.toDouble(),
        onlineHours: (m['online_hours'] as num?)?.toInt(),
        threatsBlocked: (m['threats_blocked'] as num?)?.toInt(),
      );
}

/// Информация об одном VPN-протоколе доступном на Pyrita-сервере.
class ProtocolInfo {
  const ProtocolInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.active,
    required this.primary,
    required this.available,
  });

  /// Stable id: 'reality' / 'hysteria2' / 'tuic' / 'ss2022' / 'xhttp'.
  final String id;

  /// Human-friendly: «VLESS Reality», «Hysteria 2», etc.
  final String name;

  /// Краткое объяснение зачем этот протокол.
  final String description;

  /// Phase A: совпадает с `primary` (sing-box ещё не интегрирован).
  /// Phase C: реально активный outbound во встроенном клиенте.
  final bool active;

  /// Протокол по умолчанию (VLESS Reality всегда).
  final bool primary;

  /// Сконфигурирован на сервере (env'ы заполнены) — попадает в subscription URL.
  final bool available;

  factory ProtocolInfo.fromJson(Map<String, dynamic> m) => ProtocolInfo(
        id: m['id'] as String,
        name: m['name'] as String,
        description: (m['description'] as String?) ?? '',
        active: m['active'] as bool? ?? false,
        primary: m['primary'] as bool? ?? false,
        available: m['available'] as bool? ?? false,
      );
}

/// Реферальная программа: код юзера + публичный URL + статистика.
class ReferralData {
  const ReferralData({
    required this.code,
    required this.url,
    required this.invited,
    required this.paid,
    required this.daysEarned,
  });

  /// 8-character stable код. Генерится lazy backend'ом, после remembered.
  final String code;

  /// Готовый URL для шеринга: `pyrita.com/r/<code>`.
  final String url;

  /// Сколько юзеров пришло по этому коду (включая trial-only, ни разу не платили).
  final int invited;

  /// Сколько из приглашённых хотя бы раз оплатили.
  final int paid;

  /// Сколько бонусных дней начислено на текущий момент.
  final int daysEarned;

  factory ReferralData.fromJson(Map<String, dynamic> m) {
    final stats = (m['stats'] as Map?) ?? const {};
    return ReferralData(
      code: m['code'] as String,
      url: m['url'] as String,
      invited: (stats['invited'] as num?)?.toInt() ?? 0,
      paid: (stats['paid'] as num?)?.toInt() ?? 0,
      daysEarned: (stats['days_earned'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Информация об одном клиентском устройстве юзера (Pyrita-app, Hiddify, etc).
/// UPSERT'ится backend'ом на каждом /api/me и /api/sub/<token> request'е.
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.label,
    required this.lastSeenAt,
    required this.firstSeenAt,
  });

  final int id;

  /// Human-readable строка от parseUserAgentLabel на сервере.
  /// null = не удалось распарсить UA (показать «Неизвестное» в UI).
  final String? label;

  /// Unix ms последнего request'а с этого устройства.
  final int lastSeenAt;

  /// Unix ms первого появления — для FuturePhaseC tooltip («впервые …»).
  final int firstSeenAt;

  factory DeviceSession.fromJson(Map<String, dynamic> m) => DeviceSession(
        id: (m['id'] as num).toInt(),
        label: m['label'] as String?,
        lastSeenAt: (m['last_seen_at'] as num).toInt(),
        firstSeenAt: (m['first_seen_at'] as num).toInt(),
      );
}

/// Результат `getDevices()` — список + лимит (для counter «3 / 5» в UI).
class DeviceListResult {
  const DeviceListResult({required this.devices, required this.limit});
  final List<DeviceSession> devices;
  final int limit;
}

/// История одной успешной оплаты — рендерится в Account → «История платежей».
///
/// `id` намеренно не передаётся с backend'а — это enumeration-vector
/// (юзер с двумя оплатами видел бы как растёт общий counter платежей
/// между его покупками). UI-key строится по `paidAt` (unique-per-user
/// до микросекунд).
class PaymentRecord {
  const PaymentRecord({
    required this.planId,
    required this.amountRub,
    required this.paidAt,
    this.daysGranted,
  });

  /// '1m' / '3m' / '6m' / '12m' — для маппинга в человеческое название.
  final String planId;

  /// Сумма в рублях (целое — копеек нет в текущей тарифной сетке).
  final int amountRub;

  /// Unix ms когда подтвердилась оплата.
  final int paidAt;

  /// На сколько дней продлили подписку. NULL если ещё не finalize'ено,
  /// но getPayments() возвращает только paid → на практике всегда != null.
  final int? daysGranted;

  factory PaymentRecord.fromJson(Map<String, dynamic> m) => PaymentRecord(
        planId: m['plan_id'] as String,
        amountRub: (m['amount_rub'] as num).toInt(),
        paidAt: (m['paid_at'] as num).toInt(),
        daysGranted: (m['days_granted'] as num?)?.toInt(),
      );
}

/// Interceptor — добавляет saved session-cookie в каждый запрос +
/// сохраняет Set-Cookie из response'ов.
class _AuthCookieInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final cookie = await AuthStorage.getSessionCookie();
    if (cookie != null && cookie.isNotEmpty) {
      options.headers["Cookie"] = cookie;
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final setCookie = response.headers["set-cookie"];
    if (setCookie != null && setCookie.isNotEmpty) {
      // iron-session ставит cookie вида `pyrita_session=...; Path=/; HttpOnly; ...`
      // Нам нужна только name=value часть для re-attach при следующем запросе.
      // Берём первую cookie из списка — у нас только одна session-cookie.
      final first = setCookie.first;
      final nameValue = sessionCookieValueForStorage(first);
      if (nameValue == null) {
        await AuthStorage.clearSession();
        handler.next(response);
        return;
      }
      // ВАЖНО: await — без него race condition. Если юзер быстро шлёт второй
      // запрос (login → getMe), interceptor может ещё не сохранить cookie
      // → второй запрос идёт без auth → 401 → юзера выкидывает на login.
      await AuthStorage.setSessionCookie(nameValue);
    }
    handler.next(response);
  }
}

/// Типизированный wrapper над сетевыми ошибками. Унифицирует:
///   * Dio timeout / connection-refused → ApiException(statusCode=0)
///   * 4xx/5xx с error-body → ApiException(statusCode + parsed message)
///   * Неожиданные shape ответа → ApiException(generic)
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  /// 0 = network error (no response), 1-99 = invalid, 100-599 = HTTP.
  bool get isNetwork => statusCode == 0;

  factory ApiException.fromDio(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException(
        statusCode: 0,
        message: "Не удалось подключиться к серверу. Проверьте соединение.",
      );
    }
    final status = e.response?.statusCode ?? -1;
    String? msg;
    if (e.response?.data is Map) {
      final m = e.response!.data as Map;
      if (m["error"] is String) msg = m["error"] as String;
    }
    return ApiException(
      statusCode: status,
      message: msg ?? "Ошибка сервера ($status)",
    );
  }

  @override
  String toString() => "ApiException($statusCode): $message";
}
