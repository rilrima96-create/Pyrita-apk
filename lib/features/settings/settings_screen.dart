import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/vpn_controller.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';
import '../../shared/widgets/py_tab_bar.dart';

/// «Настройки» — четвёртая tab после Account.
///
/// Перенесённые сюда блоки (из старого Account-экрана):
///   * Протоколы (read-only + manual switch reality/xhttp)
///   * Subscription URL (для других устройств)
///   * Email confirm (если ещё не подтверждён)
///   * Newsletter toggle
///   * Помощь (TG bot + ссылка на сайт)
///   * Удаление аккаунта
///   * About footer (версия, лицензии)
///
/// Что осталось в Account: profile head, plan card, usage row, devices
/// list (limit 3), referral card. Без перегрузки скроллом.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, dynamic>? _me;
  List<ProtocolInfo>? _protocols;

  @override
  void initState() {
    super.initState();
    _loadMe();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: Column(
            children: [
              const _SettingsTopBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: PyDS.sp3),
                  children: [
                    if (_me != null && _me!['email_confirmed_at'] == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: PyDS.sp4 + 2),
                        child: _EmailConfirmCard(onResent: _loadMe),
                      ),
                      const SizedBox(height: PyDS.sp4 + 2),
                    ],
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
                        'Тапни на доступный протокол — переключимся.',
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
                    const _SectionTitle('Помощь'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: PyDS.sp4 + 2),
                      child: const _HelpCard(),
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
      bottomNavigationBar: const PyTabBar(active: PyTab.settings),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp4 + 2,
        PyDS.sp3,
        PyDS.sp4 + 2,
        PyDS.sp2 - 2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Настройки',
          style: PyDS.font(
            size: 22,
            weight: FontWeight.w800,
            letterSpacing: -0.5,
            color: PyDS.text,
          ),
        ),
      ),
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

// ──────────────────────────────────────────────────────────────────────
// Помощь — Telegram-бот поддержки + ссылка на сайт. Новый раздел.
// ──────────────────────────────────────────────────────────────────────

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  static const _tgBotUrl = 'https://t.me/PyritaSupport_bot';
  static const _siteUrl = 'https://pyrita.com';

  Future<void> _openExternal(String url, BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PyCard(
      padding: const EdgeInsets.all(PyDS.sp4),
      radius: PyDS.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Если что-то не работает или есть вопросы — пишите боту '
            'поддержки в Telegram. Отвечаем обычно за час, в рабочее '
            'время — за минуты.',
            style: PyDS.font(
              size: 12.5,
              weight: FontWeight.w500,
              height: 1.45,
              color: PyDS.textSoft,
            ),
          ),
          const SizedBox(height: PyDS.sp3),
          PyButtonGold(
            label: 'Открыть бот в Telegram',
            icon: const Icon(Icons.chat_bubble_outline,
                size: 16, color: Color(0xFF1A140A)),
            height: 44,
            fontSize: 13.5,
            onPressed: () => _openExternal(_tgBotUrl, context),
          ),
          const SizedBox(height: PyDS.sp2 + 2),
          InkWell(
            onTap: () => _openExternal(_siteUrl, context),
            borderRadius: BorderRadius.circular(PyDS.rSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: PyDS.font(
                      size: 12,
                      weight: FontWeight.w500,
                      color: PyDS.textFaint,
                    ),
                    children: [
                      const TextSpan(text: 'Больше информации на нашем сайте '),
                      TextSpan(
                        text: 'pyrita.com',
                        style: PyDS.font(
                          size: 12,
                          weight: FontWeight.w600,
                          color: PyDS.goldLight,
                        ),
                      ),
                    ],
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

// ──────────────────────────────────────────────────────────────────────
// Протоколы — перенесено из Account. Switch logic в _ProtocolRow.
// ──────────────────────────────────────────────────────────────────────

class _ProtocolList extends StatelessWidget {
  const _ProtocolList({required this.protocols, required this.onReload});

  final List<ProtocolInfo>? protocols;
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
    final preferred = ref.read(vpnControllerProvider).preferredProtocolId;
    final isActive = info.id == preferred;
    final isAvailable = info.available;

    if (isActive) {
      _snack('Это активный протокол — его использует VPN на этом устройстве.');
      return;
    }
    if (!isAvailable) {
      _snack('Протокол ${info.name} ещё не настроен на сервере.');
      return;
    }
    if (!_switchableProtocolIds.contains(info.id)) {
      _snack(
        'Протокол ${info.name} пока не поддерживается на этом устройстве. '
        'Появится в одной из следующих версий.',
      );
      return;
    }

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

// ──────────────────────────────────────────────────────────────────────
// Email confirm, subscription URL+regenerate, newsletter toggle, delete
// account, about footer — перенесены из Account 1:1.
// ──────────────────────────────────────────────────────────────────────

class _EmailConfirmCard extends StatefulWidget {
  const _EmailConfirmCard({required this.onResent});
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

  String _shortenUrl(String url) {
    final clean = url.replaceFirst(RegExp(r'^https?://'), '');
    if (clean.length <= 36) return clean;
    return '${clean.substring(0, 32)}…';
  }
}

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
