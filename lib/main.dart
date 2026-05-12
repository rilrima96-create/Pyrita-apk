import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
