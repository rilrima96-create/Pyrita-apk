import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage для auth-state приложения.
///
/// Backend под капотом:
///   * Android: EncryptedSharedPreferences (AES-256, Android Keystore)
///   * iOS: Keychain (когда добавим iOS)
///
/// Что храним:
///   * `session_cookie` — серверная iron-session cookie от pyrita.com.
///     Это **главный** auth-токен. Если пользователь логинится через
///     /api/login, мы получаем Set-Cookie header и сохраняем здесь.
///     При каждом запросе Dio interceptor прикрепляет его обратно.
///   * `cached_email` — последний логин email чтобы pre-fill при reopen
///     (это удобство, не сенсорное).
///
/// Что НЕ храним:
///   * Password в открытом виде. Никогда.
///   * Sub URL — он получается через `/api/me` при необходимости,
///     не нужно его дублировать.
class AuthStorage {
  AuthStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keySessionCookie = "session_cookie";
  static const _keyCachedEmail = "cached_email";

  static Future<void> setSessionCookie(String cookie) async {
    await _storage.write(key: _keySessionCookie, value: cookie);
  }

  static Future<String?> getSessionCookie() async {
    return _storage.read(key: _keySessionCookie);
  }

  static Future<void> clearSession() async {
    await _storage.delete(key: _keySessionCookie);
  }

  static Future<void> setCachedEmail(String email) async {
    await _storage.write(key: _keyCachedEmail, value: email);
  }

  static Future<String?> getCachedEmail() async {
    return _storage.read(key: _keyCachedEmail);
  }

  /// Полная очистка — logout сценарий.
  static Future<void> clearAll() async {
    await _storage.delete(key: _keySessionCookie);
    // cached_email НЕ удаляем — pre-fill на следующий логин полезен
  }
}
