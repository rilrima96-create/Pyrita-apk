import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';

/// Pre-onboarding-объяснение зачем Pyrita просит permission'ы на Android.
///
/// Показывается ОДИН раз перед первым тапом «Подключить» (флаг
/// `vpn_permission_requested` в SharedPreferences). Если пользователь
/// тапает «Разрешить VPN»:
///   1. Запрашиваем POST_NOTIFICATIONS (Android 13+) — silent, если
///      denied всё равно продолжаем (VPN работает, просто без видимого
///      статуса в шторке).
///   2. Caller (home_screen._toggle) вызывает `requestPermission()`
///      для VpnService — Android показывает свой system-dialog
///      «Разрешить Pyrita настраивать VPN?».
///
/// Цель — снизить permission-deny rate для технически неподготовленных
/// пользователей. Без объяснения system-dialog «Разрешить Pyrita
/// настраивать VPN?» выглядит угрожающим.
///
/// Возвращает через Navigator.pop:
///   * `true` — пользователь нажал «Разрешить VPN»
///   * `false` или `null` — отмена / back swipe
class VpnPermissionIntroScreen extends StatelessWidget {
  const VpnPermissionIntroScreen({super.key});

  /// Просим POST_NOTIFICATIONS. На Android <13 permission auto-granted'ом
  /// возвращается. На 13+ показывается system-prompt. Denied — fine,
  /// VpnService всё равно стартует (foreground service не падает без
  /// видимой notification, просто status bar пустой).
  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<void> _onContinue(BuildContext context) async {
    await _requestNotificationPermission();
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

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
                          'Разрешение VPN',
                          style: PyDS.font(
                            size: 28,
                            weight: FontWeight.w800,
                            height: 1.1,
                            color: PyDS.text,
                          ),
                        ),
                        const SizedBox(height: PyDS.sp2 + 2),
                        Text(
                          'Pyrita использует системное разрешение Android, '
                          'чтобы создать VPN-подключение на вашем устройстве. '
                          'После разрешения интернет-трафик может проходить '
                          'через серверы Pyrita для работы защищенного туннеля.',
                          style: PyDS.font(
                            size: 14.5,
                            weight: FontWeight.w500,
                            height: 1.5,
                            color: PyDS.textSoft,
                          ),
                        ),
                        const SizedBox(height: PyDS.sp6),
                        const _Section(
                          title: 'Для чего это нужно',
                          items: [
                            _Item(
                              icon: Icons.vpn_lock_outlined,
                              text: 'Создать VPN-туннель и направить '
                                  'подключение через выбранный сервер Pyrita.',
                            ),
                            _Item(
                              icon: Icons.speed_outlined,
                              text: 'Проверять технический статус подключения, '
                                  'лимит трафика и доступность вашего тарифа.',
                            ),
                            _Item(
                              icon: Icons.notifications_outlined,
                              text: 'Показать системное уведомление, чтобы вы '
                                  'видели, когда VPN включен, и могли его остановить.',
                            ),
                          ],
                          accent: PyDS.goldLight,
                        ),
                        const SizedBox(height: PyDS.sp4),
                        const _Section(
                          title: 'Что Pyrita НЕ делает',
                          items: [
                            _Item(
                              icon: Icons.campaign_outlined,
                              text: 'Не использует VPN для рекламы, продажи '
                                  'данных или рекламного трекинга.',
                            ),
                            _Item(
                              icon: Icons.edit_off_outlined,
                              text: 'Не меняет содержимое сайтов, сообщений '
                                  'или файлов, которые проходят через туннель.',
                            ),
                            _Item(
                              icon: Icons.history_toggle_off,
                              text: 'Не сохраняет историю сайтов для '
                                  'маркетинга или перепродажи данных.',
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
                        label: 'Разрешить VPN',
                        fontSize: 16,
                        onPressed: () => _onContinue(context),
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
