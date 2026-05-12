import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';

/// Settings — полный LK. Состоит из секций:
///   * Profile — read-only: email + confirm-status + дата регистрации + тариф
///   * Email confirmation — кнопка resend если не подтверждён
///   * Notifications — newsletter opt-in toggle
///   * Subscription — кнопка regenerate sub URL
///   * Logout
///   * Delete account — внизу, destructive
///
/// Все данные подтягиваем из /api/me. Изменения шлём отдельными
/// endpoints (PATCH /api/me/newsletter, POST /api/me/regenerate-sub, etc).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, dynamic>? _me;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiClient.instance.getMe();
      if (mounted) setState(() => _me = me);
    } on ApiException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          context.go("/login");
          return;
        }
        setState(() => _loadError = e.message);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PyritaColors.obsidian2,
        title: const Text("Выйти из аккаунта?"),
        content: const Text(
          "На этом устройстве вас разлогинит. Войдёте обратно по email и паролю в любое время.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Выйти"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ApiClient.instance.logout();
    if (!mounted) return;
    context.go("/login");
  }

  Future<void> _deleteAccount() async {
    final email = _me?["email"] as String?;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PyritaColors.obsidian2,
        title: const Text("Удалить аккаунт?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Это действие нельзя отменить. Подписка перестанет работать на всех устройствах. Marzban-пользователь удалится навсегда.",
            ),
            if (email != null) ...[
              const SizedBox(height: 12),
              Text("Аккаунт: $email",
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PyritaColors.destructive,
              foregroundColor: PyritaColors.paper,
            ),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiClient.instance.deleteAccount();
      if (!mounted) return;
      context.go("/login");
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: PyritaColors.destructive,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: PyritaColors.obsidian,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Настройки"),
      ),
      body: SafeArea(
        child: _me == null && _loadError == null
            ? const Center(
                child: CircularProgressIndicator(color: PyritaColors.pyrite500),
              )
            : _loadError != null
                ? _ErrorState(message: _loadError!, onRetry: _loadMe)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(PyritaSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileSection(me: _me!),
                        const SizedBox(height: PyritaSpacing.md),
                        if (_me!["email_confirmed_at"] == null)
                          _EmailConfirmSection(onResent: _loadMe),
                        if (_me!["email_confirmed_at"] == null)
                          const SizedBox(height: PyritaSpacing.md),
                        _NewsletterSection(
                          initialOptIn:
                              (_me!["newsletter_opt_in"] as int? ?? 1) == 1,
                        ),
                        const SizedBox(height: PyritaSpacing.md),
                        _SubscriptionSection(
                          subscriptionUrl: _me!["subscription_url"] as String?,
                          onRegenerated: _loadMe,
                        ),
                        const SizedBox(height: PyritaSpacing.md),
                        _SectionCard(
                          title: "ВЫХОД",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Вы сможете войти снова по тому же email и паролю.",
                                style: tt.bodySmall,
                              ),
                              const SizedBox(height: PyritaSpacing.md),
                              OutlinedButton(
                                onPressed: _logout,
                                child: const Text("Выйти из аккаунта"),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: PyritaSpacing.md),
                        _SectionCard(
                          title: "О ПРИЛОЖЕНИИ",
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Pyrita Android", style: tt.bodyMedium),
                              const SizedBox(height: 2),
                              Text("Версия 0.0.1 (build 1)",
                                  style: tt.bodySmall),
                              const SizedBox(height: PyritaSpacing.md),
                              Text("Поддержка: t.me/pyrita_support",
                                  style: tt.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(height: PyritaSpacing.md),
                        _SectionCard(
                          title: "УДАЛИТЬ АККАУНТ",
                          titleColor: PyritaColors.destructive,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Действие нельзя отменить. Подписка перестанет работать.",
                                style: tt.bodySmall,
                              ),
                              const SizedBox(height: PyritaSpacing.md),
                              OutlinedButton(
                                onPressed: _deleteAccount,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: PyritaColors.destructive,
                                  side: BorderSide(
                                    color: PyritaColors.destructive
                                        .withOpacity(0.4),
                                  ),
                                ),
                                child: const Text("Удалить навсегда"),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Section: Profile
// ──────────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.me});
  final Map<String, dynamic> me;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final email = me["email"] as String;
    final confirmed = me["email_confirmed_at"] != null;
    final trialEndsAt = me["trial_ends_at"] as int?;
    final status = me["subscription_status"] as Map?;

    final createdDate = trialEndsAt != null
        ? DateTime.fromMillisecondsSinceEpoch(trialEndsAt)
            .subtract(const Duration(days: 14))
        : null;

    final planLabel = _planLabel(status);

    return _SectionCard(
      title: "АККАУНТ",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, "Email", null, valueWidget: Row(
            children: [
              Flexible(child: Text(email, style: tt.bodyMedium)),
              const SizedBox(width: PyritaSpacing.xs),
              Icon(
                confirmed
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 14,
                color: confirmed
                    ? PyritaColors.success
                    : PyritaColors.pyrite300,
              ),
            ],
          )),
          if (createdDate != null) ...[
            const SizedBox(height: PyritaSpacing.sm),
            _row(
              context,
              "Регистрация",
              DateFormat("d MMMM y", "ru_RU").format(createdDate),
            ),
          ],
          const SizedBox(height: PyritaSpacing.sm),
          _row(context, "Тариф", planLabel),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value,
      {Widget? valueWidget}) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: tt.bodySmall),
        ),
        Expanded(
          child: valueWidget ?? Text(value ?? "—", style: tt.bodyMedium),
        ),
      ],
    );
  }

  String _planLabel(Map? status) {
    if (status == null) return "—";
    final kind = status["kind"] as String?;
    if (kind == "trial") return "Пробный период";
    if (kind == "expired") return "Подписка истекла";
    if (kind == "paid") {
      final planId = status["plan_id"] as String?;
      return planId == "1m"
          ? "1 месяц"
          : planId == "3m"
              ? "3 месяца"
              : planId == "6m"
                  ? "6 месяцев"
                  : planId == "12m"
                      ? "12 месяцев"
                      : "Активна";
    }
    return "—";
  }
}

// ──────────────────────────────────────────────────────────────────────
// Section: Email confirmation (shown only if !confirmed)
// ──────────────────────────────────────────────────────────────────────

class _EmailConfirmSection extends StatefulWidget {
  const _EmailConfirmSection({required this.onResent});
  final VoidCallback onResent;

  @override
  State<_EmailConfirmSection> createState() => _EmailConfirmSectionState();
}

class _EmailConfirmSectionState extends State<_EmailConfirmSection> {
  bool _sending = false;
  String? _message;
  bool _success = false;

  Future<void> _resend() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await ApiClient.instance.resendEmailConfirmation();
      if (!mounted) return;
      setState(() {
        _success = true;
        _message =
            "Письмо отправлено. Проверьте папку «Спам» если не пришло за минуту.";
        _sending = false;
      });
      widget.onResent();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = e.message;
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _SectionCard(
      title: "ПОДТВЕРДИТЕ EMAIL",
      titleColor: PyritaColors.pyrite300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Подтвердите email — нам понадобится отправлять важные уведомления (тех. работы, чеки об оплате).",
            style: tt.bodySmall,
          ),
          if (_message != null) ...[
            const SizedBox(height: PyritaSpacing.md),
            Text(
              _message!,
              style: tt.bodySmall?.copyWith(
                color:
                    _success ? PyritaColors.success : PyritaColors.destructive,
              ),
            ),
          ],
          const SizedBox(height: PyritaSpacing.md),
          ElevatedButton(
            onPressed: _sending ? null : _resend,
            child: Text(_sending ? "Отправляем…" : "Отправить ещё раз"),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Section: Newsletter toggle
// ──────────────────────────────────────────────────────────────────────

class _NewsletterSection extends StatefulWidget {
  const _NewsletterSection({required this.initialOptIn});
  final bool initialOptIn;

  @override
  State<_NewsletterSection> createState() => _NewsletterSectionState();
}

class _NewsletterSectionState extends State<_NewsletterSection> {
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
    final tt = Theme.of(context).textTheme;
    return _SectionCard(
      title: "УВЕДОМЛЕНИЯ",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            value: _optIn,
            onChanged: _busy ? null : _toggle,
            activeColor: PyritaColors.pyrite500,
            contentPadding: EdgeInsets.zero,
            title: Text(
              "Email о тех. работах и важных новостях",
              style: tt.bodyMedium,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: PyritaSpacing.xs),
            Text(_error!,
                style: tt.bodySmall
                    ?.copyWith(color: PyritaColors.destructive)),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Section: Subscription URL + regenerate
// ──────────────────────────────────────────────────────────────────────

class _SubscriptionSection extends StatefulWidget {
  const _SubscriptionSection({
    required this.subscriptionUrl,
    required this.onRegenerated,
  });
  final String? subscriptionUrl;
  final VoidCallback onRegenerated;

  @override
  State<_SubscriptionSection> createState() => _SubscriptionSectionState();
}

class _SubscriptionSectionState extends State<_SubscriptionSection> {
  bool _busy = false;

  Future<void> _copy() async {
    final url = widget.subscriptionUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ссылка скопирована"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PyritaColors.obsidian2,
        title: const Text("Перевыпустить ссылку?"),
        content: const Text(
          "Старая ссылка перестанет работать сразу. После этого надо будет переимпортировать профиль во всех клиентах. Используйте если думаете, что URL утёк.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Отмена"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Перевыпустить"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiClient.instance.regenerateSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ссылка обновлена")),
        );
        widget.onRegenerated();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: PyritaColors.destructive,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _SectionCard(
      title: "ПОДПИСКА",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Ссылка для других устройств (Hiddify, sing-box). На этом телефоне Pyrita использует её автоматически.",
            style: tt.bodySmall,
          ),
          const SizedBox(height: PyritaSpacing.md),
          OutlinedButton.icon(
            onPressed: widget.subscriptionUrl == null ? null : _copy,
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text("Скопировать ссылку"),
          ),
          const SizedBox(height: PyritaSpacing.sm),
          TextButton(
            onPressed: _busy ? null : _regenerate,
            child: Text(
              _busy ? "Перевыпускаем…" : "Перевыпустить ссылку",
              style: tt.bodySmall?.copyWith(color: PyritaColors.paper55),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Shared widgets
// ──────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.titleColor,
  });
  final String title;
  final Widget child;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(PyritaSpacing.lg),
      decoration: BoxDecoration(
        color: PyritaColors.obsidian2,
        border: Border.all(color: PyritaColors.borderSubtle),
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: tt.labelSmall?.copyWith(color: titleColor),
          ),
          const SizedBox(height: PyritaSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PyritaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: PyritaColors.destructive, size: 32),
            const SizedBox(height: PyritaSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: PyritaSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text("Повторить")),
          ],
        ),
      ),
    );
  }
}
