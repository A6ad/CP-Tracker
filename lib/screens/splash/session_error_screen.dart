import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/server_settings_screen.dart';
import 'start_route.dart';

/// Shown when a saved session exists but the backend cannot be reached.
///
/// Unlike a rejected token, a network failure must not sign the user out:
/// they get a retry, and their tokens stay on disk.
class SessionErrorScreen extends ConsumerStatefulWidget {
  const SessionErrorScreen({super.key});

  @override
  ConsumerState<SessionErrorScreen> createState() => _SessionErrorScreenState();
}

class _SessionErrorScreenState extends ConsumerState<SessionErrorScreen> {
  bool _retrying = false;
  String? _error;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _error = null;
    });

    final controller = ref.read(authProvider.notifier);
    await controller.restoreSession();
    if (!mounted) return;

    if (controller.restoreFailed) {
      setState(() {
        _retrying = false;
        _error = "Still can't reach the server. Check your connection.";
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => startScreenFor(ref.read(authProvider)),
      ),
    );
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  Future<void> _changeServer() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
    );
    if (changed == true && mounted) {
      await _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 20),
              const Text(
                "Can't reach the server",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your session is saved. Make sure this phone is on the same '
                'Wi-Fi as the CP Tracker server, or update the server address, '
                'then try again.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Retry',
                loading: _retrying,
                onPressed: _retry,
              ),
              TextButton(
                onPressed: _retrying ? null : _changeServer,
                child: const Text('Change server'),
              ),
              TextButton(
                onPressed: _retrying ? null : _logout,
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
