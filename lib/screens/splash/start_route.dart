import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../auth/verify_email_screen.dart';
import '../connect/connect_codeforces_screen.dart';
import '../dashboard/dashboard_shell.dart';
import '../onboarding/onboarding_screen.dart';

/// Chooses the first screen for a restored session.
///
/// Mirrors the real-world gate order: prove the email, then link a handle,
/// then use the dashboard.
Widget startScreenFor(AppUser? user) {
  if (user == null) return const OnboardingScreen();
  if (!user.emailVerified) return VerifyEmailScreen(email: user.email);
  if (!user.hasLinkedCodeforces) return const ConnectCodeforcesScreen();
  return const DashboardShell();
}
