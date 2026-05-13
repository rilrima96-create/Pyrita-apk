import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';

/// Pre-onboarding-объяснение зачем Pyrita просит VPN-permission на Android.
///
/// Показывается ОДИН раз перед первым тапом «Подключить» (флаг
/// `vpn_permission_requested` в SharedPreferences). Если пользователь
/// тапает «Продолжить» — caller вызывает `requestPermission()` и Android
/// показывает свой system-dialog.
///
/// Цель — снизить permission-deny rate для технически неподготовленных
/// пользователей. Без объяснения system-dialog «Разрешить Pyrita
/// настраивать VPN?» выглядит угрожающим.
///
/// Возвращает через Navigator.pop:
///   * `true` — пользователь нажал «Понятно, продолжить»
///   * `false` или `null` — отмена / back swipe
class VpnPermissionIntroScreen extends StatelessWidget {
  const VpnPermissionIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PyDS.sp4 + 2),
            child: Column(
              children: [
                const SizedBox(height: PyDS.sp3),
                _Header(onClose: () => Navigator.of(context).pop(false)),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: PyDS.sp4),
                        Center(child: PyAppIcon(size: 92, animated: true)),
                        const SizedBox(height: PyDS.sp6),
                        Text(
                          'Нужно одно разрешение',
                          style: PyDS.font(
                            size: 28,
                            weight: FontWeight.w800,
                            letterSpacing: -0.7,
                            height: 1.1,
                            color: PyDS.text,
                          ),
                        ),
                        const SizedBox(height: PyDS.sp2 + 2),
                        Text(
                          'Pyrita создаёт защищённое подключение прямо на '
                          'устройстве. Android попросит подтверждение — '
                          'это нормально, так работают все VPN-клиенты.',
                          style: PyDS.font(
                            size: 14.5,
                            weight: FontWeight.w500,
                            height: 1.5,
                            color: PyDS.textSoft,
                          ),
                        ),
                        const SizedBox(height: PyDS.sp6),
                        const _Section(
                          title: 'Что увидите дальше',
                          items: [
                            _Item(
                              icon: Icons.shield_outlined,
                              text: 'Системный диалог Android: '
                                  '«Разрешить Pyrita настраивать VPN-соединение?»',
                            ),
                            _Item(
                              icon: Icons.vpn_lock_outlined,
                              text: 'Маленький ключик в строке состояния — '
                                  'значит туннель активен.',
                            ),
                          ],
                          accent: PyDS.goldLight,
                        ),
                        const SizedBox(height: PyDS.sp4),
                        const _Section(
                          title: 'Что Pyrita НЕ делает',
                          items: [
                            _Item(
                              icon: Icons.password_outlined,
                              text: 'Не читает пароли и личные сообщения.',
                            ),
                            _Item(
                              icon: Icons.history_toggle_off,
                              text: 'Не сохраняет историю того, что вы смотрите.',
                            ),
                            _Item(
                              icon: Icons.no_accounts_outlined,
                              text: 'Не передаёт данные третьим лицам.',
                            ),
                          ],
                          accent: PyDS.on,
                        ),
                        const SizedBox(height: PyDS.sp4),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: PyDS.sp3,
                    top: PyDS.sp3,
                  ),
                  child: Column(
                    children: [
                      PyButtonGold(
                        label: 'Понятно, продолжить',
                        fontSize: 16,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: PyDS.sp2 + 2),
                      PyButtonGhost(
                        label: 'Отмена',
                        onPressed: () => Navigator.of(context).pop(false),
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

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PyDS.bg2,
              shape: BoxShape.circle,
              border: Border.all(color: PyDS.stroke),
            ),
            child: const Icon(
              Icons.close,
              size: 16,
              color: PyDS.textMute,
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.accent,
  });

  final String title;
  final List<_Item> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp4,
        vertical: PyDS.sp4,
      ),
      decoration: BoxDecoration(
        gradient: PyDS.gradCard,
        borderRadius: BorderRadius.circular(PyDS.rMd),
        border: Border.all(color: PyDS.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: PyDS.sp3),
          for (int i = 0; i < items.length; i++) ...[
            _itemRow(items[i]),
            if (i < items.length - 1) const SizedBox(height: PyDS.sp3),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(_Item item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(item.icon, size: 15, color: accent),
        ),
        const SizedBox(width: PyDS.sp3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.text,
              style: PyDS.font(
                size: 13.5,
                weight: FontWeight.w500,
                height: 1.45,
                color: PyDS.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Item {
  const _Item({required this.icon, required this.text});
  final IconData icon;
  final String text;
}
