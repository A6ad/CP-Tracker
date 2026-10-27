import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'session_error_screen.dart';
import 'start_route.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final minimumDelay = Future.delayed(const Duration(milliseconds: 1200));
    final controller = ref.read(authProvider.notifier);
    await controller.restoreSession();
    await minimumDelay;

    if (!mounted) return;
    final user = ref.read(authProvider);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => user == null && controller.restoreFailed
            ? const SessionErrorScreen()
            : startScreenFor(user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/images/codeforces_logo.png',
                width: 56,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'CP Tracker',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Track your Codeforces journey',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
