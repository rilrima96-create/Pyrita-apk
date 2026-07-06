import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';

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
      TextInput.finishAutofillContext(shouldSave: true);
      context.go('/home');
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
    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: PyDS.sp4 + 2,
              vertical: PyDS.sp4,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: PyDS.sp7),
                  Center(child: PyAppIcon(size: 72, animated: true)),
                  const SizedBox(height: PyDS.sp5),
                  Text(
                    'С возвращением',
                    textAlign: TextAlign.center,
                    style: PyDS.font(
                      size: 28,
                      weight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: PyDS.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Войдите чтобы продолжить пользоваться Pyrita',
                    textAlign: TextAlign.center,
                    style: PyDS.font(
                      size: 13.5,
                      weight: FontWeight.w500,
                      height: 1.45,
                      color: PyDS.textSoft,
                    ),
                  ),
                  const SizedBox(height: PyDS.sp6),
                  AutofillGroup(
                    child: PyCard(
                      padding: const EdgeInsets.all(PyDS.sp5),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            style: PyDS.font(
                              size: 14.5,
                              weight: FontWeight.w600,
                              color: PyDS.text,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'you@example.com',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Введите email';
                              }
                              if (!v.contains('@')) {
                                return 'Укажите корректный email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: PyDS.sp3),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: !_passwordVisible,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            style: PyDS.font(
                              size: 14.5,
                              weight: FontWeight.w600,
                              color: PyDS.text,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              hintText: 'Ваш пароль',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: PyDS.textFaint,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _passwordVisible = !_passwordVisible,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Введите пароль';
                              }
                              return null;
                            },
                          ),
                          if (_errorMsg != null) ...[
                            const SizedBox(height: PyDS.sp3),
                            _ErrorBlock(message: _errorMsg!),
                          ],
                          const SizedBox(height: PyDS.sp4),
                          PyButtonGold(
                            label: _loading ? 'Входим…' : 'Войти',
                            busy: _loading,
                            onPressed: _submit,
                            fontSize: 15,
                          ),
                          const SizedBox(height: PyDS.sp2),
                          TextButton(
                            onPressed: () async {
                              final uri = Uri.parse(
                                  'https://pyrita.com/forgot-password');
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: PyDS.textSoft,
                              textStyle: PyDS.font(
                                size: 12.5,
                                weight: FontWeight.w500,
                              ),
                            ),
                            child: const Text('Забыли пароль?'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: PyDS.sp5),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'Нет аккаунта? ',
                          style: PyDS.font(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: PyDS.textSoft,
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.go('/register'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PyDS.sp2,
                              vertical: PyDS.sp3,
                            ),
                            child: Text(
                              'Создать',
                              style: PyDS.font(
                                size: 12.5,
                                weight: FontWeight.w700,
                                color: PyDS.goldLight,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PyDS.sp5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PyDS.sp3),
      decoration: BoxDecoration(
        color: PyDS.danger.withValues(alpha: 0.1),
        border: Border.all(color: PyDS.danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(PyDS.rMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: PyDS.danger),
          const SizedBox(width: PyDS.sp2),
          Expanded(
            child: Text(
              message,
              style: PyDS.font(
                size: 12.5,
                weight: FontWeight.w600,
                color: PyDS.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
