import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_flag.dart';
import '../../shared/widgets/py_pulse.dart';
import '../../shared/widgets/py_tab_bar.dart';

/// Главный экран — sonar hero + Connect/Disconnect.
///
/// **Phase A mockup**: connection state — локальный, не туннелирует.
/// Phase C добавит реальный VpnService binding к sing-box-core.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ConnState _state = ConnState.active;
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
    // Tactile feedback — лёгкий "тык" при переключении.
    HapticFeedback.lightImpact();

    if (_state == ConnState.connecting) {
      setState(() => _state = ConnState.idle);
      return;
    }
    if (_state == ConnState.idle) {
      setState(() => _state = ConnState.connecting);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _state = ConnState.active);
      // Чуть более ощутимая отдача при успешном connect.
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _state = ConnState.idle);
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
                      child: PyPulse(size: 232, state: _state),
                    ),
                    const SizedBox(height: PyDS.sp3),
                    _StatusBlock(state: _state),
                  ],
                ),
              ),
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
                    const _ServerCard(),
                    const SizedBox(height: PyDS.sp2 + 2),
                    _StatRow(state: _state),
                    const SizedBox(height: PyDS.sp2 + 2),
                    _ConnectButton(state: _state, onTap: _toggle),
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
  const _ServerCard();

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
                    '24',
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
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.state});

  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final on = state == ConnState.active;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'Загрузка',
            value: on ? '142.8' : '0.0',
            unit: 'Mb/s',
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        Expanded(
          child: _StatTile(
            icon: Icons.keyboard_arrow_up_rounded,
            label: 'Отдача',
            value: on ? '28.4' : '0.0',
            unit: 'Mb/s',
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        Expanded(
          child: _StatTile(
            icon: Icons.shield_outlined,
            label: 'Заблокировано',
            value: on ? '12' : '0',
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
