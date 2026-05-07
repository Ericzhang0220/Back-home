import 'dart:ui';

import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../widgets/app_ui.dart';

enum _AccountFlow { signIn, create }

enum _AuthMethod { phone, apple, email }

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.authController, super.key});

  final AppAuthController authController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _codeFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  _AccountFlow _flow = _AccountFlow.signIn;
  _AuthMethod _method = _AuthMethod.phone;
  bool _emailVerificationSent = false;
  bool _emailVerifiedForCreation = false;

  @override
  void initState() {
    super.initState();
    if (widget.authController.needsEmailVerification ||
        widget.authController.needsEmailPasswordSetup) {
      _flow = _AccountFlow.create;
      _method = _AuthMethod.email;
      _emailVerificationSent = true;
      _emailVerifiedForCreation =
          widget.authController.currentUser?.emailVerified ?? false;
      _emailController.text = widget.authController.currentUser?.email ?? '';
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendPhoneCode() async {
    await _runAuthAction(
      () => widget.authController.sendPhoneCode(_phoneController.text),
      successMessage: widget.authController.hasPendingPhoneCode
          ? 'Code sent. Enter the 6-digit code to continue.'
          : null,
      afterSuccess: () {
        if (widget.authController.hasPendingPhoneCode) {
          _codeFocusNode.requestFocus();
        }
      },
    );
  }

  Future<void> _verifyCode() async {
    await _runAuthAction(
      () => widget.authController.verifySmsCode(_codeController.text),
    );
  }

  Future<void> _signInWithApple() async {
    await _runAuthAction(widget.authController.signInWithApple);
  }

  Future<void> _signInWithEmail() async {
    await _runAuthAction(
      () => widget.authController.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      ),
    );
  }

  Future<void> _createEmailAccount() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('Please enter the same password twice.');
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    await _runAuthAction(
      () => widget.authController.finishVerifiedEmailAccount(
        password: _passwordController.text,
      ),
      afterSuccess: () {
        ScaffoldMessenger.of(context).clearSnackBars();
      },
    );
  }

  Future<void> _sendEmailCreationVerification() async {
    await _runAuthAction(
      () => widget.authController.sendEmailCreationVerification(
        _emailController.text,
      ),
      successMessage: 'Verification email sent. Open it before continuing.',
      afterSuccess: () {
        setState(() {
          _emailVerificationSent = true;
          _emailVerifiedForCreation = false;
        });
      },
    );
  }

  Future<void> _confirmEmailCreationVerification() async {
    await _runAuthAction(
      widget.authController.confirmEmailCreationVerification,
      successMessage: 'Email verified. Now create your password.',
      afterSuccess: () {
        setState(() {
          _emailVerifiedForCreation = true;
        });
        _passwordFocusNode.requestFocus();
      },
    );
  }

  Future<void> _runAuthAction(
    Future<void> Function() action, {
    String? successMessage,
    VoidCallback? afterSuccess,
  }) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      if (successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      afterSuccess?.call();
    } on AuthFlowException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authController = widget.authController;

    return AnimatedBuilder(
      animation: authController,
      builder: (context, _) {
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              const AmbientBackground(showSideGlow: true),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.stroke),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: AppColors.clay,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Welcome back home',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontSize: 38,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Choose how you want to continue',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _FlowCard(
                              icon: Icons.login_rounded,
                              title: 'Sign in',
                              subtitle: 'Use an existing account',
                              selected: _flow == _AccountFlow.signIn,
                              onTap: authController.isBusy
                                  ? null
                                  : () => setState(() {
                                      _flow = _AccountFlow.signIn;
                                    }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FlowCard(
                              icon: Icons.person_add_alt_1_rounded,
                              title: 'Create',
                              subtitle: 'Start a new account',
                              selected: _flow == _AccountFlow.create,
                              onTap: authController.isBusy
                                  ? null
                                  : () => setState(() {
                                      _flow = _AccountFlow.create;
                                    }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _MethodPicker(
                        selectedMethod: _method,
                        onSelected: authController.isBusy
                            ? null
                            : (method) {
                                setState(() {
                                  _method = method;
                                });
                                if (method == _AuthMethod.apple) {
                                  _signInWithApple();
                                }
                              },
                      ),
                      const SizedBox(height: 18),
                      if (_method == _AuthMethod.phone)
                        _PhoneCard(
                          flow: _flow,
                          authController: authController,
                          phoneController: _phoneController,
                          codeController: _codeController,
                          phoneFocusNode: _phoneFocusNode,
                          codeFocusNode: _codeFocusNode,
                          onSendCode: _sendPhoneCode,
                          onVerifyCode: _verifyCode,
                        ),
                      if (_method == _AuthMethod.apple)
                        _AppleCard(flow: _flow, onPressed: _signInWithApple),
                      if (_method == _AuthMethod.email)
                        _EmailCard(
                          flow: _flow,
                          authController: authController,
                          verificationSent: _emailVerificationSent,
                          emailVerifiedForCreation: _emailVerifiedForCreation,
                          emailController: _emailController,
                          passwordController: _passwordController,
                          confirmPasswordController: _confirmPasswordController,
                          emailFocusNode: _emailFocusNode,
                          passwordFocusNode: _passwordFocusNode,
                          confirmPasswordFocusNode: _confirmPasswordFocusNode,
                          onSubmit: _flow == _AccountFlow.create
                              ? _createEmailAccount
                              : _signInWithEmail,
                          onSendVerification: _sendEmailCreationVerification,
                          onConfirmVerification:
                              _confirmEmailCreationVerification,
                        ),
                    ],
                  ),
                ),
              ),
              if (authController.isBusy)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.28),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.clay.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.clay : AppColors.stroke,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.clay),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.selectedMethod, required this.onSelected});

  final _AuthMethod selectedMethod;
  final ValueChanged<_AuthMethod>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _MethodButton(
          icon: Icons.phone_rounded,
          label: 'Phone',
          selected: selectedMethod == _AuthMethod.phone,
          onPressed: onSelected == null
              ? null
              : () => onSelected!(_AuthMethod.phone),
        ),
        _MethodButton(
          icon: Icons.apple,
          label: 'Apple',
          selected: selectedMethod == _AuthMethod.apple,
          onPressed: onSelected == null
              ? null
              : () => onSelected!(_AuthMethod.apple),
        ),
        _MethodButton(
          icon: Icons.mail_rounded,
          label: 'Email',
          selected: selectedMethod == _AuthMethod.email,
          onPressed: onSelected == null
              ? null
              : () => onSelected!(_AuthMethod.email),
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? AppColors.clay : Colors.white,
          foregroundColor: selected ? Colors.white : AppColors.clay,
          fixedSize: const Size(76, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? AppColors.clay : AppColors.stroke,
            ),
          ),
          elevation: selected ? 2 : 0,
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({
    required this.flow,
    required this.authController,
    required this.phoneController,
    required this.codeController,
    required this.phoneFocusNode,
    required this.codeFocusNode,
    required this.onSendCode,
    required this.onVerifyCode,
  });

  final _AccountFlow flow;
  final AppAuthController authController;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final FocusNode phoneFocusNode;
  final FocusNode codeFocusNode;
  final VoidCallback onSendCode;
  final VoidCallback onVerifyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      color: Colors.white.withValues(alpha: 0.84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phone number', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            flow == _AccountFlow.create
                ? 'Create your account by receiving a verification code on your phone.'
                : 'Use your full international number, like +1 555 123 4567.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _BlurTextField(
            controller: phoneController,
            focusNode: phoneFocusNode,
            enabled: !authController.isBusy,
            hintText: '+1 555 123 4567',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.phone_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: authController.isBusy ? null : onSendCode,
              child: Text(
                authController.hasPendingPhoneCode
                    ? 'Resend code'
                    : 'Send code',
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: authController.hasPendingPhoneCode
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 12),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verification code', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _BlurTextField(
                    controller: codeController,
                    focusNode: codeFocusNode,
                    enabled: !authController.isBusy,
                    hintText: 'Enter 6-digit code',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    prefixIcon: Icons.verified_user_rounded,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: authController.isBusy ? null : onVerifyCode,
                      child: Text(
                        flow == _AccountFlow.create
                            ? 'Confirm and create'
                            : 'Confirm and enter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleCard extends StatelessWidget {
  const _AppleCard({required this.flow, required this.onPressed});

  final _AccountFlow flow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      color: Colors.white.withValues(alpha: 0.84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Apple ID', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            flow == _AccountFlow.create
                ? 'Create your account after Apple ID authentication, password, or Face ID.'
                : 'Sign in with your Apple ID password or Face ID.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.apple),
              label: Text(
                flow == _AccountFlow.create
                    ? 'Authenticate and create'
                    : 'Continue with Apple',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailCard extends StatelessWidget {
  const _EmailCard({
    required this.flow,
    required this.authController,
    required this.verificationSent,
    required this.emailVerifiedForCreation,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.confirmPasswordFocusNode,
    required this.onSubmit,
    required this.onSendVerification,
    required this.onConfirmVerification,
  });

  final _AccountFlow flow;
  final AppAuthController authController;
  final bool verificationSent;
  final bool emailVerifiedForCreation;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final FocusNode confirmPasswordFocusNode;
  final VoidCallback onSubmit;
  final VoidCallback onSendVerification;
  final VoidCallback onConfirmVerification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCreating = flow == _AccountFlow.create;
    final canEditPassword = !isCreating || emailVerifiedForCreation;

    return SoftCard(
      color: Colors.white.withValues(alpha: 0.84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            isCreating
                ? 'Verify your email first. Password fields unlock after verification.'
                : 'Sign in with your email and password.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _BlurTextField(
            controller: emailController,
            focusNode: emailFocusNode,
            enabled: !authController.isBusy,
            hintText: 'Email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.mail_rounded,
          ),
          if (isCreating) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: authController.isBusy ? null : onSendVerification,
                child: Text(
                  verificationSent
                      ? 'Resend verification email'
                      : 'Send verification email',
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: verificationSent
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(height: 12),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: authController.isBusy
                        ? null
                        : onConfirmVerification,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('I verified my email'),
                  ),
                ),
              ),
            ),
          ],
          if (canEditPassword) ...[
            const SizedBox(height: 14),
            _BlurTextField(
              controller: passwordController,
              focusNode: passwordFocusNode,
              enabled: !authController.isBusy,
              hintText: 'Password',
              keyboardType: TextInputType.visiblePassword,
              textInputAction: isCreating
                  ? TextInputAction.next
                  : TextInputAction.done,
              prefixIcon: Icons.key_rounded,
              obscureText: true,
            ),
          ],
          if (isCreating && emailVerifiedForCreation) ...[
            const SizedBox(height: 14),
            _BlurTextField(
              controller: confirmPasswordController,
              focusNode: confirmPasswordFocusNode,
              enabled: !authController.isBusy,
              hintText: 'Enter password again',
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.lock_reset_rounded,
              obscureText: true,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: authController.isBusy || !canEditPassword
                  ? null
                  : onSubmit,
              child: Text(isCreating ? 'Create with email' : 'Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurTextField extends StatelessWidget {
  const _BlurTextField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.keyboardType,
    required this.textInputAction,
    required this.prefixIcon,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final IconData prefixIcon;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted.withValues(alpha: 0.92),
            ),
            prefixIcon: Icon(prefixIcon, color: AppColors.clay),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.78),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: AppColors.stroke),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: AppColors.stroke),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: AppColors.clay, width: 1.3),
            ),
          ),
        ),
      ),
    );
  }
}
