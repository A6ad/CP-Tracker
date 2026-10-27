import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';
import '../settings/server_settings_screen.dart';
import '../splash/splash_screen.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final serverUrl = ref.watch(serverUrlProvider);

    return CustomScrollView(
      slivers: [
        const SliverAppBar(floating: true, title: Text('Profile')),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.person_rounded,
                            color: AppColors.primary, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.codeforcesHandle ?? 'Not connected',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(user?.email ?? '',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Personal Goals',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ref.watch(goalsProvider).when(
                    loading: () => const SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off_rounded,
                            color: AppColors.textSecondary),
                        title: Text(errorMessage(err)),
                        trailing: TextButton(
                          onPressed: () => ref.invalidate(goalsProvider),
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                    data: (goals) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(goals.hasTarget
                            ? 'Reach ${goals.targetRating} rating'
                            : 'No rating goal set'),
                        subtitle: goals.progress != null
                            ? Text(
                                '${(goals.progress! * 100).round()}% progress '
                                '(${goals.currentRating}/${goals.targetRating})')
                            : null,
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
              const Text('Streaks & Achievements',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ref.watch(goalsProvider).when(
                    loading: () => const SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off_rounded,
                            color: AppColors.textSecondary),
                        title: Text(errorMessage(err)),
                        trailing: TextButton(
                          onPressed: () => ref.invalidate(goalsProvider),
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                    data: (goals) => Card(
                      child: ListTile(
                        leading: const Icon(
                            Icons.local_fire_department_rounded,
                            color: Colors.orange),
                        title: Text(goals.streakDays == 1
                            ? '1-day solving streak'
                            : '${goals.streakDays}-day solving streak'),
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
              const Text('Settings',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('Server'),
                      subtitle: Text(
                        serverUrl.replaceFirst(RegExp(r'^https?://'), ''),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ServerSettingsScreen(),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    const ListTile(
                      leading: Icon(Icons.notifications_outlined),
                      title: Text('Notification Preferences'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    const ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Appearance'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    ListTile(
                      leading:
                          const Icon(Icons.logout_rounded, color: AppColors.error),
                      title: const Text('Log Out',
                          style: TextStyle(color: AppColors.error)),
                      onTap: () async {
                        await ref.read(authProvider.notifier).logout();
                        if (!context.mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const SplashScreen()),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
