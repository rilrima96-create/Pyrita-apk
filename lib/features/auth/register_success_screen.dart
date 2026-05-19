import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';

class RegisterSuccessScreen extends StatelessWidget {
  const RegisterSuccessScreen({
    super.key,
    this.selectedPlan,
    this.referralApplied = false,
  });

  final String? selectedPlan;
  final bool referralApplied;

  String? get _planLabel {
    final plan = selectedPlan?.toLowerCase();
    if (plan == null || plan.isEmpty) return null;
    if (plan.startsWith('max')) return 'Max';
    if (plan.startsWith('pro')) return 'Pro';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final planLabel = _planLabel;

    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: PyAppIcon(size: 82, animated: true)),
                          const SizedBox(height: PyDS.sp5),
                          Text(
                            'Pro включён',
                            textAlign: TextAlign.center,
                            style: PyDS.font(
                              size: 28,
                              weight: FontWeight.w800,
                              height: 1.1,
                              color: PyDS.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Аккаунт создан. Доступ уровня Pro активен на 7 дней. Карта не нужна.',
                            textAlign: TextAlign.center,
                            style: PyDS.font(
                              size: 14,
                              weight: FontWeight.w500,
                              height: 1.45,
                              color: PyDS.textSoft,
                            ),
                          ),
                          const SizedBox(height: PyDS.sp5),
                          PyCard(
                            padding: const EdgeInsets.all(PyDS.sp4),
                            child: Column(
                              children: [
                                const _SuccessRow(
                                  icon: Icons.check_circle_outline,
                                  text: 'Pro-доступ включён на 7 дней.',
                                ),
                                const SizedBox(height: PyDS.sp3),
                                const _SuccessRow(
                                  icon: Icons.vpn_lock_outlined,
                                  text:
                                      'Теперь можно подключиться одной кнопкой.',
                                ),
                                if (referralApplied) ...[
                                  const SizedBox(height: PyDS.sp3),
                                  const _SuccessRow(
                                    icon: Icons.group_outlined,
                                    text:
                                        'Если код друга действителен, бонусные дни начислятся после первой успешной оплаты.',
                                  ),
                                ],
                                if (planLabel != null) ...[
                                  const SizedBox(height: PyDS.sp3),
                                  _SuccessRow(
                                    icon: Icons.workspace_premium_outlined,
                                    text:
                                        'Вы интересовались тарифом $planLabel. Его можно оформить позже в разделе подписки.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: PyDS.sp3,
                    bottom: PyDS.sp3,
                  ),
                  child: Column(
                    children: [
                      PyButtonGold(
                        label: 'Подключиться',
                        onPressed: () => context.go('/home'),
                        fontSize: 16,
                      ),
                      const SizedBox(height: PyDS.sp2 + 2),
                      PyButtonGhost(
                        label: 'Посмотреть тарифы',
                        onPressed: () => context.go('/checkout'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: PyDS.goldLight.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: PyDS.goldLight),
        ),
        const SizedBox(width: PyDS.sp3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: PyDS.font(
                size: 13.5,
                weight: FontWeight.w600,
                height: 1.4,
                color: PyDS.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
