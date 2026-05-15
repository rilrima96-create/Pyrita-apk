import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/vpn_controller.dart';
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

  /// `null` пока грузим; `[]` после загрузки если оплат не было.
  List<PaymentRecord>? _payments;

  /// `null` пока грузим. Поля внутри тоже nullable (см. UsageStats).
  UsageStats? _stats;

  /// `null` пока грузим. limit/devices внутри.
  DeviceListResult? _deviceList;

  /// `null` пока грузим.
  ReferralData? _referral;

  /// `null` пока грузим; `[]` если backend не вернул протоколы.
  List<ProtocolInfo>? _protocols;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _loadPayments();
    _loadStats();
    _loadDevices();
    _loadReferral();
    _loadProtocols();
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

  Future<void> _loadPayments() async {
    try {
      final p = await ApiClient.instance.getPayments();
      if (!mounted) return;
      setState(() => _payments = p);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 401 уже обработает _loadMe(); тут просто оставляем _payments=null
      // → UI покажет skeleton-плейсхолдер.
      if (e.statusCode != 401) {
        // Логируем, но не падаем — Account-экран должен работать даже если
        // payments-endpoint лежит.
        debugPrint('Failed to load payments: ${e.message}');
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await ApiClient.instance.getStats();
      if (!mounted) return;
      setState(() => _stats = s);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 401) {
        debugPrint('Failed to load stats: ${e.message}');
      }
    }
  }

  Future<void> _loadDevices() async {
    try {
      final d = await ApiClient.instance.getDevices();
      if (!mounted) return;
      setState(() => _deviceList = d);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 401) {
        debugPrint('Failed to load devices: ${e.message}');
      }
    }
  }

  Future<void> _loadReferral() async {
    try {
      final r = await ApiClient.instance.getReferral();
      if (!mounted) return;
      setState(() => _referral = r);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 401) {
        debugPrint('Failed to load referral: ${e.message}');
      }
    }
  }

  Future<void> _loadProtocols() async {
    try {
      final p = await ApiClient.instance.getProtocols();
      if (!mounted) return;
      setState(() => _protocols = p);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode != 401) {
        debugPrint('Failed to load protocols: ${e.message}');
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
              const _AccountTopBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: PyDS.sp3),
                  children: [
                    _ProfileHead(
                      initial: _firstInitial,
                      name: _displayName,
                      email: _email,
                      status: _me?['subscription_status'] as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    if (_me != null && _me!['email_confirmed_at'] == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: PyDS.sp4 + 2),
                        child: _EmailConfirmCard(onResent: _loadMe),
                      ),
                      const SizedBox(height: PyDS.sp4 + 2),
                    ],
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: _PlanCard(
                        info: _planInfo,
                        onRenew: () => context.push('/checkout'),
                        onChange: () => context.push('/checkout'),
                      ),
                    ),
                    const _SectionTitle('Использование'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _UsageRow(stats: _stats),
                    ),
                    _SectionTitle(
                      'Устройства',
                      trailing: _deviceList != null
                          ? '${_deviceList!.devices.length} / ${_deviceList!.limit}'
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _DevicesList(list: _deviceList),
                    ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _ReferralCard(data: _referral),
                    ),
                    const _SectionTitle('Протоколы'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _ProtocolList(
                        protocols: _protocols,
                        onReload: _loadProtocols,
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
                        'Pyrita раздаёт подписку со всеми доступными '
                        'протоколами. На этом устройстве активен VLESS Reality — '
                        'основной протокол с DPI-устойчивым handshake. '
                        'Возможность ручного переключения появится позже.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PyDS.textFaint,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const _SectionTitle('Ссылка подписки'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _SubscriptionLinkCard(
                        subscriptionUrl:
                            _me?['subscription_url'] as String?,
                        onRegenerated: _loadMe,
                      ),
                    ),
                    const _SectionTitle('История платежей'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _PaymentsList(payments: _payments),
                    ),
                    const _SectionTitle('Уведомления'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _NewsletterCard(
                        initialOptIn:
                            (_me?['newsletter_opt_in'] as int? ?? 1) == 1,
                      ),
                    ),
                    const SizedBox(height: PyDS.sp5),
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
                    const SizedBox(height: PyDS.sp3),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _DeleteAccountCard(email: _email),
                    ),
                    const SizedBox(height: PyDS.sp5),
                    const _AboutFooter(),
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

/// Top bar Account-экрана. После C2-merge'а (Этап 2 плана a-b2-nifty-haven)
/// шестерёнка «настроек» убрана — все её функции теперь живут прямо в Account,
/// и отдельного /settings экрана больше нет.
class _AccountTopBar extends StatelessWidget {
  const _AccountTopBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        PyDS.sp4 + 2,
        PyDS.sp3,
        PyDS.sp4 + 2,
        PyDS.sp2 - 2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PyLogo(size: 26),
      ),
    );
  }
}

class _ProfileHead extends StatelessWidget {
  const _ProfileHead({
    required this.initial,
    required this.name,
    required this.email,
    required this.status,
  });

  final String initial;
  final String name;
  final String email;

  /// `me.subscription_status` — discriminated union {kind, days_left, ...}.
  /// Может быть null пока /api/me не загружено или если бэкенд изменил shape.
  final Map<String, dynamic>? status;

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
                _StatusBadge(status: status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill в ProfileHead. Discriminated union по subscription_status.kind:
///   trial   → жёлтый «TRIAL · N дн»
///   paid    → золотой «PRO» (если активен) либо «PRO · истекает через N»
///   expired → красный «EXPIRED»
///   null    → серый «…» (placeholder пока грузим)
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final Map<String, dynamic>? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    String label;
    Color bg;
    Color fg;
    Color border;
    IconData? icon;

    if (s == null) {
      label = '…';
      bg = PyDS.bg2;
      fg = PyDS.textFaint;
      border = PyDS.stroke;
    } else {
      final kind = s['kind'] as String?;
      final daysLeft = (s['days_left'] as num?)?.toInt();
      switch (kind) {
        case 'trial':
          label = daysLeft != null ? 'TRIAL · $daysLeft ДН' : 'TRIAL';
          bg = const Color(0x29F5B946); // warn-tint
          fg = PyDS.warn;
          border = PyDS.warn.withValues(alpha: 0.4);
          break;
        case 'paid':
          label = daysLeft != null ? 'PRO · $daysLeft ДН' : 'PRO';
          bg = const Color(0x1AF5DDA3); // gold-tint
          fg = PyDS.goldLight;
          border = PyDS.strokeStrong;
          icon = Icons.auto_awesome;
          break;
        case 'expired':
          label = 'EXPIRED';
          bg = const Color(0x29E26A5E); // danger-tint
          fg = PyDS.danger;
          border = PyDS.danger.withValues(alpha: 0.4);
          break;
        default:
          label = (kind ?? 'unknown').toUpperCase();
          bg = PyDS.bg2;
          fg = PyDS.textMute;
          border = PyDS.stroke;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PyDS.rPill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: PyDS.font(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 0.6,
              color: fg,
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
  const _ReferralCard({required this.data});

  final ReferralData? data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    // Display-форма URL — без https://, чтобы помещалось в карточку.
    final displayUrl = d != null
        ? d.url.replaceFirst(RegExp(r'^https?://'), '')
        : 'pyrita.com/r/…';
    final copyText = d?.url ?? '';

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
                    displayUrl,
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
                onTap: d == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: copyText));
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
            children: [
              Expanded(
                child: _KV(value: '${d?.invited ?? 0}', label: 'приглашено'),
              ),
              Expanded(
                child: _KV(value: '${d?.paid ?? 0}', label: 'оплатили'),
              ),
              Expanded(
                child: _KV(value: '${d?.daysEarned ?? 0}', label: 'дней дано'),
              ),
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

/// Read-only список реальных протоколов которые раздаёт Pyrita-server.
/// Phase A: read-only display, активный определяется автоматически
/// сервером (VLESS Reality — default). Phase C добавит возможность ручного
/// переключения для встроенного sing-box клиента.
class _ProtocolList extends StatelessWidget {
  const _ProtocolList({required this.protocols, required this.onReload});

  final List<ProtocolInfo>? protocols;

  /// Callback после успешного switch'а — родительский screen должен
  /// re-fetch'ить `/api/me/protocols` чтобы обновить active flag (Phase D
  /// scope: active определяется client-side через preferred_protocol,
  /// сервер всё ещё считает primary). Реально-то pwd обновится через
  /// re-render потому что мы храним preferred в SharedPreferences и
  /// читаем при build (см. _ProtocolList build).
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final list = protocols;
    if (list == null) {
      return const Column(
        children: [
          _ProtocolRowSkeleton(),
          SizedBox(height: PyDS.sp2),
          _ProtocolRowSkeleton(),
        ],
      );
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PyDS.sp3),
        child: Text(
          'Не удалось загрузить список протоколов.',
          style: PyDS.font(
            size: 12,
            weight: FontWeight.w500,
            color: PyDS.textFaint,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: PyDS.sp2),
          _ProtocolRow(info: list[i], catalog: list, onSwitched: onReload),
        ],
      ],
    );
  }
}

/// Список protocol-id'шников которые plugin'у parseable и Pyrita-сервер
/// реально кладёт в подписку. Используется в UI для preview "включён бы
/// переключатель или disable'нут" — не делаем switchProtocol() round-trip
/// для protocol'а который точно не работает.
const _switchableProtocolIds = {'reality', 'xhttp'};

class _ProtocolRow extends ConsumerStatefulWidget {
  const _ProtocolRow({
    required this.info,
    required this.catalog,
    required this.onSwitched,
  });

  final ProtocolInfo info;
  final List<ProtocolInfo> catalog;
  final VoidCallback onSwitched;

  @override
  ConsumerState<_ProtocolRow> createState() => _ProtocolRowState();
}

class _ProtocolRowState extends ConsumerState<_ProtocolRow> {
  bool _switching = false;

  Future<void> _onTap() async {
    if (_switching) return;
    final info = widget.info;
    // Client-side override: backend always reports Reality as primary,
    // но если юзер switch'нул на XHTTP — реально-то active в Pyrita-app это
    // XHTTP. См. PyritaVpnStatus.preferredProtocolId.
    final preferred = ref.read(vpnControllerProvider).preferredProtocolId;
    final isActive = info.id == preferred;
    final isAvailable = info.available;

    // Active → просто info snackbar.
    if (isActive) {
      _snack('Это активный протокол — его использует VPN на этом устройстве.');
      return;
    }

    // !available → snackbar warning, не настроен на сервере.
    if (!isAvailable) {
      _snack('Протокол ${info.name} ещё не настроен на сервере.');
      return;
    }

    // Available but not parseable клиентом → snackbar warning, Phase E.
    if (!_switchableProtocolIds.contains(info.id)) {
      _snack(
        'Протокол ${info.name} пока не поддерживается на этом устройстве. '
        'Появится в одной из следующих версий.',
      );
      return;
    }

    // Available & parseable → confirm dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Переключиться на ${info.name}?'),
        content: const Text(
          'VPN отключится и переподключится через 2-3 секунды. '
          'Текущее подключение прервётся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Переключиться'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _switching = true);
    try {
      final controller = ref.read(vpnControllerProvider.notifier);
      final reconnected = await controller.switchProtocol(
        info.id,
        protocolsCatalog: widget.catalog,
      );
      if (!mounted) return;
      _snack(
        reconnected
            ? 'Переключено на ${info.name}, переподключаемся…'
            : 'Сохранено: при следующем подключении будет ${info.name}',
      );
      widget.onSwitched();
    } on StateError catch (e) {
      if (!mounted) return;
      _snack(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      _snack('Не удалось переключить: $e', isError: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: PyDS.font(size: 12.5, color: PyDS.text)),
        backgroundColor: isError ? PyDS.danger : PyDS.bg2,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // ref.watch триггерит rebuild когда preferredProtocolId меняется
    // (в switchProtocol()) → active state визуально обновляется без
    // re-fetch'а /api/me/protocols.
    final preferred =
        ref.watch(vpnControllerProvider.select((s) => s.preferredProtocolId));
    final isActive = info.id == preferred;
    final isAvailable = info.available;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _switching ? null : _onTap,
      child: PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp3 + 2,
        vertical: PyDS.sp3 - 1,
      ),
      radius: PyDS.rMd,
      // Активный — золотая обводка; недоступный — приглушённая;
      // available-but-not-active — обычный stroke.
      border: Border.all(
        color: isActive
            ? PyDS.strokeStrong
            : (isAvailable ? PyDS.stroke : PyDS.strokeSoft),
        width: isActive ? 1.5 : 1,
      ),
      gradient: isActive
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x1FF5DDA3), Color(0x05C9A875)],
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        info.name,
                        overflow: TextOverflow.ellipsis,
                        style: PyDS.font(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: isAvailable ? PyDS.text : PyDS.textFaint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isActive)
                      _ProtocolBadge(
                        label: 'АКТИВЕН',
                        bg: PyDS.gold.withValues(alpha: 0.18),
                        fg: PyDS.goldLight,
                      )
                    else if (!isAvailable)
                      _ProtocolBadge(
                        label: 'НЕ НАСТРОЕН',
                        bg: PyDS.bg2,
                        fg: PyDS.textFaint,
                      )
                    else if (!_switchableProtocolIds.contains(info.id))
                      // Backend кладёт URL'ы для Hy2/TUIC в подписку, но
                      // flutter_v2ray_client не имеет parser'а — реально
                      // переключиться нельзя. Phase E добавит parsers.
                      _ProtocolBadge(
                        label: 'В РАЗРАБОТКЕ',
                        bg: PyDS.bg2,
                        fg: PyDS.textFaint,
                      )
                    else
                      _ProtocolBadge(
                        label: 'ДОСТУПЕН',
                        bg: PyDS.bg2,
                        fg: PyDS.textSoft,
                      ),
                  ],
                ),
                if (info.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    info.description,
                    style: PyDS.font(
                      size: 11,
                      weight: FontWeight.w500,
                      height: 1.35,
                      color: PyDS.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ProtocolBadge extends StatelessWidget {
  const _ProtocolBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PyDS.rPill),
      ),
      child: Text(
        label,
        style: PyDS.font(
          size: 9,
          weight: FontWeight.w700,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

class _ProtocolRowSkeleton extends StatelessWidget {
  const _ProtocolRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp3 + 2,
        vertical: PyDS.sp3 - 1,
      ),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 120, height: 13, color: PyDS.bg2),
          const SizedBox(height: 6),
          Container(width: 220, height: 10, color: PyDS.bg2),
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

/// Список устройств юзера — Pyrita app + другие VPN-клиенты на гаджетах,
/// если юзер скопировал подписку в их. Самое свежее устройство (last_seen)
/// идёт первым с подписью «(это устройство)».
class _DevicesList extends StatelessWidget {
  const _DevicesList({required this.list});

  final DeviceListResult? list;

  @override
  Widget build(BuildContext context) {
    final l = list;
    if (l == null) {
      return Column(
        children: const [
          _DeviceRowSkeleton(),
          SizedBox(height: PyDS.sp2),
          _DeviceRowSkeleton(),
        ],
      );
    }
    if (l.devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PyDS.sp3),
        child: Text(
          'Пока не открыто ни одно устройство. Открой Account на ещё одном — оно появится тут.',
          style: PyDS.font(
            size: 12,
            weight: FontWeight.w500,
            color: PyDS.textFaint,
          ),
        ),
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return Column(
      children: [
        for (int i = 0; i < l.devices.length; i++) ...[
          if (i > 0) const SizedBox(height: PyDS.sp2),
          _DeviceRow(
            icon: _iconForLabel(l.devices[i].label),
            // Первое = самое свежее по серверу (ORDER BY last_seen_at DESC).
            name: i == 0
                ? '${l.devices[i].label ?? "Неизвестное"} (это устройство)'
                : (l.devices[i].label ?? 'Неизвестное'),
            subtitle: _relativeTime(now, l.devices[i].lastSeenAt),
            active: i == 0,
          ),
        ],
      ],
    );
  }

  static IconData _iconForLabel(String? label) {
    if (label == null) return Icons.help_outline;
    final l = label.toLowerCase();
    if (l.contains('pyrita') || l.contains('iphone') || l.contains('android')) {
      return Icons.smartphone_outlined;
    }
    if (l.contains('mac')) return Icons.laptop_mac_outlined;
    if (l.contains('windows')) return Icons.laptop_windows_outlined;
    if (l.contains('linux')) return Icons.laptop_outlined;
    if (l.contains('hiddify') || l.contains('sing-box') || l.contains('clash')) {
      return Icons.vpn_lock_outlined;
    }
    return Icons.public;
  }

  /// «сейчас» / «5 мин» / «3 ч» / «вчера» / «5 дней» / «2 нед».
  static String _relativeTime(int now, int then) {
    final diffMs = now - then;
    if (diffMs < 60000) return 'сейчас';
    final minutes = diffMs ~/ 60000;
    if (minutes < 60) return '$minutes мин назад';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours ч назад';
    final days = hours ~/ 24;
    if (days == 1) return 'вчера';
    if (days < 7) return '$days дн назад';
    final weeks = days ~/ 7;
    return '$weeks нед назад';
  }
}

/// Placeholder для skeleton-state.
class _DeviceRowSkeleton extends StatelessWidget {
  const _DeviceRowSkeleton();

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
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 140, height: 12, color: PyDS.bg2),
                const SizedBox(height: 4),
                Container(width: 60, height: 9, color: PyDS.bg2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Три stat-карточки (Трафик / Онлайн / Угрозы) на real-данных из
/// `/api/me/stats`. null-значения → «—» + хинт «появится скоро» (Phase C).
class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.stats});

  final UsageStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;

    // Трафик
    final trafficUsed = s?.trafficUsedGb;
    final trafficLimit = s?.trafficLimitGb;
    final trafficValue = trafficUsed != null
        ? trafficUsed.toStringAsFixed(1)
        : '—';
    final trafficHint = trafficUsed == null
        ? 'загрузка…'
        : (trafficLimit != null
            ? 'из ${trafficLimit.toStringAsFixed(0)} GB'
            : 'без лимита');
    final trafficPct = (trafficUsed != null &&
            trafficLimit != null &&
            trafficLimit > 0)
        ? (trafficUsed / trafficLimit).clamp(0.0, 1.0)
        : 0.0;

    // Онлайн — TODO Phase C (sing-box stats)
    final onlineValue = s?.onlineHours?.toString() ?? '—';
    final onlineHint = s == null
        ? 'загрузка…'
        : (s.onlineHours == null ? 'появится скоро' : 'в этом мес.');

    // Угрозы — TODO Phase C (sing-box geosite blocklist counter)
    final threatsValue = s?.threatsBlocked?.toString() ?? '—';
    final threatsHint = s == null
        ? 'загрузка…'
        : (s.threatsBlocked == null ? 'появится скоро' : 'заблокировано');

    return Row(
      children: [
        Expanded(
          child: _BigStatCard(
            label: 'Трафик',
            value: trafficValue,
            unit: trafficUsed != null ? 'GB' : '',
            hint: trafficHint,
            pct: trafficPct,
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        Expanded(
          child: _BigStatCard(
            label: 'Онлайн',
            value: onlineValue,
            unit: s?.onlineHours != null ? 'ч' : '',
            hint: onlineHint,
            pct: 0,
            color: PyDS.on,
          ),
        ),
        const SizedBox(width: PyDS.sp2),
        Expanded(
          child: _BigStatCard(
            label: 'Угроз',
            value: threatsValue,
            unit: '',
            hint: threatsHint,
            pct: 0,
          ),
        ),
      ],
    );
  }
}

/// Wrapper над списком оплат — обрабатывает три состояния:
///   * `payments == null` — ещё грузится, показываем 3 skeleton-row'а
///   * `payments.isEmpty` — у юзера ни одной оплаты, мягкое сообщение
///   * иначе — реальный список (до 10 рядов)
///
/// Маппинг plan_id → human-label дублирует словарь из `pyrita-web/lib/billing.ts`
/// (если billing-сторона изменит названия, оба файла надо обновить).
class _PaymentsList extends StatelessWidget {
  const _PaymentsList({required this.payments});

  final List<PaymentRecord>? payments;

  static const _planLabels = {
    '1m': 'Pyrita · 1 мес',
    '3m': 'Pyrita · 3 мес',
    '6m': 'Pyrita · 6 мес',
    '12m': 'Pyrita · 12 мес',
  };

  @override
  Widget build(BuildContext context) {
    final p = payments;
    if (p == null) {
      // Skeleton — 2 пустых ряда чтобы сохранить вертикальный ритм пока
      // загружается.
      return Column(
        children: const [
          _PaymentRowSkeleton(),
          _PaymentRowSkeleton(),
        ],
      );
    }
    if (p.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PyDS.sp3),
        child: Text(
          'Платежей пока нет. Активная подписка — пробный период.',
          style: PyDS.font(
            size: 12,
            weight: FontWeight.w500,
            color: PyDS.textFaint,
          ),
        ),
      );
    }

    return Column(
      children: p.map((rec) {
        final date = DateFormat('d MMM y', 'ru_RU')
            .format(DateTime.fromMillisecondsSinceEpoch(rec.paidAt));
        final plan = _planLabels[rec.planId] ?? 'Pyrita · ${rec.planId}';
        // Формат суммы «₽2 690» — пробел-разделитель тысяч.
        final amount = '₽${NumberFormat('#,##0', 'ru_RU').format(rec.amountRub)}'
            .replaceAll(' ', ' ');
        return _PaymentRow(date: date, plan: plan, amount: amount);
      }).toList(),
    );
  }
}

/// Placeholder-ряд для skeleton-state. Совпадает по высоте с _PaymentRow
/// чтобы layout не «прыгал» когда данные приходят.
class _PaymentRowSkeleton extends StatelessWidget {
  const _PaymentRowSkeleton();

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
                Container(width: 120, height: 12, color: PyDS.bg2),
                const SizedBox(height: 4),
                Container(width: 60, height: 9, color: PyDS.bg2),
              ],
            ),
          ),
          Container(width: 50, height: 12, color: PyDS.bg2),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Etap 2 (C2-merge): inline'ed settings sections.
// Email confirm, subscription URL+regenerate, newsletter toggle, delete
// account, about footer — раньше жили в /settings, теперь часть Account.
// ──────────────────────────────────────────────────────────────────────

/// Жёлтое предупреждение «Подтвердите email» со встроенной resend-кнопкой.
/// Появляется только когда `me.email_confirmed_at == null`.
class _EmailConfirmCard extends StatefulWidget {
  const _EmailConfirmCard({required this.onResent});

  /// Перезагрузить `me` в родителе после успешного resend — чтобы баннер
  /// исчез, если пользователь успел подтвердить в браузере.
  final VoidCallback onResent;

  @override
  State<_EmailConfirmCard> createState() => _EmailConfirmCardState();
}

class _EmailConfirmCardState extends State<_EmailConfirmCard> {
  bool _busy = false;
  String? _message;
  bool _success = false;

  Future<void> _resend() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ApiClient.instance.resendEmailConfirmation();
      if (!mounted) return;
      setState(() {
        _success = true;
        _message =
            'Письмо отправлено. Проверьте папку «Спам» если не пришло за минуту.';
        _busy = false;
      });
      widget.onResent();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.all(PyDS.sp4),
      radius: PyDS.rLg,
      border: Border.all(color: PyDS.warn.withValues(alpha: 0.4), width: 1),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x29F5B946), Color(0x0AF5B946)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined,
                  size: 16, color: PyDS.warn),
              const SizedBox(width: 6),
              Text(
                'EMAIL НЕ ПОДТВЕРЖДЁН',
                style: PyDS.font(
                  size: 10.5,
                  weight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: PyDS.warn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Подтверди email — нам понадобится отправлять тех. уведомления '
            'и чеки об оплате.',
            style: PyDS.font(
              size: 12.5,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textSoft,
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: PyDS.font(
                size: 11.5,
                weight: FontWeight.w600,
                color: _success ? PyDS.on : PyDS.danger,
              ),
            ),
          ],
          const SizedBox(height: PyDS.sp3),
          PyButtonGhost(
            label: _busy ? 'Отправляем…' : 'Отправить ещё раз',
            onPressed: _busy ? null : _resend,
            height: 40,
            fontSize: 13,
            color: PyDS.warn,
          ),
        ],
      ),
    );
  }
}

/// Подписка для других устройств (Hiddify, sing-box). На самом телефоне
/// Pyrita импортирует sub URL автоматически, эта карточка — чтобы юзер
/// мог переиспользовать аккаунт на ноуте/планшете.
class _SubscriptionLinkCard extends StatefulWidget {
  const _SubscriptionLinkCard({
    required this.subscriptionUrl,
    required this.onRegenerated,
  });

  final String? subscriptionUrl;
  final VoidCallback onRegenerated;

  @override
  State<_SubscriptionLinkCard> createState() => _SubscriptionLinkCardState();
}

class _SubscriptionLinkCardState extends State<_SubscriptionLinkCard> {
  bool _busy = false;

  Future<void> _copy() async {
    final url = widget.subscriptionUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перевыпустить ссылку?'),
        content: const Text(
          'Старая ссылка перестанет работать сразу. После этого надо будет '
          'переимпортировать профиль во всех клиентах. Используй если '
          'думаешь, что URL утёк.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Перевыпустить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiClient.instance.regenerateSubscription();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка обновлена')),
      );
      widget.onRegenerated();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: PyDS.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.subscriptionUrl;
    return PyCard(
      padding: const EdgeInsets.all(PyDS.sp4),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Если хотите использовать Pyrita на других устройствах (ноутбук, '
            'планшет) — скопируйте эту ссылку в свой VPN-клиент. На этом '
            'телефоне Pyrita сама подключается, копировать не нужно.',
            style: PyDS.font(
              size: 11.5,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: PyDS.sp3),
          // Сокращённое отображение URL — полный текст копируется кнопкой,
          // визуально показываем только домен + начало токена.
          if (url != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: PyDS.bg,
                borderRadius: BorderRadius.circular(PyDS.rSm),
                border: Border.all(color: PyDS.strokeStrong),
              ),
              child: Text(
                _shortenUrl(url),
                overflow: TextOverflow.ellipsis,
                style: PyDS.font(
                  size: 11.5,
                  weight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: PyDS.goldLight,
                  mono: true,
                ),
              ),
            ),
          const SizedBox(height: PyDS.sp3),
          PyButtonGhost(
            label: 'Скопировать ссылку',
            onPressed: url == null ? null : _copy,
            icon: const Icon(Icons.content_copy,
                size: 14, color: PyDS.goldLight),
            height: 42,
            fontSize: 13,
            color: PyDS.goldLight,
          ),
          const SizedBox(height: PyDS.sp2),
          TextButton(
            onPressed: _busy ? null : _regenerate,
            child: Text(
              _busy ? 'Перевыпускаем…' : 'Перевыпустить ссылку',
              style: PyDS.font(
                size: 12,
                weight: FontWeight.w500,
                color: PyDS.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Превращает `https://pyrita.com/sub/abc123def456…` → `pyrita.com/sub/abc12…`
  /// чтобы карточка не растягивалась под длинный token.
  String _shortenUrl(String url) {
    final clean = url.replaceFirst(RegExp(r'^https?://'), '');
    if (clean.length <= 36) return clean;
    return '${clean.substring(0, 32)}…';
  }
}

/// Newsletter opt-in toggle. Сохраняет ответ оптимистично — UI меняется
/// сразу, при ошибке откатывается на prev value + показывает сообщение.
class _NewsletterCard extends StatefulWidget {
  const _NewsletterCard({required this.initialOptIn});

  final bool initialOptIn;

  @override
  State<_NewsletterCard> createState() => _NewsletterCardState();
}

class _NewsletterCardState extends State<_NewsletterCard> {
  late bool _optIn = widget.initialOptIn;
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool v) async {
    if (_busy) return;
    final prev = _optIn;
    setState(() {
      _optIn = v;
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.setNewsletterOptIn(v);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _optIn = prev;
          _error = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp4,
        vertical: PyDS.sp2,
      ),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            value: _optIn,
            onChanged: _busy ? null : _toggle,
            activeThumbColor: PyDS.gold,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Email о тех. работах и новостях',
              style: PyDS.font(
                size: 13,
                weight: FontWeight.w600,
                color: PyDS.text,
              ),
            ),
            subtitle: Text(
              _optIn
                  ? 'Будем писать только по делу — пару раз в месяц'
                  : 'Только письма про подтверждение email и оплату',
              style: PyDS.font(
                size: 11,
                weight: FontWeight.w500,
                color: PyDS.textFaint,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: PyDS.font(
                size: 11.5,
                weight: FontWeight.w500,
                color: PyDS.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Destructive «Удалить аккаунт». Двойной AlertDialog confirm — чтобы
/// случайным двойным тапом не сжечь подписку.
class _DeleteAccountCard extends StatefulWidget {
  const _DeleteAccountCard({required this.email});

  final String email;

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _busy = false;

  Future<void> _delete() async {
    if (_busy) return;

    // Step 1 — мягкое предупреждение.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: Text(
          'Это действие нельзя отменить. Подписка перестанет работать на '
          'всех устройствах, Marzban-пользователь удалится навсегда.\n\n'
          'Аккаунт: ${widget.email}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Продолжить',
                style: PyDS.font(
                  size: 14,
                  weight: FontWeight.w600,
                  color: PyDS.danger,
                )),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Step 2 — финальный confirm.
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Точно удалить?'),
        content: const Text(
          'Деньги за неиспользованную часть подписки не возвращаются. '
          'Это последний шанс отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PyDS.danger,
              foregroundColor: PyDS.text,
            ),
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiClient.instance.deleteAccount();
      if (!mounted) return;
      context.go('/login');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: PyDS.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PyButtonGhost(
      label: _busy ? 'Удаляем…' : 'Удалить аккаунт',
      onPressed: _busy ? null : _delete,
      icon: const Icon(Icons.delete_outline, size: 16, color: PyDS.danger),
      height: 48,
      fontSize: 13,
      color: PyDS.danger,
    );
  }
}

/// Мелкая подпись «версия + поддержка» в самом низу Account.
class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Pyrita Android · v0.1.0',
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Поддержка: t.me/pyrita_support',
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w500,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: PyDS.sp2 + 2),
          TextButton(
            onPressed: () => context.push('/licenses'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              'Открытые лицензии',
              style: PyDS.font(
                size: 11,
                weight: FontWeight.w600,
                color: PyDS.goldLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
