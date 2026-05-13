import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/vpn_controller.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_flag.dart';
import '../../shared/widgets/py_pulse.dart';
import '../../shared/widgets/py_tab_bar.dart';
import '../onboarding/vpn_permission_intro.dart';

/// Главный экран — sonar hero + Connect/Disconnect.
///
/// Phase C: state источник — `vpnControllerProvider` (StateNotifier поверх
/// V2ray instance из flutter_v2ray_client). Tap-on-sonar (или CTA button)
/// поднимает реальный VLESS+Reality туннель через Xray-core; stat tiles
/// реактивно показывают bytes_in/out из onStatusChanged callback.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _me;

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
        context.go('/login');
        return;
      }
      // Молча — экран должен работать в offline preview-режиме.
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();

    final controller = ref.read(vpnControllerProvider.notifier);
    final status = ref.read(vpnControllerProvider);

    // Если уже подключен или подключается — это disconnect-action.
    if (status.isConnected || status.isConnecting) {
      await controller.stop();
      return;
    }

    // Guard: истёкшая подписка → редирект в checkout.
    final subStatus = _me?['subscription_status'];
    if (subStatus is Map && subStatus['kind'] == 'expired') {
      if (!mounted) return;
      _showSnack('Подписка истекла. Продлите её, чтобы подключиться.');
      context.go('/checkout');
      return;
    }

    // Pre-onboarding gate — только в первый раз.
    final alreadyAsked = await controller.hasPermissionEverBeenRequested();
    if (!alreadyAsked) {
      if (!mounted) return;
      final consent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const VpnPermissionIntroScreen(),
          fullscreenDialog: true,
        ),
      );
      if (consent != true) return;
    }

    // System dialog — Android попросит разрешение, если ещё не дано.
    final granted = await controller.requestPermission();
    if (!granted) {
      if (!mounted) return;
      // Android API не различает «user denied» и «другой VPN активен» —
      // оба возвращают granted=false. Диалог покрывает оба случая.
      final retry = await _showPermissionConflictDialog();
      if (retry == true) {
        await _toggle();
      }
      return;
    }

    // Поднимаем туннель — controller сам fetch'ит /api/me, парсит sub URL,
    // строит конфиг с RU bypass и стартует Xray-core.
    await controller.start();

    HapticFeedback.mediumImpact();
  }

  /// Открывает AlertDialog с последними логами Xray + текущим config'ом.
  /// Используется для диагностики connecting-зависания или error-state'а.
  Future<void> _showLogsDialog() async {
    final controller = ref.read(vpnControllerProvider.notifier);
    final status = ref.read(vpnControllerProvider);
    final logs = await controller.fetchLogs();
    final config = controller.currentConfig;
    if (!mounted) return;

    // Показываем ВСЕ logs (до 500 строк) — Xray exception обычно
    // в начале output'а (top of stack trace), мы не хотим truncate'ить.
    // Reversed = newest first (нам важно последнее произошедшее).
    final logsText = logs.isEmpty
        ? '(пусто — plugin ещё не запустил Xray или getLogs() не сработал)'
        : logs.reversed.take(500).join('\n');

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: PyDS.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyDS.rMd),
          side: const BorderSide(color: PyDS.stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(PyDS.sp4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Диагностика VPN',
                style: PyDS.font(
                  size: 17,
                  weight: FontWeight.w800,
                  color: PyDS.text,
                ),
              ),
              const SizedBox(height: PyDS.sp2),
              Text(
                'State: ${status.state.name}'
                '${status.errorMessage != null ? "\nError: ${status.errorMessage}" : ""}'
                '\nConfig cached: ${config != null ? "yes (${config.length} chars)" : "no"}',
                style: PyDS.font(
                  size: 12,
                  weight: FontWeight.w500,
                  color: PyDS.textSoft,
                  mono: true,
                ),
              ),
              const SizedBox(height: PyDS.sp3),
              Text(
                'XRAY LOGS (последние 40):',
                style: PyDS.font(
                  size: 10.5,
                  weight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: PyDS.textFaint,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                padding: const EdgeInsets.all(PyDS.sp2),
                decoration: BoxDecoration(
                  color: PyDS.ink,
                  borderRadius: BorderRadius.circular(PyDS.rSm),
                  border: Border.all(color: PyDS.stroke),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    logsText,
                    style: PyDS.font(
                      size: 10.5,
                      weight: FontWeight.w500,
                      height: 1.4,
                      color: PyDS.textSoft,
                      mono: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PyDS.sp3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                        text: 'State: ${status.state.name}\n'
                            'Error: ${status.errorMessage ?? ""}\n\n'
                            'Logs:\n$logsText',
                      ));
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Скопировано в буфер'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Text(
                      'Скопировать',
                      style: PyDS.font(
                        size: 13,
                        weight: FontWeight.w600,
                        color: PyDS.goldLight,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Закрыть',
                      style: PyDS.font(
                        size: 13,
                        weight: FontWeight.w600,
                        color: PyDS.textMute,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: PyDS.font(size: 13, color: PyDS.text)),
        backgroundColor: PyDS.bg2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Диалог при granted=false от VpnService.prepare(). Покрывает оба
  /// сценария: юзер deny'нул system-dialog ИЛИ у него уже активен
  /// другой VPN (Android API не различает их).
  Future<bool?> _showPermissionConflictDialog() {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: PyDS.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyDS.rMd),
          side: const BorderSide(color: PyDS.stroke),
        ),
        title: Text(
          'Не получилось подключиться',
          style: PyDS.font(
            size: 18,
            weight: FontWeight.w800,
            color: PyDS.text,
            letterSpacing: -0.3,
          ),
        ),
        content: Text(
          'Pyrita не получила разрешение на VPN.\n\n'
          'Возможные причины:\n'
          '• Вы отказали в системном окне\n'
          '• На устройстве активен другой VPN (Hiddify, '
          'AmneziaVPN и т.п.) — отключите его и попробуйте снова',
          style: PyDS.font(
            size: 13.5,
            weight: FontWeight.w500,
            height: 1.5,
            color: PyDS.textSoft,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Закрыть',
              style: PyDS.font(
                size: 14,
                weight: FontWeight.w600,
                color: PyDS.textMute,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Попробовать снова',
              style: PyDS.font(
                size: 14,
                weight: FontWeight.w700,
                color: PyDS.goldLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _expiringSoon {
    final status = _me?['subscription_status'];
    if (status is! Map) return false;
    final kind = status['kind'] as String?;
    if (kind == 'expired') return true;
    if (kind == 'paid') {
      final daysLeft = status['days_left'] as int?;
      return daysLeft != null && daysLeft <= 7;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем VPN status — UI реактивно перерисуется на каждый
    // onStatusChanged callback (примерно раз в секунду пока активно).
    final vpnStatus = ref.watch(vpnControllerProvider);

    // На переход в error — auto-open диалог с full logs + copy-button.
    // Snackbar малоинформативен (пропадает за 4 сек), banner может clip
    // длинный stack trace — диалог гарантированно показывает всё.
    ref.listen<PyritaVpnStatus>(vpnControllerProvider, (prev, next) {
      if (next.isError && prev?.isError != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showLogsDialog();
        });
      }
    });

    final connState = _mapState(vpnStatus.state);

    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: Column(
            children: [
              _HomeTopBar(onAccount: () => context.go('/account')),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PulseTapTarget(
                      onTap: _toggle,
                      child: PyPulse(size: 232, state: connState),
                    ),
                    const SizedBox(height: PyDS.sp3),
                    _StatusBlock(state: connState),
                  ],
                ),
              ),
              // Persistent error banner — показывается пока state.errorMessage
              // не очищен (cleared on next successful connect или новый start).
              // Виден всегда — не пропадает как snackbar.
              if (vpnStatus.errorMessage != null && vpnStatus.isError)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PyDS.sp4 + 2,
                  ),
                  child: _ErrorBanner(
                    message: vpnStatus.errorMessage!,
                    onShowLogs: () => _showLogsDialog(),
                  ),
                ),
              // Debug-кнопка «Показать логи» когда долгое connecting (>10 sec).
              if (vpnStatus.isConnecting)
                _ConnectingDebugButton(onShowLogs: () => _showLogsDialog()),
              if (_expiringSoon)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PyDS.sp4 + 2,
                  ),
                  child: _ExpiringBanner(
                    onTap: () => context.go('/checkout'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PyDS.sp4 + 2,
                  PyDS.sp2,
                  PyDS.sp4 + 2,
                  PyDS.sp3,
                ),
                child: Column(
                  children: [
                    _ServerCard(
                      connected: vpnStatus.isConnected,
                      pingMs: vpnStatus.serverPingMs,
                    ),
                    const SizedBox(height: PyDS.sp2 + 2),
                    _StatRow(status: vpnStatus),
                    const SizedBox(height: PyDS.sp2 + 2),
                    _ConnectButton(state: connState, onTap: _toggle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const PyTabBar(active: PyTab.home),
    );
  }

  /// Маппинг PyritaVpnState → ConnState (UI layer). Error treat как idle
  /// визуально — snackbar объясняет что произошло.
  ConnState _mapState(PyritaVpnState s) => switch (s) {
        PyritaVpnState.connected => ConnState.active,
        PyritaVpnState.connecting => ConnState.connecting,
        _ => ConnState.idle, // disconnected, error
      };
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onAccount});

  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 2,
        PyDS.sp3,
        PyDS.sp4 + 2,
        PyDS.sp3,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const PyLogo(size: 28),
          GestureDetector(
            onTap: onAccount,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PyDS.bg2,
                shape: BoxShape.circle,
                border: Border.all(color: PyDS.stroke),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 18,
                color: PyDS.goldLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.state});

  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final isOn = state == ConnState.active;
    final isPending = state == ConnState.connecting;

    final chipLabel = isOn
        ? 'Под защитой'
        : isPending
            ? 'Защищаем соединение'
            : 'Нажмите чтобы подключиться';
    final dotColor = isOn
        ? PyDS.on
        : isPending
            ? PyDS.warn
            : PyDS.textFaint;
    final chipBg = isOn ? const Color(0x1A6BD49A) : PyDS.bg2;
    final chipBorder = isOn ? const Color(0x526BD49A) : PyDS.stroke;
    final chipColor = isOn ? PyDS.on : PyDS.textMute;

    final title = isOn
        ? 'Интернет работает'
        : isPending
            ? 'Подключаемся'
            : 'Готов к подключению';
    final subtitle = isOn
        ? 'Сайты и звонки работают как обычно'
        : isPending
            ? 'Это займёт пару секунд'
            : 'Один тап — и трафик защищён';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(PyDS.rPill),
              border: Border.all(color: chipBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: isOn
                        ? [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.8),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  chipLabel.toUpperCase(),
                  style: PyDS.font(
                    size: 10.5,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: chipColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PyDS.sp3 - 2),
          isOn
              ? PyTextGold(
                  text: title,
                  textAlign: TextAlign.center,
                  style: PyDS.font(
                    size: 26,
                    weight: FontWeight.w800,
                    letterSpacing: -0.65,
                    height: 1.1,
                  ),
                )
              : Text(
                  title,
                  textAlign: TextAlign.center,
                  style: PyDS.font(
                    size: 26,
                    weight: FontWeight.w800,
                    letterSpacing: -0.65,
                    height: 1.1,
                    color: PyDS.text,
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: PyDS.font(
              size: 12.5,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.connected, this.pingMs});

  final bool connected;
  final int? pingMs;

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp4 + 2,
        vertical: PyDS.sp3 + 2,
      ),
      child: Row(
        children: [
          const PyFlag(code: 'FI', size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СЕРВЕР',
                  style: PyDS.font(
                    size: 10,
                    weight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: PyDS.textFaint,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: PyDS.font(
                      size: 15,
                      weight: FontWeight.w700,
                      color: PyDS.text,
                    ),
                    children: [
                      const TextSpan(text: 'Хельсинки '),
                      TextSpan(
                        text: '· FI',
                        style: PyDS.font(
                          size: 15,
                          weight: FontWeight.w500,
                          color: PyDS.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Live ping показываем только когда connected и измерение есть.
          // Без измерения (первые 5 сек после connect) — рендерим только
          // зелёную точку + dash, без числа.
          if (connected)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: PyDS.on,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: PyDS.on.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pingMs != null ? '$pingMs' : '—',
                      style: PyDS.font(
                        size: 13,
                        weight: FontWeight.w700,
                        color: PyDS.on,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'MS',
                      style: PyDS.font(
                        size: 10,
                        weight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: PyDS.textFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: PyDS.textFaint,
                ),
              ],
            )
          else
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: PyDS.textFaint,
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.status});

  final PyritaVpnStatus status;

  /// Форматирует bytes/sec → Mb/s (megabits, для UI юзер ждёт привычные
  /// провайдерские единицы). 1 байт = 8 бит, MB/s × 8 = Mbps.
  /// 1000000 без digit-separator — Dart SDK constraint >=3.4.0,
  /// underscore-syntax только с 3.6+.
  String _mbps(int bytesPerSec) {
    final mbps = (bytesPerSec * 8) / 1000000;
    if (mbps < 0.1) return '0.0';
    return mbps.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final on = status.isConnected;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'Загрузка',
            value: on ? _mbps(status.downloadSpeed) : '0.0',
            unit: 'Mb/s',
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        Expanded(
          child: _StatTile(
            icon: Icons.keyboard_arrow_up_rounded,
            label: 'Отдача',
            value: on ? _mbps(status.uploadSpeed) : '0.0',
            unit: 'Mb/s',
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        // Phase C: «Заблокировано» — заглушка. Real-counter возможен только
        // когда Xray-core stats покажут rules-match'и (Phase D).
        Expanded(
          child: _StatTile(
            icon: Icons.shield_outlined,
            label: 'Защищено',
            value: on ? '✓' : '—',
            unit: '',
            color: PyDS.on,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.color = PyDS.goldLight,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp3 + 2,
        vertical: PyDS.sp3,
      ),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: PyDS.textFaint),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 9.5,
                    weight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: PyDS.textFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 19,
                    weight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: color,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: PyDS.font(
                      size: 11,
                      weight: FontWeight.w600,
                      color: PyDS.textFaint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.state, required this.onTap});

  final ConnState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOn = state == ConnState.active;
    final isPending = state == ConnState.connecting;

    if (isPending) {
      return PyButtonGhost(
        label: 'Отмена',
        onPressed: onTap,
        color: PyDS.goldLight,
      );
    }
    if (isOn) {
      return PyButtonGhost(
        label: 'Отключить',
        onPressed: onTap,
      );
    }
    return PyButtonGold(label: 'Подключить', onPressed: onTap, fontSize: 16);
  }
}

/// Persistent error banner — показывается пока state.isError. Не пропадает
/// как snackbar; пользователь может прочитать ошибку и нажать «Показать логи».
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onShowLogs});

  final String message;
  final VoidCallback onShowLogs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: PyDS.sp2 + 2),
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp4,
        vertical: PyDS.sp3,
      ),
      decoration: BoxDecoration(
        color: PyDS.danger.withValues(alpha: 0.10),
        border: Border.all(color: PyDS.danger.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(PyDS.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 18, color: PyDS.danger),
              const SizedBox(width: PyDS.sp2),
              Expanded(
                child: Text(
                  'Ошибка подключения',
                  style: PyDS.font(
                    size: 13,
                    weight: FontWeight.w700,
                    color: PyDS.danger,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onShowLogs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: PyDS.bg,
                    borderRadius: BorderRadius.circular(PyDS.rPill),
                    border: Border.all(
                        color: PyDS.danger.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'ЛОГИ',
                    style: PyDS.font(
                      size: 10,
                      weight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: PyDS.danger,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: PyDS.font(
              size: 11.5,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textSoft,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Маленькая ссылка-debug «Показать логи» под sonar когда state==connecting.
/// Появляется чтобы юзер мог получить диагностику если зависнет.
class _ConnectingDebugButton extends StatelessWidget {
  const _ConnectingDebugButton({required this.onShowLogs});

  final VoidCallback onShowLogs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PyDS.sp2),
      child: TextButton(
        onPressed: onShowLogs,
        child: Text(
          'Долго подключаемся? Показать логи',
          style: PyDS.font(
            size: 12,
            weight: FontWeight.w600,
            color: PyDS.textFaint,
          ),
        ),
      ),
    );
  }
}

class _ExpiringBanner extends StatelessWidget {
  const _ExpiringBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: PyDS.sp2 + 2),
        padding: const EdgeInsets.symmetric(
          horizontal: PyDS.sp4,
          vertical: PyDS.sp3,
        ),
        decoration: BoxDecoration(
          color: PyDS.warn.withValues(alpha: 0.10),
          border: Border.all(color: PyDS.warn.withValues(alpha: 0.40)),
          borderRadius: BorderRadius.circular(PyDS.rMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 18, color: PyDS.warn),
            const SizedBox(width: PyDS.sp2 + 2),
            Expanded(
              child: Text(
                'Подписка скоро истечёт. Продлите чтобы не остаться без сети.',
                style: PyDS.font(
                  size: 12.5,
                  weight: FontWeight.w600,
                  height: 1.35,
                  color: PyDS.warn,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: PyDS.warn),
          ],
        ),
      ),
    );
  }
}

/// Press-target вокруг sonar-анимации. Делает её tappable с лёгким scale-press
/// эффектом. Hit-зона круглая (clip), чтобы пропускать тапы по углам
/// квадратного bounding box'а.
class _PulseTapTarget extends StatefulWidget {
  const _PulseTapTarget({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PulseTapTarget> createState() => _PulseTapTargetState();
}

class _PulseTapTargetState extends State<_PulseTapTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
