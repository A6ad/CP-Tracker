import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../connect/connect_codeforces_screen.dart';
import '../dashboard/dashboard_shell.dart';
import '../splash/splash_screen.dart';

/// Blocks the app until the account's email address is proven.
///
/// The backend logs the code to its console in development; [devCode] is the
/// backend's dev-only echo so the flow is testable without an inbox.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;
  final String? devCode;

  const VerifyEmailScreen({super.key, required this.email, this.devCode});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  late final TextEditingController _code;
  late String? _devCode;
  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _code = TextEditingController(text: widget.devCode ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyEmail(widget.email, code);
      if (!mounted) return;
      final user = ref.read(authProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => (user?.hasLinkedCodeforces ?? false)
              ? const DashboardShell()
              : const ConnectCodeforcesScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      final result =
          await ref.read(authProvider.notifier).resendVerification(widget.email);
      if (!mounted) return;
      setState(() {
        _info = result.message;
        if (result.devVerificationCode != null) {
          _devCode = result.devVerificationCode;
          _code.text = result.devVerificationCode!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify your email',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a verification code to ${widget.email}. '
                'Enter it below to unlock your account.',
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4),
              ),
              if (_devCode != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Dev mode: no email backend is configured, so the code is '
                    '$_devCode.',
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verify(),
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              if (_info != null) ...[
                const SizedBox(height: 8),
                Text(_info!,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Verify email',
                loading: _loading,
                onPressed: _verify,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _resending ? null : _resend,
                  child: _resending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resend code'),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _logout,
                  child: const Text('Use a different account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
