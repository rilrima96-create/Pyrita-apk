import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Plan picker — 4 тарифа. На тап:
///   1. POST /api/checkout/create → backend создаёт CC invoice
///   2. Открываем `redirect_url` в Chrome Custom Tab (нативный браузер,
///      cookies сохраняются, юзер видит SSL-lock)
///   3. После закрытия tab'а (юзер платил или отменил) — pop screen,
///      home screen poll'ит /api/me чтобы детектить новый paid_until
///
/// Цены захардкожены в _plans — должны совпадать с pyrita-web's
/// lib/billing.ts PLANS константой. TODO: подтягивать с /api/plans
/// endpoint когда добавим (сейчас нет — все читают content.ts).
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _loadingPlanId;
  String? _errorMsg;

  static final List<_Plan> _plans = [
    _Plan(id: "1m", title: "1 месяц", price: "200 ₽", perMonth: "200 ₽/мес"),
    _Plan(
      id: "3m",
      title: "3 месяца",
      price: "500 ₽",
      perMonth: "167 ₽/мес",
      savings: "Экономия 17%",
    ),
    _Plan(
      id: "6m",
      title: "6 месяцев",
      price: "900 ₽",
      perMonth: "150 ₽/мес",
      savings: "Экономия 25%",
      featured: true,
    ),
    _Plan(
      id: "12m",
      title: "12 месяцев",
      price: "1 500 ₽",
      perMonth: "125 ₽/мес",
      savings: "Экономия 38%",
    ),
  ];

  Future<void> _selectPlan(_Plan plan) async {
    if (_loadingPlanId != null) return;
    setState(() {
      _loadingPlanId = plan.id;
      _errorMsg = null;
    });

    try {
      final result = await ApiClient.instance.createCheckout(plan.id);
      // Открываем pay-page в Custom Tab. external app = browser, не
      // WebView — так у юзера сохраняются куки если он залогинен в CC,
      // плюс нативный SSL-lock виден.
      final uri = Uri.parse(result.redirectUrl);
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        if (mounted) {
          setState(() {
            _errorMsg = "Не удалось открыть страницу оплаты";
            _loadingPlanId = null;
          });
        }
        return;
      }
      // После открытия Custom Tab сразу pop'аем checkout-screen — юзер
      // вернётся на home по back-button, там можно увидеть статус.
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.message;
          _loadingPlanId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: PyritaColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Выберите тариф"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PyritaSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Оплата СБП через CryptoCloud. Возврат в течение 7 дней.",
                style: tt.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PyritaSpacing.xl),
              ..._plans.map(_buildPlanCard),
              if (_errorMsg != null) ...[
                const SizedBox(height: PyritaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(PyritaSpacing.md),
                  decoration: BoxDecoration(
                    color: PyritaColors.destructive.withValues(alpha: 0.1),
                    border: Border.all(
                      color: PyritaColors.destructive.withValues(alpha: 0.4),
                    ),
                    borderRadius:
                        BorderRadius.circular(PyritaSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: tt.bodySmall?.copyWith(
                      color: PyritaColors.destructive,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: PyritaSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(_Plan plan) {
    final tt = Theme.of(context).textTheme;
    final loading = _loadingPlanId == plan.id;
    final disabled = _loadingPlanId != null && !loading;

    return Padding(
      padding: const EdgeInsets.only(bottom: PyritaSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : () => _selectPlan(plan),
          borderRadius: BorderRadius.circular(PyritaSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(PyritaSpacing.lg),
            decoration: BoxDecoration(
              color: plan.featured
                  ? PyritaColors.obsidian2
                  : PyritaColors.obsidian2,
              border: Border.all(
                color: plan.featured
                    ? PyritaColors.pyrite500
                    : PyritaColors.borderSubtle,
                width: plan.featured ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(PyritaSpacing.radiusLg),
              boxShadow: plan.featured
                  ? [
                      BoxShadow(
                        color: PyritaColors.pyrite500.withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plan.featured) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: PyritaColors.pyrite500,
                            borderRadius:
                                BorderRadius.circular(PyritaSpacing.radiusFull),
                          ),
                          child: Text(
                            "ПОПУЛЯРНЫЙ",
                            style: tt.labelSmall?.copyWith(
                              color: PyritaColors.obsidian,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: PyritaSpacing.xs),
                      ],
                      Text(plan.title, style: tt.titleMedium),
                      const SizedBox(height: PyritaSpacing.xs),
                      Row(
                        children: [
                          Text(
                            plan.price,
                            style: tt.headlineMedium?.copyWith(
                              fontFamily: "monospace",
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: PyritaSpacing.sm),
                          Text(plan.perMonth, style: tt.bodySmall),
                        ],
                      ),
                      if (plan.savings != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          plan.savings!,
                          style: tt.bodySmall?.copyWith(
                            color: PyritaColors.pyrite300,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PyritaColors.pyrite500,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: disabled
                        ? PyritaColors.paper40
                        : PyritaColors.paper70,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Plan {
  const _Plan({
    required this.id,
    required this.title,
    required this.price,
    required this.perMonth,
    this.savings,
    this.featured = false,
  });

  final String id;
  final String title;
  final String price;
  final String perMonth;
  final String? savings;
  final bool featured;
}
