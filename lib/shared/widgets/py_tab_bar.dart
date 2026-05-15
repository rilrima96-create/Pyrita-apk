import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

enum PyTab { home, account, billing, settings }

/// Bottom-tab bar в стиле дизайна. 4 пункта: home / account / billing / settings.
/// Активный — gold-pill подсветка + золотой icon/label.
class PyTabBar extends StatelessWidget {
  const PyTabBar({super.key, required this.active});

  final PyTab active;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x990C0907), // rgba(12,9,7,0.6)
            border: Border(top: BorderSide(color: PyDS.strokeSoft, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(
            PyDS.sp3,
            PyDS.sp3,
            PyDS.sp3,
            PyDS.sp4,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                _TabItem(
                  tab: PyTab.home,
                  active: active == PyTab.home,
                  icon: Icons.home_outlined,
                  iconActive: Icons.home_rounded,
                  label: 'Главная',
                  onTap: () => context.go('/home'),
                ),
                _TabItem(
                  tab: PyTab.account,
                  active: active == PyTab.account,
                  icon: Icons.person_outline,
                  iconActive: Icons.person,
                  label: 'Кабинет',
                  onTap: () => context.go('/account'),
                ),
                _TabItem(
                  tab: PyTab.billing,
                  active: active == PyTab.billing,
                  icon: Icons.credit_card_outlined,
                  iconActive: Icons.credit_card,
                  label: 'Оплата',
                  onTap: () => context.go('/checkout'),
                ),
                _TabItem(
                  tab: PyTab.settings,
                  active: active == PyTab.settings,
                  icon: Icons.settings_outlined,
                  iconActive: Icons.settings,
                  label: 'Настройки',
                  onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    required this.icon,
    required this.iconActive,
    required this.label,
    required this.onTap,
  });

  final PyTab tab;
  final bool active;
  final IconData icon;
  final IconData iconActive;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? PyDS.goldLight : PyDS.textFaint;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(PyDS.rMd),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? const Color(0x1AC9A875) : Colors.transparent,
              borderRadius: BorderRadius.circular(PyDS.rMd),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? iconActive : icon, size: 20, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: PyDS.font(
                    size: 10.5,
                    weight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: color,
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

/// Top-bar для основных экранов: лого слева, account-icon справа.
class PyTopBar extends StatelessWidget {
  const PyTopBar({
    super.key,
    this.trailing,
    this.leading,
    this.title,
  });

  /// Если задан title — рендерим back-button + title. Иначе — PyLogo + trailing.
  final String? title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (title != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          PyDS.sp4,
          PyDS.sp4,
          PyDS.sp4,
          PyDS.sp3,
        ),
        child: Row(
          children: [
            if (leading != null)
              leading!
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PyDS.bg2,
                  borderRadius: BorderRadius.circular(PyDS.rSm),
                  border: Border.all(color: PyDS.stroke),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.arrow_back, color: PyDS.text),
                  onPressed: () {
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    } else {
                      context.go('/home');
                    }
                  },
                ),
              ),
            const SizedBox(width: 10),
            Text(
              title!,
              style: PyDS.font(
                size: 16,
                weight: FontWeight.w800,
                letterSpacing: -0.3,
                color: PyDS.text,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 4,
        PyDS.sp4 - 2,
        PyDS.sp4 + 4,
        PyDS.sp3,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          leading ?? const SizedBox.shrink(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
