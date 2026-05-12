import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';

/// Splash screen — рендерится 1-2 секунды пока:
///   1. Читаем session-cookie из secure storage
///   2. Если есть — пробуем GET /api/me чтобы проверить что сессия живая
///   3. Если живая → редирект на /home; если нет → /login
///
/// Если сети нет (offline) — даём 1.5s grace period и идём на /login
/// (нельзя коннектиться без auth — но юзер хотя бы видит UI).
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
    // Минимальная задержка чтобы splash не мигнул на быстром старте.
    // 600ms — достаточно чтобы юзер увидел brand-mark.
    final minDelay = Future.delayed(const Duration(milliseconds: 600));

    final cookie = await AuthStorage.getSessionCookie();
    bool authed = false;

    if (cookie != null && cookie.isNotEmpty) {
      try {
        await ApiClient.instance.getMe();
        authed = true;
      } on ApiException {
        // 401 / network → юзер не аутентифицирован или offline. Пускаем
        // на /login где он или войдёт, или увидит ошибку.
        authed = false;
      }
    }

    await minDelay;
    if (!mounted) return;

    if (authed) {
      context.go("/home");
    } else {
      context.go("/login");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PyritaColors.obsidian,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              "assets/images/logo-mark.svg",
              width: 88,
              height: 88,
            ),
            const SizedBox(height: PyritaSpacing.lg),
            Text(
              "Pyrita",
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: PyritaSpacing.sm),
            Text(
              "Стабильный интернет",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
