import 'dart:ui';

import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../widgets/app_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.authController, super.key});

  final AppAuthController authController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _codeFocusNode = FocusNode();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
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
      successMessage: 'You are signed in now.',
    );
  }

  Future<void> _signInWithApple() async {
    await _runAuthAction(
      widget.authController.signInWithApple,
      successMessage: 'Apple sign in completed.',
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
                      const SizedBox(height: 12),
                      Text(
                        'Create your account with a phone number or Apple ID before entering the app. Once you are signed in, we will keep you signed in until you log out in Settings.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _LoginHeroCard(theme: theme),
                      const SizedBox(height: 24),
                      SoftCard(
                        color: Colors.white.withValues(alpha: 0.84),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Phone number',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use your full international number, like +1 555 123 4567.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            _BlurTextField(
                              controller: _phoneController,
                              focusNode: _phoneFocusNode,
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
                                onPressed: authController.isBusy
                                    ? null
                                    : _sendPhoneCode,
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
                                    Text(
                                      'Verification code',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 10),
                                    _BlurTextField(
                                      controller: _codeController,
                                      focusNode: _codeFocusNode,
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
                                        onPressed: authController.isBusy
                                            ? null
                                            : _verifyCode,
                                        child: const Text('Confirm and enter'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (authController.supportsAppleSignIn) ...[
                        const SizedBox(height: 18),
                        SoftCard(
                          color: Colors.white.withValues(alpha: 0.84),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Apple ID',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'A soft one-tap option for people already on iPhone.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: authController.isBusy
                                      ? null
                                      : _signInWithApple,
                                  icon: const Icon(Icons.apple),
                                  label: const Text('Continue with Apple'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'Without signing in, the app stays locked on this welcome screen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.clay,
                          fontWeight: FontWeight.w700,
                        ),
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

class _LoginHeroCard extends StatelessWidget {
  const _LoginHeroCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF7F1), Color(0xFFF7E3D4), Color(0xFFF4D8C2)],
        ),
        border: Border.all(color: AppColors.stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MiniChip(
                icon: Icons.lock_rounded,
                label: 'Private account gate',
              ),
              const Spacer(),
              Text(
                'Secure entry',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.clay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Let each person enter through their own account.',
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 31),
          ),
          const SizedBox(height: 10),
          Text(
            'The room, hall, chat, and profile stay behind this first door until registration is complete.',
            style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.clay),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.clay),
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final IconData prefixIcon;

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
