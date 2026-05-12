import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Russian locale для intl/DateFormat. Без этого DateFormat("d MMMM",
  // "ru_RU") бросает LocaleDataException на первом render'е home screen'а
  // или settings'а где показываем даты подписки.
  await initializeDateFormatting('ru_RU', null);

  // Принудительно portrait — VPN-приложение не нуждается в landscape,
  // плюс упрощает UI testing. Можно убрать когда дойдём до tablet support.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Status-bar / nav-bar в Pyrita-стиле: тёмные системные surfaces.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0E0F12),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0E0F12),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: PyritaApp()));
}
