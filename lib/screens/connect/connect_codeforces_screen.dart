import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/codeforces_link_start.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../dashboard/dashboard_shell.dart';

/// Two-step handle linking: ask for the handle, then verify ownership by
/// checking that a one-time code appears in the public Codeforces profile.
class ConnectCodeforcesScreen extends ConsumerStatefulWidget {
  const ConnectCodeforcesScreen({super.key});

  @override
  ConsumerState<ConnectCodeforcesScreen> createState() =>
      _ConnectCodeforcesScreenState();
}

enum _Phase { handle, verify }

class _ConnectCodeforcesScreenState
    extends ConsumerState<ConnectCodeforcesScreen> {
  final _handle = TextEditingController();
  _Phase _phase = _Phase.handle;
  CodeforcesLinkStart? _link;
  bool _loading = false;
  String? _error;

  Future<void> _start() async {
    final handle = _handle.text.trim();
    if (handle.isEmpty) {
      setState(() => _error = 'Enter your Codeforces username');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final link =
          await ref.read(authProvider.notifier).startCodeforcesLink(handle);
      if (!mounted) return;
      setState(() {
        _link = link;
        _phase = _Phase.verify;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final link = _link;
    if (link == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .verifyCodeforcesLink(link.verificationCode);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardShell()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _useAnotherHandle() {
    setState(() {
      _phase = _Phase.handle;
      _link = null;
      _error = null;
    });
  }

  Future<void> _copyCode() async {
    final code = _link?.verificationCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verification code copied')),
    );
  }

  void _skip() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardShell()),
    );
  }

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
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
                child: const Icon(Icons.link_rounded,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              Text(
                _phase == _Phase.handle
                    ? 'Connect your Codeforces account'
                    : 'Verify you own @${link?.handle ?? ''}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _phase == _Phase.handle
                    ? 'Enter your Codeforces handle so we can pull your '
                        'rating, submissions, and contest history.'
                    : 'Add the code below to your public Codeforces profile, '
                        'then verify. You can remove it afterwards.',
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (_phase == _Phase.handle)
                TextField(
                  controller: _handle,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _start(),
                  decoration: const InputDecoration(
                    labelText: 'Codeforces username',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                )
              else if (link != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          link.verificationCode,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _copyCode,
                        tooltip: 'Copy code',
                        icon: const Icon(Icons.copy_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Where to put it',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Open codeforces.com/settings/social and paste the code into '
                  'the First name, Last name, or Organization field. Save the '
                  'page, then come back and verify.',
                  style: TextStyle(
                      color: AppColors.textSecondary, height: 1.4),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _phase == _Phase.handle
                    ? 'Get verification code'
                    : 'Verify & connect',
                loading: _loading,
                onPressed: _phase == _Phase.handle ? _start : _verify,
              ),
              if (_phase == _Phase.verify) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _useAnotherHandle,
                    child: const Text('Use a different handle'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _skip,
                    child: const Text('Skip for now'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
