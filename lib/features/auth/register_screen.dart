import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  bool _accept = false;
  String? _errorMsg;

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
    if (!_accept) {
      setState(() => _errorMsg = "Необходимо согласиться с условиями");
      return;
    }

    setState(() => _loading = true);
    try {
      await ApiClient.instance.register(
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: PyritaColors.paper70,
          onPressed: () => context.go("/login"),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: PyritaSpacing.xl,
            vertical: PyritaSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "PYRITA · РЕГИСТРАЦИЯ",
                  style: tt.labelSmall?.copyWith(color: PyritaColors.pyrite500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PyritaSpacing.md),
                Text(
                  "Создайте аккаунт",
                  style: tt.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PyritaSpacing.md),
                Text(
                  "14 дней бесплатно. Карта не нужна.",
                  style: tt.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: PyritaSpacing.xl2),
                Container(
                  padding: const EdgeInsets.all(PyritaSpacing.xl),
                  decoration: BoxDecoration(
                    color: PyritaColors.obsidian2,
                    border: Border.all(color: PyritaColors.borderSubtle),
                    borderRadius:
                        BorderRadius.circular(PyritaSpacing.radiusLg),
                  ),
                  child: Column(
                    children: [
                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newUsername],
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
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: "Пароль",
                          hintText: "Минимум 8 символов",
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
                          if (v.length < 8) {
                            return "Не менее 8 символов";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: PyritaSpacing.lg),

                      // Accept terms
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _accept,
                            onChanged: (v) => setState(() => _accept = v ?? false),
                            activeColor: PyritaColors.pyrite500,
                            checkColor: PyritaColors.obsidian,
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _accept = !_accept),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  "Принимаю оферту и политику конфиденциальности",
                                  style: tt.bodySmall,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_errorMsg != null) ...[
                        const SizedBox(height: PyritaSpacing.md),
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

                      const SizedBox(height: PyritaSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: Text(_loading ? "Создаём…" : "Создать аккаунт"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PyritaSpacing.xl),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text("Уже есть аккаунт? ", style: tt.bodySmall),
                      GestureDetector(
                        onTap: () => context.go("/login"),
                        child: Text(
                          "Войти",
                          style: tt.bodySmall?.copyWith(
                            color: PyritaColors.pyrite500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
