import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';

/// Root приложения. Material+go_router setup. State management через Riverpod
/// (см. main.dart ProviderScope).
class PyritaApp extends ConsumerWidget {
  const PyritaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: "Pyrita",
      debugShowCheckedModeBanner: false,
      theme: buildPyritaTheme(),
      routerConfig: router,
    );
  }
}

/// Router-config. Routes:
///   * `/` — splash, проверяет сохранённую сессию
///   * `/login` — форма входа
///   * `/home` — главный экран с Connect/Disconnect
///   * `/settings` — настройки
final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: "/",
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: "/",
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: "/login",
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: "/home",
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: "/settings",
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
