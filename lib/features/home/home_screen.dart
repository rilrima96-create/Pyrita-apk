import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Главный экран — Connect/Disconnect toggle + статус подписки.
///
/// **Phase A mockup**: connection state — локальный, не туннелирует.
/// Кнопка просто переключает visual-state «Connected/Disconnected»
/// плюс fake-stats. Phase C добавит реальный VpnService binding к
/// sing-box-core.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _connected = false;
  bool _busy = false;
  Map<String, dynamic>? _me;
  String? _meError;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiClient.instance.getMe();
      if (!mounted) return;
      setState(() => _me = me);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        // Сессия истекла — на login
        context.go("/login");
        return;
      }
      setState(() => _meError = e.message);
    }
  }

  Future<void> _toggleConnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Фейк-задержка имитирует handshake. Phase C заменит на реальный
    // VpnService.startService() через MethodChannel.
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _connected = !_connected;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: PyritaColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Pyrita", style: tt.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            color: PyritaColors.paper70,
            onPressed: () => context.push("/settings"),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PyritaSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Subscription status card
              _SubscriptionCard(me: _me, error: _meError),
              const SizedBox(height: PyritaSpacing.xl2),

              // Connect button — center stage
              Expanded(
                child: Center(
                  child: _ConnectButton(
                    connected: _connected,
                    busy: _busy,
                    onTap: _toggleConnect,
                  ),
                ),
              ),

              // Status text under button
              Text(
                _connected
                    ? "Соединение защищено"
                    : "Нажмите для подключения",
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: _connected
                      ? PyritaColors.success
                      : PyritaColors.paper55,
                ),
              ),
              const SizedBox(height: PyritaSpacing.xl2),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.me, required this.error});

  final Map<String, dynamic>? me;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (error != null) {
      return _card(
        Row(
          children: [
            const Icon(Icons.error_outline,
                color: PyritaColors.destructive, size: 20),
            const SizedBox(width: PyritaSpacing.md),
            Expanded(
              child: Text(error!,
                  style: tt.bodySmall?.copyWith(
                      color: PyritaColors.destructive)),
            ),
          ],
        ),
      );
    }

    if (me == null) {
      return _card(
        const SizedBox(
          height: 24,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PyritaColors.pyrite500,
              ),
            ),
          ),
        ),
      );
    }

    final status = me!["subscription_status"] as Map?;
    final kind = status?["kind"] as String?;
    final daysLeft = status?["days_left"] as int?;
    final expiresAt = status?["expires_at"] as int?;

    String title;
    String? subtitle;
    Color accentColor = PyritaColors.pyrite500;

    if (kind == "paid") {
      title = "Подписка активна";
      if (daysLeft != null && expiresAt != null) {
        final date = DateFormat("d MMMM", "ru_RU")
            .format(DateTime.fromMillisecondsSinceEpoch(expiresAt));
        subtitle = "До $date · $daysLeft ${_dayWord(daysLeft)}";
      }
    } else if (kind == "trial") {
      title = "Пробный период";
      if (daysLeft != null && expiresAt != null) {
        final date = DateFormat("d MMMM", "ru_RU")
            .format(DateTime.fromMillisecondsSinceEpoch(expiresAt));
        subtitle = "До $date · $daysLeft ${_dayWord(daysLeft)}";
      }
    } else {
      title = "Подписка истекла";
      subtitle = "Продлите чтобы продолжить";
      accentColor = PyritaColors.destructive;
    }

    return _card(
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(PyritaSpacing.radiusFull),
            ),
            child: Icon(Icons.workspace_premium_outlined,
                color: accentColor, size: 20),
          ),
          const SizedBox(width: PyritaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: tt.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(PyritaSpacing.lg),
      decoration: BoxDecoration(
        color: PyritaColors.obsidian2,
        border: Border.all(color: PyritaColors.borderSubtle),
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusLg),
      ),
      child: child,
    );
  }

  String _dayWord(int days) {
    // Simple русская плюрализация для «1 день / 2 дня / 5 дней».
    final mod10 = days % 10;
    final mod100 = days % 100;
    if (mod10 == 1 && mod100 != 11) return "день";
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "дня";
    return "дней";
  }
}

/// Connect/Disconnect — большая круглая кнопка с pulsing animation
/// когда connected. Mock-визуал; реальный VPN-tunnel в Phase C.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connected,
    required this.busy,
    required this.onTap,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: connected
                ? [PyritaColors.pyrite500, PyritaColors.pyrite700]
                : [PyritaColors.obsidian2, PyritaColors.obsidian3],
          ),
          border: Border.all(
            color: connected
                ? PyritaColors.pyrite500
                : PyritaColors.borderDefault,
            width: 2,
          ),
          boxShadow: connected
              ? [
                  BoxShadow(
                    color: PyritaColors.pyrite500.withOpacity(0.4),
                    blurRadius: 48,
                    spreadRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: PyritaColors.pyrite500,
                  ),
                )
              : Icon(
                  connected ? Icons.shield : Icons.power_settings_new,
                  size: 64,
                  color: connected
                      ? PyritaColors.obsidian
                      : PyritaColors.paper70,
                ),
        ),
      ),
    );
  }
}
