import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Native method channel для APK install intent. open_filex и share_plus
/// оба silent fail'или на Android 14+ Samsung One UI — юзер видел «моргнула
/// и выключилась» без installer dialog'а. Свой native intent в
/// MainActivity.installApk с FLAG_ACTIVITY_NEW_TASK +
/// FLAG_GRANT_READ_URI_PERMISSION + кастомный FileProvider работает
/// надёжно.
const _installerChannel = MethodChannel('com.pyrita.pyrita_app/installer');

/// `_log` swallow'ится в release-APK. Используем `print` через
/// Zone-redirect — он реально пишет в logcat (filterable как 'flutter:I').
void _log(String msg) {
  // ignore: avoid_print
  print('[PyritaUpdate] $msg');
}

/// Информация о доступном update'е, возвращаемая `UpdateService.checkForUpdate()`.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    required this.assetUrl,
    required this.assetSizeBytes,
    required this.releaseNotes,
  });

  /// Текущая version из pubspec.yaml (e.g. '0.1.0').
  final String currentVersion;

  /// Latest tag без префикса 'v' (e.g. '0.1.0').
  final String latestVersion;

  /// Original tag_name (e.g. 'v0.1.0') — для display.
  final String tagName;

  /// HTML URL страницы скачивания. Fallback если download fails.
  final String releaseUrl;

  /// Direct download URL для arm64 APK.
  final String assetUrl;

  /// Размер APK в байтах (для UI progress).
  final int assetSizeBytes;

  /// Markdown-текст из release notes. Если пусто — show generic.
  final String releaseNotes;

  bool get hasUpdate => _isLater(latestVersion, currentVersion);

  /// Compare semver-like versions. `a > b` → true.
  /// Простое сравнение по dot-separated integers. Не handles pre-release tags
  /// (alpha/beta) — для наших целей достаточно.
  static bool _isLater(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    while (aParts.length < maxLen) {
      aParts.add(0);
    }
    while (bParts.length < maxLen) {
      bParts.add(0);
    }
    for (var i = 0; i < maxLen; i++) {
      if (aParts[i] > bParts[i]) return true;
      if (aParts[i] < bParts[i]) return false;
    }
    return false;
  }
}

/// Progress event для downloadApk stream.
@immutable
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});
  final int received;
  final int total;
  double get fraction => total > 0 ? received / total : 0;
  int get percent => (fraction * 100).round();
}

/// Сервис проверки и установки обновлений приложения.
///
/// Логика:
///   1. `checkForUpdate()` — GET https://api.pyrita.com/api/release/latest.
///      Это self-hosted release endpoint на Pyrita, совместимый с subset'ом
///      GitHub Releases API. Распарсить tag_name, найти
///      `app-arm64-v8a-release.apk` asset.
///   2. `downloadApk(info, onProgress)` — Dio download в getExternalCacheDir()
///      (внешний кэш auto-cleanup'ится Android'ом, и FileProvider может
///      его читать).
///   3. `installApk(file)` — `open_filex.open()` → Android ACTION_VIEW
///      intent с MIME application/vnd.android.package-archive → юзер
///      видит system installer.
///
/// Замечания:
///   - Debug APK (current dev cycle) и Release APK (из CI release) имеют
///     разные signing keys → install fails с INSTALL_FAILED_UPDATE_
///     INCOMPATIBLE. UI должен warn'ить юзера если он на debug-сборке.
///   - Android 8+ требует юзер'а grant'нуть REQUEST_INSTALL_PACKAGES
///     permission один раз (system dialog «Allow Pyrita to install
///     unknown apps?»).
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  @visibleForTesting
  static const releaseEndpoint = 'https://api.pyrita.com/api/release/latest';

  static const _githubFallbackReleaseEndpoint =
      'https://api.github.com/repos/rilrima96-create/Pyrita-apk/releases/latest';

  static const _releaseEndpoints = [
    releaseEndpoint,
    _githubFallbackReleaseEndpoint,
  ];

  /// Имя ABI-specific APK asset, который мы качаем. Соответствует
  /// `flutter build apk --split-per-abi` output. arm64-v8a покрывает
  /// 99% Android 10+ devices. Если нужен fallback на armeabi-v7a —
  /// меняем эту константу.
  @visibleForTesting
  static const targetAbiAsset = 'app-arm64-v8a-release.apk';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'Pyrita-app/update-check',
    },
  ));

  @visibleForTesting
  static UpdateInfo? parseReleasePayload({
    required String currentVersion,
    required Map<String, dynamic> data,
  }) {
    final tagName = data['tag_name'] as String? ?? '';
    final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    final releaseUrl = data['html_url'] as String? ?? '';
    final body = data['body'] as String? ?? '';

    final assets = (data['assets'] as List?) ?? const [];
    Map<dynamic, dynamic>? asset;
    for (final candidate in assets) {
      if (candidate is Map && candidate['name'] == targetAbiAsset) {
        asset = candidate;
        break;
      }
    }
    if (asset == null) {
      _log('[Update] no $targetAbiAsset asset in release $tagName');
      return null;
    }
    final assetUrl = asset['browser_download_url'] as String? ?? '';
    final assetSize = (asset['size'] as num?)?.toInt() ?? 0;
    if (tagName.isEmpty || assetUrl.isEmpty) return null;

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tagName: tagName,
      releaseUrl: releaseUrl,
      assetUrl: assetUrl,
      assetSizeBytes: assetSize,
      releaseNotes: body,
    );
  }

  /// Проверяет latest release. Возвращает `null` если сетевая ошибка
  /// или release payload не содержит нужный APK asset.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;

      for (final endpoint in _releaseEndpoints) {
        try {
          final resp = await _dio.get<Map<String, dynamic>>(endpoint);
          final data = resp.data;
          if (data == null) continue;

          final info = parseReleasePayload(
            currentVersion: currentVersion,
            data: data,
          );
          if (info == null) continue;

          _log(
            '[Update] endpoint=$endpoint current=$currentVersion '
            'latest=${info.latestVersion} hasUpdate=${info.hasUpdate}',
          );
          return info;
        } on DioException catch (e) {
          _log('[Update] check failed at $endpoint: ${e.message}');
        }
      }
      return null;
    } on DioException catch (e) {
      _log('[Update] check failed: ${e.message}');
      return null;
    } catch (e) {
      _log('[Update] check exception: $e');
      return null;
    }
  }

  /// Скачивает APK в external cache dir. Стримит прогресс через
  /// `onProgress(received, total)` callback. Возвращает File готовый
  /// для install'а.
  Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(UpdateProgress) onProgress,
  }) async {
    final cacheDir = await getExternalCacheDirectories();
    if (cacheDir == null || cacheDir.isEmpty) {
      throw StateError('Не удалось получить external cache dir');
    }
    final apkFile = File('${cacheDir.first.path}/pyrita-${info.latestVersion}.apk');

    // Если APK уже скачан и матчит размер — skip re-download.
    if (apkFile.existsSync() && apkFile.lengthSync() == info.assetSizeBytes) {
      _log('[Update] reusing cached ${apkFile.path}');
      onProgress(UpdateProgress(
        received: info.assetSizeBytes,
        total: info.assetSizeBytes,
      ));
      return apkFile;
    }

    _log('[Update] downloading ${info.assetUrl} → ${apkFile.path}');
    try {
      // followRedirects=true чтобы пройти 302 на release-assets.
      // githubusercontent.com (S3-Blob). validateStatus loose (<400)
      // на случай 206 Partial Content от range download'ов.
      await _dio.download(
        info.assetUrl,
        apkFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(UpdateProgress(received: received, total: total));
          }
        },
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(minutes: 5),
          headers: {
            'Accept': 'application/octet-stream',
            'User-Agent': 'Pyrita-app/update-download',
          },
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      _log('[Update] download complete, ${apkFile.lengthSync()} bytes');
      return apkFile;
    } on DioException catch (e) {
      _log('[Update] download failed: type=${e.type} message=${e.message}');
      // Удаляем недокачанный файл чтобы next try не reuse'ил bad cache.
      if (apkFile.existsSync()) {
        try {
          apkFile.deleteSync();
        } catch (_) {}
      }
      // Human-readable error чтобы юзер понял что это не «нет интернета».
      final reason = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.connectionError =>
          'Не удаётся скачать APK с сервера Pyrita. '
              'Попробуйте ещё раз или откройте страницу скачивания в браузере.',
        DioExceptionType.receiveTimeout =>
          'Соединение оборвалось во время скачивания. Попробуйте ещё раз.',
        DioExceptionType.badCertificate =>
          'Ошибка SSL-сертификата. Проверьте дату на телефоне.',
        DioExceptionType.badResponse =>
          'Сервер обновлений вернул ошибку ${e.response?.statusCode}.',
        _ => 'Сеть: ${e.message ?? "неизвестная ошибка"}',
      };
      throw StateError(reason);
    }
  }

  /// Триггерит Android system installer для скачанного APK.
  /// Юзер увидит system dialog «Установить?» и должен accept'нуть.
  ///
  /// Pre-conditions проверяемые этим методом:
  ///   1. APK файл существует
  ///   2. REQUEST_INSTALL_PACKAGES permission выдан (Android 8+, иначе
  ///      Android silent reject'ит install intent с no visible feedback)
  ///   3. OpenFilex.open returns ResultType.done (иначе throw с понятным
  ///      message'ом — какой именно бы открылся exception)
  ///
  /// Если permission не выдан → открываем system Settings page для
  /// "Install unknown apps" → юзер toggle'ит → возвращается → tap снова.
  Future<void> installApk(File apk) async {
    if (!apk.existsSync()) {
      throw StateError('APK файл не найден: ${apk.path}');
    }

    // Android 8+ REQUEST_INSTALL_PACKAGES. На <8 — auto-granted.
    // permission_handler v11+ returns isGranted=true для auto-granted на <8.
    final permStatus = await Permission.requestInstallPackages.status;
    _log('[Update] install-packages permission status: $permStatus');
    if (!permStatus.isGranted) {
      _log('[Update] requesting REQUEST_INSTALL_PACKAGES permission');
      final result = await Permission.requestInstallPackages.request();
      _log('[Update] permission request result: $result');
      if (!result.isGranted) {
        throw StateError(
          'Нужно разрешение «Установка из неизвестных источников». '
          'В открывшихся настройках Android включите Pyrita и нажмите '
          '«Обновить» ещё раз.',
        );
      }
    }

    // Sanity check: APK readable. Иногда external cache очищается
    // Android'ом между download и install.
    final size = apk.lengthSync();
    _log('[Update] APK ready: ${apk.path} size=$size bytes');
    if (size <= 0) {
      throw StateError(
        'Скачанный APK пуст. Попробуйте ещё раз.',
      );
    }

    _log('[Update] triggering native install intent…');
    try {
      final ok = await _installerChannel.invokeMethod<bool>(
        'installApk',
        {'path': apk.path},
      );
      _log('[Update] native intent returned ok=$ok');
      if (ok != true) {
        throw StateError(
          'APK файл не найден или пуст. Попробуйте ещё раз.',
        );
      }
    } on PlatformException catch (e) {
      _log('[Update] PlatformException: ${e.code} ${e.message}');
      throw StateError(
        'Не удалось открыть установщик: ${e.message ?? e.code}. '
        'Попробуйте скачать APK через браузер.',
      );
    }
  }
}
