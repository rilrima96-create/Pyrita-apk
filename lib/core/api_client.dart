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
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final setCookie = response.headers["set-cookie"];
    if (setCookie != null && setCookie.isNotEmpty) {
      // iron-session ставит cookie вида `pyrita_session=...; Path=/; HttpOnly; ...`
      // Нам нужна только name=value часть для re-attach при следующем запросе.
      // Берём первую cookie из списка — у нас только одна session-cookie.
      final first = setCookie.first;
      final nameValue = first.split(";").first.trim();
      AuthStorage.setSessionCookie(nameValue);
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
