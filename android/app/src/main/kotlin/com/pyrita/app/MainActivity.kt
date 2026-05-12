package com.pyrita.app

import io.flutter.embedding.android.FlutterActivity

/**
 * Базовый FlutterActivity. На Phase C сюда добавится MethodChannel
 * для коммуникации с PyritaVpnService (start/stop/state).
 *
 * Зачем kotlin, не java: Flutter create по умолчанию генерирует kotlin
 * с Android Gradle Plugin 8+. Менять не нужно — наш код всё равно
 * вызывается через MethodChannel из Dart.
 */
class MainActivity : FlutterActivity()
