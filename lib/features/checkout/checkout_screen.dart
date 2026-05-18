import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_tab_bar.dart';

/// 3-tier checkout screen (Free / Pro / Max) — mirror'ит /dashboard/billing
/// на pyrita.com. Backend migration 2026-05-15: plan_id формат
/// 'pro-1m' / 'max-12m' и т.д. (8 IDs + 4 legacy aliases).
///
/// UX flow:
///   1. Top: monthly/annual toggle (default annual — exposed savings)
///   2. 3 vertical cards (full-width на mobile):
///      • Pyrita Free — без кнопок (актуальный плюс trial state)
///      • Pyrita Pro (featured) — golden border + «Безлимит, 3 устройства…»
///      • Pyrita Max — Pro + 6 устройств + ручной выбор протокола
///   3. На карточке Pro/Max — кнопка «Подробно» → bottom sheet с 4
///      длительностями + 2 провайдерами (Lava / CryptoCloud)
///   4. Tap на длительность × провайдер → POST /api/checkout/create →
///      launchUrl externalApplication mode → юзер платит
///
/// Trial-юзеры (effective_tier='pro', tier='free') получают Pro-доступ,
/// поэтому экран оплаты подсвечивает Pro как пробный доступ, не Free.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  /// 'monthly' — 1m plan IDs, 'annual' — 12m IDs. По умолчанию annual —
  /// чтобы saving callout сразу visible.
  bool _annual = true;

  /// Текущий видимый tier юзера для подсветки активной карточки.
  /// Загружаем через /api/me на initState. До загрузки — null (skeleton).
  String? _currentTier;
  bool _isTrial = false;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiClient.instance.getMe();
      if (!mounted) return;
      final status = me['subscription_status'];
      final isTrial = status is Map && status['kind'] == 'trial';
      setState(() {
        _isTrial = isTrial;
        _currentTier = isTrial
            ? (me['effective_tier'] as String? ?? 'pro')
            : me['tier'] as String?;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        context.go('/login');
      }
    }
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
              const PyTopBar(title: 'Подписка'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: PyDS.sp4),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        PyDS.sp4 + 6,
                        PyDS.sp3,
                        PyDS.sp4 + 6,
                        0,
                      ),
                      child: _Hero(),
                    ),
                    const SizedBox(height: PyDS.sp4),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PyDS.sp4 + 2,
                      ),
                      child: _BillingToggle(
                        annual: _annual,
                        onChanged: (v) => setState(() => _annual = v),
                      ),
                    ),
                    const SizedBox(height: PyDS.sp3),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
                      child: Column(
                        children: [
                          _TierCard(
                            tier: _PricingTier.free,
                            annual: _annual,
                            isCurrent: _currentTier == 'free',
                            currentLabel: 'ВАШ ПЛАН',
                          ),
                          const SizedBox(height: PyDS.sp3),
                          _TierCard(
                            tier: _PricingTier.pro,
                            annual: _annual,
                            isCurrent: _currentTier == 'pro',
                            currentLabel:
                                _isTrial ? 'ПРОБНЫЙ ДОСТУП' : 'ВАШ ПЛАН',
                          ),
                          const SizedBox(height: PyDS.sp3),
                          _TierCard(
                            tier: _PricingTier.max,
                            annual: _annual,
                            isCurrent: _currentTier == 'max',
                            currentLabel: 'ВАШ ПЛАН',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PyDS.sp3),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: PyDS.sp4 + 6),
                      child: Text(
                        'Оплата картой РФ или СБП через Lava либо криптой '
                        'через CryptoCloud. 7 дней на возврат без объяснений.',
                        style: TextStyle(
                          fontSize: 11,
                          color: PyDS.textFaint,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const PyTabBar(active: PyTab.billing),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Free, чтобы попробовать.\nPro — для повседневного.\nMax — когда нужен контроль.',
          style: PyDS.font(
            size: 22,
            weight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.2,
            color: PyDS.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Лимит зависит от тарифа: Free — 1, Pro — 3, Max — 6 устройств. '
          'Российские сайты всегда напрямую.',
          style: PyDS.font(
            size: 13,
            weight: FontWeight.w500,
            height: 1.45,
            color: PyDS.textSoft,
          ),
        ),
      ],
    );
  }
}

class _BillingToggle extends StatelessWidget {
  const _BillingToggle({required this.annual, required this.onChanged});

  final bool annual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PyDS.bg2,
        borderRadius: BorderRadius.circular(PyDS.rPill),
        border: Border.all(color: PyDS.stroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleSegment(
              label: 'Помесячно',
              active: !annual,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ToggleSegment(
              label: 'Годовая',
              hint: '−27–37%',
              active: annual,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.label,
    required this.active,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          gradient: active ? PyDS.gradGold : null,
          borderRadius: BorderRadius.circular(PyDS.rPill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: PyDS.font(
                size: 12.5,
                weight: FontWeight.w700,
                color: active ? const Color(0xFF1A140A) : PyDS.textSoft,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 6),
              Text(
                hint!,
                style: PyDS.font(
                  size: 10,
                  weight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: active ? const Color(0xFF1A140A) : PyDS.goldLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Tier data — mirror pricing.tiers в pyrita-web/src/lib/content.ts.
// Если backend изменит prices или features — обновлять оба места.
// ──────────────────────────────────────────────────────────────────────

enum _PricingTier { free, pro, max }

class _TierMeta {
  const _TierMeta({
    required this.id,
    required this.name,
    required this.tagline,
    required this.featured,
    required this.priceMonthly,
    required this.priceAnnual,
    required this.perMonthMonthly,
    required this.perMonthAnnual,
    required this.savingsAnnual,
    required this.features,
    required this.durations,
  });

  final String id;
  final String name;
  final String tagline;
  final bool featured;
  final String priceMonthly;
  final String priceAnnual;
  final String? perMonthMonthly;
  final String? perMonthAnnual;
  final String? savingsAnnual;
  final List<String> features;
  // 4 длительности (1m/3m/6m/12m) для bottom-sheet picker'а. null для Free.
  final List<_Duration>? durations;

  static _TierMeta of(_PricingTier t) => switch (t) {
        _PricingTier.free => const _TierMeta(
            id: 'free',
            name: 'Pyrita Free',
            tagline: 'Попробовать без карты',
            featured: false,
            priceMonthly: '0 ₽',
            priceAnnual: '0 ₽',
            perMonthMonthly: null,
            perMonthAnnual: null,
            savingsAnnual: null,
            features: [
              '10 ГБ трафика в месяц',
              '1 устройство',
              'Финляндия · VLESS',
              'Российские сайты — напрямую',
            ],
            durations: null,
          ),
        _PricingTier.pro => const _TierMeta(
            id: 'pro',
            name: 'Pyrita Pro',
            tagline: 'Безлимит и фильтры',
            featured: true,
            priceMonthly: '199 ₽',
            priceAnnual: '1 500 ₽',
            perMonthMonthly: '199 ₽/мес',
            perMonthAnnual: '125 ₽/мес',
            savingsAnnual: 'Экономия 37%',
            features: [
              'Безлимит трафика',
              '3 устройства',
              'Несколько протоколов · auto-failover',
              'Блок рекламы, трекинга, малвари',
              '7 дней на возврат',
            ],
            durations: [
              _Duration('pro-1m', '1 месяц', 199, perMonth: 199),
              _Duration('pro-3m', '3 месяца', 500, perMonth: 167, savePct: 16),
              _Duration('pro-6m', '6 месяцев', 900, perMonth: 150, savePct: 25),
              _Duration('pro-12m', '12 месяцев', 1500,
                  perMonth: 125, savePct: 37),
            ],
          ),
        _PricingTier.max => const _TierMeta(
            id: 'max',
            name: 'Pyrita Max',
            tagline: 'Для требовательных',
            featured: false,
            priceMonthly: '399 ₽',
            priceAnnual: '3 500 ₽',
            perMonthMonthly: '399 ₽/мес',
            perMonthAnnual: '292 ₽/мес',
            savingsAnnual: 'Экономия 27%',
            features: [
              'Всё из Pro',
              '6 устройств',
              'Ручной выбор протокола',
              'Приоритетная поддержка',
            ],
            durations: [
              _Duration('max-1m', '1 месяц', 399, perMonth: 399),
              _Duration('max-3m', '3 месяца', 1000, perMonth: 333, savePct: 16),
              _Duration('max-6m', '6 месяцев', 1900,
                  perMonth: 317, savePct: 21),
              _Duration('max-12m', '12 месяцев', 3500,
                  perMonth: 292, savePct: 27),
            ],
          ),
      };
}

class _Duration {
  const _Duration(
    this.planId,
    this.label,
    this.amount, {
    required this.perMonth,
    this.savePct,
  });

  final String planId;
  final String label;
  final int amount;
  final int perMonth;
  final int? savePct;
}

// ──────────────────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.annual,
    required this.isCurrent,
    required this.currentLabel,
  });

  final _PricingTier tier;
  final bool annual;
  final bool isCurrent;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    final meta = _TierMeta.of(tier);
    final price = annual ? meta.priceAnnual : meta.priceMonthly;
    final perMonth = annual ? meta.perMonthAnnual : meta.perMonthMonthly;
    final savings = annual ? meta.savingsAnnual : null;

    return PyCard(
      padding: const EdgeInsets.all(PyDS.sp4),
      radius: PyDS.rMd,
      border: Border.all(
        color: isCurrent
            ? PyDS.strokeStrong
            : (meta.featured ? PyDS.strokeStrong : PyDS.stroke),
        width: isCurrent || meta.featured ? 1.5 : 1,
      ),
      gradient: isCurrent
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x1FF5DDA3), Color(0x05C9A875)],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta.name,
                  style: PyDS.font(
                    size: 16,
                    weight: FontWeight.w800,
                    color: meta.featured ? PyDS.goldLight : PyDS.text,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PyDS.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(PyDS.rPill),
                  ),
                  child: Text(
                    currentLabel,
                    style: PyDS.font(
                      size: 9.5,
                      weight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: PyDS.goldLight,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            meta.tagline,
            style: PyDS.font(
              size: 12,
              weight: FontWeight.w500,
              color: PyDS.textSoft,
            ),
          ),
          const SizedBox(height: PyDS.sp3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              PyTextGold(
                text: price,
                style: PyDS.font(
                  size: 28,
                  weight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1.0,
                ),
              ),
              if (perMonth != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    perMonth,
                    overflow: TextOverflow.ellipsis,
                    style: PyDS.font(
                      size: 12,
                      weight: FontWeight.w500,
                      color: PyDS.textFaint,
                      mono: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (savings != null) ...[
            const SizedBox(height: 4),
            Text(
              savings,
              style: PyDS.font(
                size: 11,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
                color: PyDS.goldLight,
              ),
            ),
          ],
          const SizedBox(height: PyDS.sp3),
          for (final f in meta.features) ...[
            _FeatureRow(text: f, goldCheck: meta.featured),
            const SizedBox(height: 6),
          ],
          if (meta.durations != null) ...[
            const SizedBox(height: PyDS.sp3 - 2),
            PyButtonGold(
              label: isCurrent ? 'Продлить' : 'Оформить',
              icon: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Color(0xFF1A140A)),
              height: 44,
              fontSize: 13.5,
              onPressed: () => _openPicker(context, meta),
            ),
          ] else ...[
            const SizedBox(height: PyDS.sp2 + 2),
            Text(
              isCurrent
                  ? 'Активный план — без оплаты'
                  : 'Активируется автоматически после окончания подписки',
              style: PyDS.font(
                size: 11.5,
                weight: FontWeight.w500,
                color: PyDS.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openPicker(BuildContext context, _TierMeta meta) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaymentPickerSheet(meta: meta),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text, required this.goldCheck});
  final String text;
  final bool goldCheck;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check,
            size: 13,
            color: goldCheck ? PyDS.goldLight : PyDS.textMute,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: PyDS.font(
              size: 12.5,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textSoft,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Bottom-sheet picker: 4 длительности × 2 провайдера. Tap = create
// invoice + open external browser.
// ──────────────────────────────────────────────────────────────────────

class _PaymentPickerSheet extends StatefulWidget {
  const _PaymentPickerSheet({required this.meta});
  final _TierMeta meta;

  @override
  State<_PaymentPickerSheet> createState() => _PaymentPickerSheetState();
}

class _PaymentPickerSheetState extends State<_PaymentPickerSheet> {
  /// Выбранная длительность. По умолчанию — annual (12m, лучшая экономия).
  late _Duration _selected = widget.meta.durations!.last;

  String? _loadingFor; // 'planId:provider' либо null
  String? _error;

  Future<void> _pay(String provider) async {
    if (_loadingFor != null) return;
    setState(() {
      _loadingFor = '${_selected.planId}:$provider';
      _error = null;
    });
    try {
      final res = await ApiClient.instance.createCheckout(
        _selected.planId,
        provider: provider,
      );
      final uri = Uri.parse(res.redirectUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() {
          _error = 'Не удалось открыть страницу оплаты';
          _loadingFor = null;
        });
        return;
      }
      if (mounted) {
        // pop sheet + checkout screen — юзер ушёл в браузер.
        Navigator.of(context).pop();
        context.pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingFor = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось создать платёж: $e';
        _loadingFor = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLavaLoading = _loadingFor == '${_selected.planId}:lava';
    final isCcLoading = _loadingFor == '${_selected.planId}:cryptocloud';
    final isAnyLoading = _loadingFor != null;

    return Container(
      decoration: const BoxDecoration(
        color: PyDS.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PyDS.rLg),
        ),
        border: Border(top: BorderSide(color: PyDS.strokeStrong, width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        PyDS.sp4,
        PyDS.sp4,
        PyDS.sp4,
        MediaQuery.of(context).viewInsets.bottom + PyDS.sp4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: PyDS.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: PyDS.sp3),
          Text(
            widget.meta.name,
            style: PyDS.font(
              size: 18,
              weight: FontWeight.w800,
              color: PyDS.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Выберите длительность и провайдера оплаты',
            style: PyDS.font(
              size: 12,
              weight: FontWeight.w500,
              color: PyDS.textSoft,
            ),
          ),
          const SizedBox(height: PyDS.sp4),
          // Длительности — 4 ряда
          for (final dur in widget.meta.durations!) ...[
            _DurationRow(
              duration: dur,
              selected: _selected.planId == dur.planId,
              onTap: () => setState(() => _selected = dur),
            ),
            const SizedBox(height: PyDS.sp2),
          ],
          const SizedBox(height: PyDS.sp3),
          // Pay-кнопки
          PyButtonGold(
            label: isLavaLoading ? 'Создаём…' : 'Оплатить картой / СБП',
            icon: const Icon(Icons.credit_card,
                size: 16, color: Color(0xFF1A140A)),
            height: 48,
            fontSize: 14,
            onPressed: isAnyLoading ? null : () => _pay('lava'),
          ),
          const SizedBox(height: PyDS.sp2),
          PyButtonGhost(
            label: isCcLoading ? 'Создаём…' : 'Оплатить криптой',
            icon: const Icon(Icons.currency_bitcoin,
                size: 16, color: PyDS.goldLight),
            height: 48,
            fontSize: 14,
            onPressed: isAnyLoading ? null : () => _pay('cryptocloud'),
          ),
          if (_error != null) ...[
            const SizedBox(height: PyDS.sp3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: PyDS.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(PyDS.rSm),
                border: Border.all(color: PyDS.danger.withValues(alpha: 0.35)),
              ),
              child: Text(
                _error!,
                style: PyDS.font(
                  size: 12,
                  weight: FontWeight.w500,
                  color: PyDS.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final _Duration duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PyDS.sp3 + 2,
          vertical: PyDS.sp3,
        ),
        decoration: BoxDecoration(
          color: selected ? PyDS.gold.withValues(alpha: 0.10) : PyDS.bg2,
          borderRadius: BorderRadius.circular(PyDS.rMd),
          border: Border.all(
            color: selected ? PyDS.strokeStrong : PyDS.stroke,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? PyDS.goldLight : PyDS.textFaint,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: PyDS.goldLight,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duration.label,
                    style: PyDS.font(
                      size: 14,
                      weight: FontWeight.w700,
                      color: PyDS.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${duration.perMonth} ₽/мес',
                    style: PyDS.font(
                      size: 11.5,
                      weight: FontWeight.w500,
                      color: PyDS.textFaint,
                      mono: true,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${duration.amount} ₽',
                  style: PyDS.font(
                    size: 15,
                    weight: FontWeight.w800,
                    color: PyDS.text,
                  ),
                ),
                if (duration.savePct != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    '−${duration.savePct}%',
                    style: PyDS.font(
                      size: 10.5,
                      weight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: PyDS.goldLight,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
