import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    // Pre-fill last logged-in email — небольшое удобство для re-open'а.
    AuthStorage.getCachedEmail().then((email) {
      if (email != null && mounted) {
        setState(() => _emailCtrl.text = email);
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _errorMsg = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await ApiClient.instance.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      context.go("/home");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: PyritaColors.obsidian,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: PyritaSpacing.xl,
            vertical: PyritaSpacing.xl3,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: PyritaSpacing.xl2),
                Text(
                  "PYRITA · ВХОД",
                  style: tt.labelSmall?.copyWith(color: PyritaColors.pyrite500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PyritaSpacing.md),
                Text(
                  "Войдите в аккаунт",
                  style: tt.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PyritaSpacing.xl2),
                _CardContainer(
                  child: Column(
                    children: [
                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: "Email",
                          hintText: "you@example.com",
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return "Введите email";
                          }
                          if (!v.contains("@")) {
                            return "Укажите корректный email";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: PyritaSpacing.lg),
                      // Password
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: !_passwordVisible,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: "Пароль",
                          hintText: "Ваш пароль",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: PyritaColors.paper55,
                            ),
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Введите пароль";
                          return null;
                        },
                      ),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: PyritaSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(PyritaSpacing.md),
                          decoration: BoxDecoration(
                            color: PyritaColors.destructive.withOpacity(0.1),
                            border: Border.all(
                              color: PyritaColors.destructive.withOpacity(0.4),
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
                      const SizedBox(height: PyritaSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: Text(_loading ? "Входим…" : "Войти"),
                        ),
                      ),
                      const SizedBox(height: PyritaSpacing.md),
                      // TODO: forgot password — связать с /forgot-password
                      // на pyrita-web, или сделать в-app экран. Phase B.
                      TextButton(
                        onPressed: () {
                          // Stub — открыть pyrita.com/forgot-password через
                          // url_launcher когда добавим dep
                        },
                        child: Text(
                          "Забыли пароль?",
                          style: tt.bodySmall?.copyWith(
                            color: PyritaColors.paper55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PyritaSpacing.xl),
                Text(
                  "Нет аккаунта? Зарегистрируйтесь на pyrita.com",
                  style: tt.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка в стиле dashboard'а (obsidian-2 surface + subtle border).
class _CardContainer extends StatelessWidget {
  const _CardContainer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PyritaSpacing.xl),
      decoration: BoxDecoration(
        color: PyritaColors.obsidian2,
        border: Border.all(color: PyritaColors.borderSubtle),
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusLg),
      ),
      child: child,
    );
  }
}
