import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import 'auth_bootstrap_decision.dart';

/// Splash screen — рендерится 0.6-1.5 сек пока:
///   1. Читаем session-cookie из secure storage
///   2. Если есть — пробуем GET /api/me чтобы проверить что сессия живая
///   3. Если /api/me вернул 401/403 → /login; сетевой сбой не сбрасывает
///      сохраненную сессию и ведет на /home, где пользователь увидит ошибку.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final minDelay = Future.delayed(const Duration(milliseconds: 600));

    final cookie = await AuthStorage.getSessionCookie();
    bool authed = false;

    if (cookie != null && cookie.isNotEmpty) {
      try {
        await ApiClient.instance.getMe();
        authed = true;
      } on ApiException catch (e) {
        authed = !shouldSendBootstrapFailureToLogin(e.statusCode);
      }
    }

    await minDelay;
    if (!mounted) return;

    if (authed) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PyAppIcon(size: 88, animated: true),
              const SizedBox(height: PyDS.sp4),
              Text(
                'Pyrita',
                style: PyDS.font(
                  size: 32,
                  weight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: PyDS.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Стабильный интернет',
                style: PyDS.font(
                  size: 13,
                  weight: FontWeight.w500,
                  color: PyDS.textSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
