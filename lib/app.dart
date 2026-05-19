import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/account/account_screen.dart';
import 'features/account/licenses_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/register_success_screen.dart';
import 'features/checkout/checkout_screen.dart';
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
      title: 'Pyrita',
      debugShowCheckedModeBanner: false,
      theme: buildPyritaTheme(),
      routerConfig: router,
    );
  }
}

/// Router-config:
///   * `/` — splash, проверяет сохранённую сессию
///   * `/login`, `/register`, `/register-success` — auth flow
///   * `/home` — sonar hero, connect/disconnect
///   * `/account` — личный кабинет (план, устройства, реферал, протокол,
///     подтверждение email, newsletter, sub URL, удаление аккаунта)
///   * `/checkout` — оплата подписки (тарифы + CryptoCloud-redirect)
final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegisterScreen(
          refCode: state.uri.queryParameters['ref'],
          planId: state.uri.queryParameters['plan'],
        ),
      ),
      GoRoute(
        path: '/register-success',
        builder: (context, state) => RegisterSuccessScreen(
          selectedPlan: state.uri.queryParameters['plan'],
          referralApplied: state.uri.queryParameters['ref'] == '1',
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/licenses',
        builder: (context, state) => const LicensesScreen(),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
