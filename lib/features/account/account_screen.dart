import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_tab_bar.dart';

/// Личный кабинет: профиль, план, использование, устройства, реферальная
/// программа, протокол, история платежей.
///
/// Реальные данные пока только email + subscription_status (из /api/me).
/// Остальное — mock'и для дизайна; Phase B-D будут заполнены.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  Map<String, dynamic>? _me;
  String _protocol = 'WireGuard';

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
      }
    }
  }

  String get _email => (_me?['email'] as String?) ?? 'you@pyrita.com';
  String get _firstInitial =>
      _email.isNotEmpty ? _email.substring(0, 1).toUpperCase() : 'A';
  String get _displayName {
    final email = _email;
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return email.substring(0, at);
  }

  /// Возвращает (planTitle, daysLeftText, progressPct).
  ({String title, String hint, double pct}) get _planInfo {
    final status = _me?['subscription_status'];
    if (status is! Map) {
      return (title: 'Pyrita', hint: 'Загружаем…', pct: 0);
    }
    final kind = status['kind'] as String?;
    final daysLeft = status['days_left'] as int?;
    final expiresAt = status['expires_at'] as int?;

    if (kind == 'paid' && daysLeft != null) {
      final hint = expiresAt != null
          ? 'Активен ещё $daysLeft ${_dayWord(daysLeft)}'
          : 'Активен ещё $daysLeft ${_dayWord(daysLeft)}';
      final pct = (daysLeft / 90).clamp(0.0, 1.0);
      return (title: 'Pyrita Pro', hint: hint, pct: pct);
    }
    if (kind == 'trial' && daysLeft != null) {
      return (
        title: 'Pyrita Trial',
        hint: 'Пробный · $daysLeft ${_dayWord(daysLeft)}',
        pct: (daysLeft / 14).clamp(0.0, 1.0),
      );
    }
    return (title: 'Pyrita', hint: 'Подписка истекла', pct: 0);
  }

  String _dayWord(int days) {
    final mod10 = days % 10;
    final mod100 = days % 100;
    if (mod10 == 1 && mod100 != 11) return 'день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'дня';
    return 'дней';
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
              _AccountTopBar(
                onSettings: () => context.push('/settings'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: PyDS.sp3),
                  children: [
                    _ProfileHead(
                      initial: _firstInitial,
                      name: _displayName,
                      email: _email,
                    ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: _PlanCard(
                        info: _planInfo,
                        onRenew: () => context.go('/checkout'),
                        onChange: () => context.go('/checkout'),
                      ),
                    ),
                    const _SectionTitle('Использование'),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: Row(
                        children: const [
                          Expanded(
                            child: _BigStatCard(
                              label: 'Трафик',
                              value: '84.2',
                              unit: 'GB',
                              hint: 'из 256 GB',
                              pct: 0.32,
                            ),
                          ),
                          SizedBox(width: PyDS.sp2),
                          Expanded(
                            child: _BigStatCard(
                              label: 'Онлайн',
                              value: '142',
                              unit: 'ч',
                              hint: 'в этом мес.',
                              pct: 0.68,
                              color: PyDS.on,
                            ),
                          ),
                          SizedBox(width: PyDS.sp2),
                          Expanded(
                            child: _BigStatCard(
                              label: 'Угроз',
                              value: '1284',
                              unit: '',
                              hint: 'заблокировано',
                              pct: 0.50,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _SectionTitle('Устройства', trailing: '3 / 5'),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: Column(
                        children: const [
                          _DeviceRow(
                            icon: Icons.smartphone_outlined,
                            name: 'Pixel 9 (это устройство)',
                            subtitle: 'сейчас',
                            active: true,
                          ),
                          SizedBox(height: PyDS.sp2),
                          _DeviceRow(
                            icon: Icons.laptop_mac_outlined,
                            name: 'MacBook Pro 14″',
                            subtitle: '2 ч назад',
                          ),
                          SizedBox(height: PyDS.sp2),
                          _DeviceRow(
                            icon: Icons.public,
                            name: 'Chrome · Windows',
                            subtitle: 'вчера',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: _ReferralCard(code: 'pyrita.com/r/ARTEM-77'),
                    ),
                    const _SectionTitle('Протокол'),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: _ProtocolToggle(
                        active: _protocol,
                        onChange: (p) => setState(() => _protocol = p),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        PyDS.sp4 + 6,
                        PyDS.sp2,
                        PyDS.sp4 + 6,
                        0,
                      ),
                      child: Text(
                        'Современный протокол — лучше скорость и время '
                        'отклика. Pyrita автоматически переключается при '
                        'блокировках.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PyDS.textFaint,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const _SectionTitle(
                      'История платежей',
                      trailing: 'Все →',
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: Column(
                        children: [
                          _PaymentRow(
                            date: '14 фев 2026',
                            plan: 'Pyrita Pro · 3 мес',
                            amount: '₽2 690',
                          ),
                          _PaymentRow(
                            date: '12 ноя 2025',
                            plan: 'Pyrita Plus · 1 мес',
                            amount: '₽890',
                          ),
                          _PaymentRow(
                            date: '10 окт 2025',
                            plan: 'Pyrita Plus · 1 мес',
                            amount: '₽890',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PyDS.sp3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PyDS.sp4 + 2,
                      ),
                      child: PyButtonGhost(
                        label: 'Выйти',
                        onPressed: () async {
                          await ApiClient.instance.logout();
                          if (!context.mounted) return;
                          context.go('/login');
                        },
                      ),
                    ),
                    const SizedBox(height: PyDS.sp4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const PyTabBar(active: PyTab.account),
    );
  }
}

class _AccountTopBar extends StatelessWidget {
  const _AccountTopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 2,
        PyDS.sp3,
        PyDS.sp4 + 2,
        PyDS.sp2 - 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const PyLogo(size: 26),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PyDS.bg2,
                shape: BoxShape.circle,
                border: Border.all(color: PyDS.stroke),
              ),
              child: const Icon(
                Icons.settings_outlined,
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

class _ProfileHead extends StatelessWidget {
  const _ProfileHead({
    required this.initial,
    required this.name,
    required this.email,
  });

  final String initial;
  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 2,
        PyDS.sp3,
        PyDS.sp4 + 2,
        0,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: PyDS.gradPyrite,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0x73F5DDA3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PyDS.gold.withValues(alpha: 0.55),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: PyDS.font(
                      size: 28,
                      weight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: const Color(0xFF1A140A),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: PyDS.on,
                    shape: BoxShape.circle,
                    border: Border.all(color: PyDS.bg, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: PyDS.on.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 19,
                    weight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: PyDS.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 13,
                    weight: FontWeight.w500,
                    color: PyDS.textSoft,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1AF5DDA3),
                        borderRadius: BorderRadius.circular(PyDS.rPill),
                        border: Border.all(color: PyDS.strokeStrong),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            size: 10,
                            color: PyDS.goldLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'PRO',
                            style: PyDS.font(
                              size: 9.5,
                              weight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: PyDS.goldLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: PyDS.bg2,
                        borderRadius: BorderRadius.circular(PyDS.rPill),
                        border: Border.all(color: PyDS.stroke),
                      ),
                      child: Text(
                        'ID #18472',
                        style: PyDS.font(
                          size: 9.5,
                          weight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: PyDS.textMute,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.info,
    required this.onRenew,
    required this.onChange,
  });

  final ({String title, String hint, double pct}) info;
  final VoidCallback onRenew;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PyDS.sp4 + 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221A13), Color(0xFF14100C)],
        ),
        border: Border.all(color: PyDS.strokeStrong),
        borderRadius: BorderRadius.circular(PyDS.rLg),
        boxShadow: PyDS.shadowCard,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Opacity(
              opacity: 0.4,
              child: PyAppIcon(size: 120, animated: false),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ТЕКУЩИЙ ПЛАН',
                style: PyDS.font(
                  size: 10,
                  weight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: PyDS.textFaint,
                ),
              ),
              const SizedBox(height: 6),
              PyTextGold(
                text: info.title,
                style: PyDS.font(
                  size: 32,
                  weight: FontWeight.w800,
                  letterSpacing: -0.95,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info.hint,
                style: PyDS.font(
                  size: 13,
                  weight: FontWeight.w500,
                  color: PyDS.textSoft,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(PyDS.rPill),
                child: Stack(
                  children: [
                    Container(
                      height: 6,
                      color: const Color(0x1AF5DDA3),
                    ),
                    FractionallySizedBox(
                      widthFactor: info.pct,
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          gradient: PyDS.gradGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PyButtonGold(
                      label: 'Продлить',
                      onPressed: onRenew,
                      height: 44,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(width: PyDS.sp2),
                  Expanded(
                    child: PyButtonGhost(
                      label: 'Сменить план',
                      onPressed: onChange,
                      height: 44,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 6,
        PyDS.sp5,
        PyDS.sp4 + 6,
        PyDS.sp2 + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title.toUpperCase(),
            style: PyDS.font(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: 0.4,
              color: PyDS.textFaint,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: PyDS.font(
                size: 11.5,
                weight: FontWeight.w600,
                color: PyDS.goldLight,
              ),
            ),
        ],
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.hint,
    required this.pct,
    this.color = PyDS.goldLight,
  });

  final String label;
  final String value;
  final String unit;
  final String hint;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.all(PyDS.sp3),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: PyDS.font(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 0.4,
              color: PyDS.textFaint,
            ),
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
                    size: 22,
                    weight: FontWeight.w800,
                    letterSpacing: -0.65,
                    color: color,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: PyDS.font(
                      size: 11,
                      weight: FontWeight.w700,
                      color: PyDS.textFaint,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: PyDS.font(
              size: 10,
              weight: FontWeight.w500,
              height: 1.3,
              color: PyDS.textSoft,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(
                  height: 3,
                  color: const Color(0x14F5DDA3),
                ),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: color == PyDS.on ? null : PyDS.gradGold,
                      color: color == PyDS.on ? PyDS.on : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.subtitle,
    this.active = false,
  });

  final IconData icon;
  final String name;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp3 + 2,
        vertical: PyDS.sp3 - 1,
      ),
      radius: PyDS.rMd,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PyDS.bg2,
              borderRadius: BorderRadius.circular(PyDS.rSm),
              border: Border.all(color: PyDS.stroke),
            ),
            child: Icon(icon, size: 18, color: PyDS.goldLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: PyDS.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: PyDS.font(
                    size: 11,
                    weight: FontWeight.w500,
                    color: PyDS.textFaint,
                  ),
                ),
              ],
            ),
          ),
          if (active)
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
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: PyDS.font(
                    size: 10.5,
                    weight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: PyDS.on,
                  ),
                ),
              ],
            )
          else
            const Icon(Icons.chevron_right, size: 14, color: PyDS.textFaint),
        ],
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PyDS.sp4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x29F5DDA3), Color(0x0AC9A875)],
          stops: [0.0, 0.6],
        ),
        borderRadius: BorderRadius.circular(PyDS.rLg),
        border: Border.all(color: PyDS.strokeStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'РЕФЕРАЛЬНАЯ ПРОГРАММА',
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w700,
              letterSpacing: 0.4,
              color: PyDS.goldLight,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: PyDS.font(
                size: 17,
                weight: FontWeight.w800,
                letterSpacing: -0.4,
                color: PyDS.text,
              ),
              children: [
                const TextSpan(text: 'Приведи друга — получи '),
                WidgetSpan(
                  child: PyTextGold(
                    text: '30 дней',
                    style: PyDS.font(
                      size: 17,
                      weight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: PyDS.bg,
                    borderRadius: BorderRadius.circular(PyDS.rSm),
                    border: Border.all(
                      color: PyDS.strokeStrong,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Text(
                    code,
                    overflow: TextOverflow.ellipsis,
                    style: PyDS.font(
                      size: 12,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                      color: PyDS.goldLight,
                      mono: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Скопировано'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(PyDS.rSm),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: PyDS.gradGold,
                    borderRadius: BorderRadius.circular(PyDS.rSm),
                  ),
                  child: const Icon(
                    Icons.copy_outlined,
                    size: 16,
                    color: Color(0xFF1A140A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: PyDS.stroke, height: 1),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: _KV(value: '7', label: 'приглашено')),
              Expanded(child: _KV(value: '4', label: 'оплатили')),
              Expanded(child: _KV(value: '120', label: 'дней дано')),
            ],
          ),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PyTextGold(
          text: value,
          style: PyDS.font(
            size: 22,
            weight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: PyDS.font(
            size: 10,
            weight: FontWeight.w600,
            letterSpacing: 0.4,
            color: PyDS.textSoft,
          ),
        ),
      ],
    );
  }
}

class _ProtocolToggle extends StatelessWidget {
  const _ProtocolToggle({required this.active, required this.onChange});

  final String active;
  final ValueChanged<String> onChange;

  static const _options = ['WireGuard', 'OpenVPN', 'IKEv2'];

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.all(4),
      radius: PyDS.rLg,
      child: Row(
        children: [
          for (final opt in _options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: opt == active ? PyDS.gradGold : null,
                    borderRadius: BorderRadius.circular(PyDS.rMd),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt,
                    style: PyDS.font(
                      size: 13,
                      weight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: opt == active
                          ? const Color(0xFF1A140A)
                          : PyDS.textMute,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.date,
    required this.plan,
    required this.amount,
  });

  final String date;
  final String plan;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PyDS.strokeSoft, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan,
                  style: PyDS.font(
                    size: 13,
                    weight: FontWeight.w700,
                    color: PyDS.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  date,
                  style: PyDS.font(
                    size: 11,
                    weight: FontWeight.w500,
                    color: PyDS.textFaint,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: PyDS.font(
              size: 13.5,
              weight: FontWeight.w800,
              color: PyDS.text,
            ),
          ),
        ],
      ),
    );
  }
}
