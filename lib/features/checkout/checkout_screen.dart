import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_tab_bar.dart';

/// Plan picker — 4 тарифа. На тап "Оплатить":
///   1. POST /api/checkout/create → backend создаёт CC invoice
///   2. Открываем `redirect_url` в Chrome Custom Tab
///   3. После возврата — pop screen, home polls /api/me
///
/// Card form / payment-method селектор — визуал-only (реальную карту
/// принимает CryptoCloud на своей странице, мы не PCI-compliant).
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedId = '6m';
  String _method = 'card';
  bool _loading = false;
  String? _errorMsg;

  static final List<_Plan> _plans = [
    _Plan(
      id: '1m',
      title: '1 месяц',
      price: '₽200',
      perMonth: '₽200 / мес',
    ),
    _Plan(
      id: '3m',
      title: '3 месяца',
      price: '₽500',
      perMonth: '₽167 / мес',
      save: '−17%',
    ),
    _Plan(
      id: '6m',
      title: '6 месяцев',
      price: '₽900',
      perMonth: '₽150 / мес',
      save: '−25%',
      best: true,
    ),
    _Plan(
      id: '12m',
      title: '12 месяцев',
      price: '₽1 500',
      perMonth: '₽125 / мес',
      save: '−38%',
    ),
  ];

  _Plan get _selected => _plans.firstWhere((p) => p.id == _selectedId);

  Future<void> _pay() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final result = await ApiClient.instance.createCheckout(_selectedId);
      final uri = Uri.parse(result.redirectUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() {
          _errorMsg = 'Не удалось открыть страницу оплаты';
          _loading = false;
        });
        return;
      }
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.message;
          _loading = false;
        });
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
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PyDS.sp4 + 2,
                      ),
                      child: Column(
                        children: [
                          for (final p in _plans) ...[
                            _PlanCard(
                              plan: p,
                              selected: p.id == _selectedId,
                              onTap: () =>
                                  setState(() => _selectedId = p.id),
                            ),
                            const SizedBox(height: PyDS.sp2),
                          ],
                        ],
                      ),
                    ),
                    const _SectionTitle('Способ оплаты'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PyDS.sp4 + 2,
                      ),
                      child: _MethodToggle(
                        active: _method,
                        onChange: (m) => setState(() => _method = m),
                      ),
                    ),
                    if (_method == 'card') ...[
                      const SizedBox(height: PyDS.sp3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2,
                        ),
                        child: Column(
                          children: const [
                            _CardField(
                              label: 'Номер карты',
                              value: '4242  ••••  ••••  4242',
                              trailing: _CardBrandIcons(),
                            ),
                            SizedBox(height: PyDS.sp2 + 2),
                            Row(
                              children: [
                                Expanded(
                                  child: _CardField(
                                    label: 'Срок',
                                    value: '08 / 29',
                                  ),
                                ),
                                SizedBox(width: PyDS.sp2 + 2),
                                Expanded(
                                  child: _CardField(
                                    label: 'CVV',
                                    value: '•••',
                                    mono: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_errorMsg != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          PyDS.sp4 + 2,
                          PyDS.sp3,
                          PyDS.sp4 + 2,
                          0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(PyDS.sp3),
                          decoration: BoxDecoration(
                            color: PyDS.danger.withValues(alpha: 0.1),
                            border: Border.all(
                              color: PyDS.danger.withValues(alpha: 0.4),
                            ),
                            borderRadius:
                                BorderRadius.circular(PyDS.rMd),
                          ),
                          child: Text(
                            _errorMsg!,
                            style: PyDS.font(
                              size: 12,
                              weight: FontWeight.w600,
                              color: PyDS.danger,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: PyDS.sp4 + 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PyDS.sp4 + 2,
                      ),
                      child: _TotalCard(
                        plan: _selected,
                        loading: _loading,
                        onPay: _pay,
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
          'Выберите длительность',
          style: PyDS.font(
            size: 26,
            weight: FontWeight.w800,
            letterSpacing: -0.65,
            height: 1.15,
            color: PyDS.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Все тарифы одинаковые. Чем дольше — тем дешевле в месяц. '
          'Отменить можно в любой момент.',
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

class _Plan {
  const _Plan({
    required this.id,
    required this.title,
    required this.price,
    required this.perMonth,
    this.save,
    this.best = false,
  });

  final String id;
  final String title;
  final String price;
  final String perMonth;
  final String? save;
  final bool best;
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.all(selected ? 2 : 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PyDS.rLg),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF5DDA3),
                        Color(0xFF8A6D40),
                        Color(0xFFC9A875),
                      ],
                      stops: [0.0, 0.7, 1.0],
                    )
                  : null,
              color: selected ? null : PyDS.stroke,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: PyDS.gold.withValues(alpha: 0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                        spreadRadius: -16,
                      ),
                    ]
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PyDS.sp4,
                vertical: PyDS.sp3 + 2,
              ),
              decoration: BoxDecoration(
                color: PyDS.bg1,
                borderRadius: BorderRadius.circular(PyDS.rLg - 2),
              ),
              child: Row(
                children: [
                  _PlanRadio(selected: selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                plan.title,
                                overflow: TextOverflow.ellipsis,
                                style: PyDS.font(
                                  size: 14.5,
                                  weight: FontWeight.w800,
                                  letterSpacing: -0.15,
                                  color: PyDS.text,
                                ),
                              ),
                            ),
                            if (plan.save != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x1AF5DDA3),
                                  borderRadius:
                                      BorderRadius.circular(PyDS.rPill),
                                  border: Border.all(color: PyDS.stroke),
                                ),
                                child: Text(
                                  plan.save!,
                                  style: PyDS.font(
                                    size: 9.5,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                    color: PyDS.goldLight,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          plan.perMonth,
                          style: PyDS.font(
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: PyDS.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (selected)
                    PyTextGold(
                      text: plan.price,
                      style: PyDS.font(
                        size: 16,
                        weight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    )
                  else
                    Text(
                      plan.price,
                      style: PyDS.font(
                        size: 16,
                        weight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: PyDS.text,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (plan.best)
            Positioned(
              top: -9,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: PyDS.bg2,
                  borderRadius: BorderRadius.circular(PyDS.rPill),
                  border: Border.all(color: PyDS.strokeStrong),
                ),
                child: Text(
                  'ВЫГОДНЕЕ',
                  style: PyDS.font(
                    size: 9.5,
                    weight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: PyDS.goldLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanRadio extends StatelessWidget {
  const _PlanRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: selected ? PyDS.gradGold : null,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: PyDS.strokeStrong, width: 1.5),
      ),
      child: selected
          ? const Icon(
              Icons.check,
              size: 12,
              color: Color(0xFF1A140A),
            )
          : null,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 6,
        PyDS.sp5,
        PyDS.sp4 + 6,
        PyDS.sp2 + 2,
      ),
      child: Text(
        title.toUpperCase(),
        style: PyDS.font(
          size: 11,
          weight: FontWeight.w700,
          letterSpacing: 0.4,
          color: PyDS.textFaint,
        ),
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  const _MethodToggle({required this.active, required this.onChange});

  final String active;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('card', 'Карта', Icons.credit_card_outlined),
      ('crypto', 'Крипто', Icons.currency_bitcoin),
      ('sbp', 'SBP', Icons.swap_horiz),
    ];
    return PyCard(
      padding: const EdgeInsets.all(4),
      radius: PyDS.rLg,
      child: Row(
        children: [
          for (final (id, label, icon) in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: id == active ? PyDS.gradGold : null,
                    borderRadius: BorderRadius.circular(PyDS.rMd),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: id == active
                            ? const Color(0xFF1A140A)
                            : PyDS.textMute,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: PyDS.font(
                          size: 13,
                          weight: FontWeight.w700,
                          color: id == active
                              ? const Color(0xFF1A140A)
                              : PyDS.textMute,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardField extends StatelessWidget {
  const _CardField({
    required this.label,
    required this.value,
    this.trailing,
    this.mono = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp3 + 2,
        vertical: PyDS.sp3 - 2,
      ),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: PyDS.font(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 0.4,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: PyDS.font(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: PyDS.text,
                    mono: mono,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class _CardBrandIcons extends StatelessWidget {
  const _CardBrandIcons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 14,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEB001B), Color(0xFFF79E1B)],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 22,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F71),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: const Text(
            'V',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.plan,
    required this.loading,
    required this.onPay,
  });

  final _Plan plan;
  final bool loading;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PyDS.sp4),
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
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'К ОПЛАТЕ',
                    style: PyDS.font(
                      size: 10,
                      weight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: PyDS.textFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.price,
                    style: PyDS.font(
                      size: 24,
                      weight: FontWeight.w800,
                      letterSpacing: -0.7,
                      height: 1.1,
                      color: PyDS.text,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                plan.perMonth,
                style: PyDS.font(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: PyDS.textSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PyButtonGold(
            label: 'Оплатить ${plan.price}',
            busy: loading,
            onPressed: onPay,
            fontSize: 14.5,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 11, color: PyDS.textFaint),
              const SizedBox(width: 4),
              Text(
                'TLS 1.3',
                style: PyDS.font(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: PyDS.textFaint,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '7 дней возврат',
                style: PyDS.font(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: PyDS.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
