import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/distribution.dart';
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

  /// `null` пока грузим; `[]` после загрузки если оплат не было.
  List<PaymentRecord>? _payments;

  /// `null` пока грузим. Поля внутри тоже nullable (см. UsageStats).
  UsageStats? _stats;

  /// `null` пока грузим. limit/devices внутри.
  DeviceListResult? _deviceList;

  /// `null` пока грузим.
  ReferralData? _referral;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _loadPayments();
    _loadStats();
    _loadDevices();
    _loadReferral();
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

  /// Hardcoded UI лимит. Backend Marzban может выдать больше (если
  /// серверный limit_per_user_devices не выставлен), но Pyrita-app
  /// принудительно отключает «лишние» — kick'аем все кроме 3 самых
  /// свежих по `last_seen_at`. Это secure-by-default: один аккаунт = 3
  /// устройства, без обхода через purchase-of-multiple subscriptions.
  static const _deviceLimit = 3;

  Future<void> _loadDevices() async {
    try {
      final d = await ApiClient.instance.getDevices();
      if (!mounted) return;

      // Auto-kick: если устройств больше лимита — `forgetDevice` для
      // самых старых. Bypass: list уже отсортирован backend'ом по
      // last_seen_at DESC, поэтому keepers = first N, kickers = rest.
      if (d.devices.length > _deviceLimit) {
        final kickers = d.devices.skip(_deviceLimit).toList();
        for (final dev in kickers) {
          try {
            await ApiClient.instance.forgetDevice(dev.id);
          } catch (e) {
            debugPrint('Failed to kick device ${dev.id}: $e');
          }
        }
        // Refetch чтобы UI показал актуальный список (3 шт).
        try {
          final fresh = await ApiClient.instance.getDevices();
          if (!mounted) return;
          setState(() => _deviceList = fresh);
        } catch (_) {
          // Если refetch упал — показываем top-3 из original'а.
          if (!mounted) return;
          setState(() => _deviceList = DeviceListResult(
                devices: d.devices.take(_deviceLimit).toList(),
                limit: _deviceLimit,
              ));
        }
        return;
      }
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

  String get _email => (_me?['email'] as String?) ?? 'you@pyrita.com';
  String get _firstInitial =>
      _email.isNotEmpty ? _email.substring(0, 1).toUpperCase() : 'A';
  String get _displayName {
    final email = _email;
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return email.substring(0, at);
  }

  /// Возвращает (planTitle, daysLeftText, progressPct). 3-tier aware
  /// (Pyrita Free / Pro / Max) — после migration 2026-05-15.
  ///
  /// Title строится из `me.tier` ('free'/'pro'/'max'). Hint и progress
  /// идут от subscription_status (trial / paid / expired).
  ({String title, String hint, double pct}) get _planInfo {
    // Tier raw — определяет название плана. У trial-юзеров tier='free'
    // (backend ставит effective_tier='pro' для VPN-config, но "ваш план"
    // всё ещё Free).
    final tier = _me?['tier'] as String?;
    final tierName = switch (tier) {
      'pro' => 'Pyrita Pro',
      'max' => 'Pyrita Max',
      'free' => 'Pyrita Free',
      _ => 'Pyrita',
    };

    final status = _me?['subscription_status'];
    if (status is! Map) {
      return (title: tierName, hint: 'Загружаем…', pct: 0);
    }
    final kind = status['kind'] as String?;
    final daysLeft = status['days_left'] as int?;

    if (kind == 'paid' && daysLeft != null) {
      final hint = 'Активен ещё $daysLeft ${_dayWord(daysLeft)}';
      final pct = (daysLeft / 365).clamp(0.0, 1.0);
      return (title: tierName, hint: hint, pct: pct);
    }
    if (kind == 'trial' && daysLeft != null) {
      // Trial — это 7-day Pyrita Pro для новых юзеров. tier='free' в DB
      // но эффективно Pro. Показываем как «Pyrita Pro · пробный».
      return (
        title: 'Pyrita Pro',
        hint: 'Пробный · $daysLeft ${_dayWord(daysLeft)}',
        pct: (daysLeft / 7).clamp(0.0, 1.0),
      );
    }
    // Expired / free — показываем tier name + CTA hint.
    return (
      title: tierName,
      hint: tier == 'free' ? 'Бесплатный план' : 'Подписка истекла',
      pct: 0,
    );
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
                      tier: _me?['tier'] as String?,
                    ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: _PlanCard(
                        info: _planInfo,
                        onRenew: () => context.push('/checkout'),
                        onChange: () => context.push('/checkout'),
                        renewLabel:
                            isGooglePlayBuild ? 'Тарифы' : 'Продлить',
                        changeLabel: isGooglePlayBuild
                            ? 'Что входит'
                            : 'Сменить план',
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
                      // Trailing — `actual / hardLimit` где hardLimit=3.
                      // Если backend серверный limit ниже (e.g. trial=1) —
                      // показываем его как cap (но не больше 3).
                      trailing: _deviceList != null
                          ? '${_deviceList!.devices.length} / ${_deviceList!.limit < _deviceLimit ? _deviceList!.limit : _deviceLimit}'
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
                    const _SectionTitle('История платежей'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: _PaymentsList(payments: _payments),
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
    required this.tier,
  });

  final String initial;
  final String name;
  final String email;

  /// `me.subscription_status` — discriminated union {kind, days_left, ...}.
  /// Может быть null пока /api/me не загружено или если бэкенд изменил shape.
  final Map<String, dynamic>? status;

  /// `me.tier` raw — 'free' / 'pro' / 'max'. null пока загружается.
  /// Badge показывает tier-specific label (PRO N ДН / MAX N ДН).
  final String? tier;

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
                _StatusBadge(status: status, tier: tier),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status pill в ProfileHead. Discriminated union по subscription_status.kind
/// + tier-aware label (3-tier migration 2026-05-15):
///   trial             → жёлтый «TRIAL · N дн» (7-day Pyrita Pro)
///   paid + tier=pro   → золотой «PRO · N дн»
///   paid + tier=max   → золотой «MAX · N дн» (с icon brilliance)
///   expired           → красный «EXPIRED»
///   free (no status)  → серый «FREE»
///   null              → серый «…» (placeholder пока грузим)
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.tier});

  final Map<String, dynamic>? status;
  final String? tier;

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
          // tier='max' → MAX badge с brilliance icon (premium feel).
          // tier='pro' (или fallback) → PRO badge стандартный.
          final tierLabel = tier == 'max' ? 'MAX' : 'PRO';
          label = daysLeft != null ? '$tierLabel · $daysLeft ДН' : tierLabel;
          bg = const Color(0x1AF5DDA3); // gold-tint
          fg = PyDS.goldLight;
          border = PyDS.strokeStrong;
          icon = tier == 'max' ? Icons.diamond_outlined : Icons.auto_awesome;
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
    required this.renewLabel,
    required this.changeLabel,
  });

  final ({String title, String hint, double pct}) info;
  final VoidCallback onRenew;
  final VoidCallback onChange;
  final String renewLabel;
  final String changeLabel;

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
                      label: renewLabel,
                      onPressed: onRenew,
                      height: 44,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(width: PyDS.sp2),
                  Expanded(
                    child: PyButtonGhost(
                      label: changeLabel,
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
