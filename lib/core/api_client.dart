import 'package:dio/dio.dart';
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
      final errorMsg =
          (body is Map && body["error"] is String) ? body["error"] as String : null;
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
  }) async {
    try {
      final res = await _dio.post(
        "/api/register",
        data: {"email": email, "password": password, "accept": true},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      if (res.statusCode == 200) {
        await AuthStorage.setCachedEmail(email);
        return;
      }
      final body = res.data;
      final errorMsg =
          (body is Map && body["error"] is String) ? body["error"] as String : null;
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
  /// на CryptoCloud pay-page. Caller открывает URL в Chrome Custom Tab.
  ///
  /// Если BILLING_ENABLED=0 на сервере → 404. Caller должен handle.
  Future<({int paymentId, String redirectUrl})> createCheckout(String planId) async {
    try {
      final res = await _dio.post(
        "/api/checkout/create",
        data: {"plan_id": planId},
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
      final errorMsg =
          (body is Map && body["error"] is String) ? body["error"] as String : null;
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
      final nameValue = first.split(";").first.trim();
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
