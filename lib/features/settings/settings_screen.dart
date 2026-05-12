import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';

/// Settings screen. Phase A minimum:
///   * Logout
///   * About (version, links)
///
/// Phase B будет добавлять:
///   * Profile section (email + confirm status, newsletter toggle)
///   * Regenerate sub URL
///   * Delete account
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _email;

  @override
  void initState() {
    super.initState();
    AuthStorage.getCachedEmail().then((v) {
      if (mounted) setState(() => _email = v);
    });
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PyritaSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile mini-card
              if (_email != null)
                _Section(
                  title: "АККАУНТ",
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: PyritaColors.pyrite500.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_outline,
                            size: 18, color: PyritaColors.pyrite500),
                      ),
                      const SizedBox(width: PyritaSpacing.md),
                      Expanded(
                        child: Text(_email!,
                            style: tt.bodyMedium
                                ?.copyWith(color: PyritaColors.paper)),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: PyritaSpacing.lg),

              _Section(
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

              const SizedBox(height: PyritaSpacing.lg),

              _Section(
                title: "О ПРИЛОЖЕНИИ",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Pyrita Android", style: tt.bodyMedium),
                    const SizedBox(height: 2),
                    Text("Версия 0.0.1 (build 1)", style: tt.bodySmall),
                    const SizedBox(height: PyritaSpacing.md),
                    Text(
                      "Поддержка: t.me/pyrita_support",
                      style: tt.bodySmall,
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
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
            style: tt.labelSmall,
          ),
          const SizedBox(height: PyritaSpacing.md),
          child,
        ],
      ),
    );
  }
}
