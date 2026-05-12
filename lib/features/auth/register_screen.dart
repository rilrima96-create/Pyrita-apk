import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/py_app_icon.dart';
import '../../shared/widgets/py_button.dart';
import '../../shared/widgets/py_card.dart';

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
      setState(() => _errorMsg = 'Необходимо согласиться с условиями');
      return;
    }

    setState(() => _loading = true);
    try {
      await ApiClient.instance.register(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
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
                        onPressed: () => context.go('/login'),
                      ),
                    ),
                  ),
                  const SizedBox(height: PyDS.sp4),
                  Center(child: PyAppIcon(size: 64, animated: true)),
                  const SizedBox(height: PyDS.sp4 + 2),
                  Text(
                    'Создайте аккаунт',
                    textAlign: TextAlign.center,
                    style: PyDS.font(
                      size: 26,
                      weight: FontWeight.w800,
                      letterSpacing: -0.7,
                      color: PyDS.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: PyDS.font(
                        size: 13.5,
                        weight: FontWeight.w500,
                        height: 1.45,
                        color: PyDS.textSoft,
                      ),
                      children: [
                        const TextSpan(text: '14 дней '),
                        TextSpan(
                          text: 'бесплатно',
                          style: PyDS.font(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: PyDS.goldLight,
                          ),
                        ),
                        const TextSpan(text: '. Карта не нужна.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: PyDS.sp5),
                  PyCard(
                    padding: const EdgeInsets.all(PyDS.sp5),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newUsername],
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
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          style: PyDS.font(
                            size: 14.5,
                            weight: FontWeight.w600,
                            color: PyDS.text,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            hintText: 'Минимум 8 символов',
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
                            if (v == null || v.isEmpty) return 'Введите пароль';
                            if (v.length < 8) return 'Не менее 8 символов';
                            return null;
                          },
                        ),
                        const SizedBox(height: PyDS.sp3),
                        InkWell(
                          onTap: () => setState(() => _accept = !_accept),
                          borderRadius: BorderRadius.circular(PyDS.rSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    gradient:
                                        _accept ? PyDS.gradGold : null,
                                    color: _accept ? null : PyDS.bg2,
                                    borderRadius:
                                        BorderRadius.circular(5),
                                    border: Border.all(
                                      color: _accept
                                          ? Colors.transparent
                                          : PyDS.strokeStrong,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _accept
                                      ? const Icon(
                                          Icons.check,
                                          size: 12,
                                          color: Color(0xFF1A140A),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Принимаю оферту и политику '
                                    'конфиденциальности',
                                    style: PyDS.font(
                                      size: 12.5,
                                      weight: FontWeight.w500,
                                      height: 1.4,
                                      color: PyDS.textSoft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_errorMsg != null) ...[
                          const SizedBox(height: PyDS.sp3),
                          Container(
                            padding: const EdgeInsets.all(PyDS.sp3),
                            decoration: BoxDecoration(
                              color: PyDS.danger.withValues(alpha: 0.1),
                              border: Border.all(
                                color: PyDS.danger.withValues(alpha: 0.4),
                              ),
                              borderRadius:
                                  BorderRadius.circular(PyDS.rMd),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: PyDS.danger,
                                ),
                                const SizedBox(width: PyDS.sp2),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: PyDS.font(
                                      size: 12.5,
                                      weight: FontWeight.w600,
                                      color: PyDS.danger,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: PyDS.sp4),
                        PyButtonGold(
                          label: _loading ? 'Создаём…' : 'Создать аккаунт',
                          busy: _loading,
                          onPressed: _submit,
                          fontSize: 15,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PyDS.sp5),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'Уже есть аккаунт? ',
                          style: PyDS.font(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: PyDS.textSoft,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text(
                            'Войти',
                            style: PyDS.font(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: PyDS.goldLight,
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
