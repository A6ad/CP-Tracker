import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final stats = ref.watch(statsProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text(user?.codeforcesHandle != null
              ? 'Hi, ${user!.codeforcesHandle}'
              : 'Dashboard'),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              stats.when(
                loading: () => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => _StatsError(message: errorMessage(err)),
                data: (s) => GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    StatCard(
                      label: 'Current Rating',
                      value: '${s.currentRating}',
                      icon: Icons.speed_rounded,
                      valueColor: AppColors.ratingColor(s.currentRating),
                    ),
                    StatCard(
                      label: 'Max Rating',
                      value: '${s.maxRating}',
                      icon: Icons.military_tech_rounded,
                      valueColor: AppColors.ratingColor(s.maxRating),
                    ),
                    StatCard(
                      label: 'Problems Solved',
                      value: '${s.problemsSolved}',
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    StatCard(
                      label: 'Current Streak',
                      value: '${s.currentStreak} days',
                      icon: Icons.local_fire_department_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Recent Activity',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ref.watch(recentSubmissionsProvider).when(
                    loading: () => const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => _StatsError(message: errorMessage(err)),
                    data: (submissions) => submissions.isEmpty
                        ? const Card(
                            child: ListTile(
                              leading: Icon(Icons.hourglass_empty_rounded,
                                  color: AppColors.textSecondary),
                              title: Text('No recent submissions'),
                            ),
                          )
                        : Card(
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: submissions.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1, color: AppColors.divider),
                              itemBuilder: (context, i) {
                                final s = submissions[i];
                                return ListTile(
                                  leading: Icon(
                                    s.solved
                                        ? Icons.check_circle
                                        : Icons.cancel_outlined,
                                    color: s.solved
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                  title: Text('${s.problemId} · ${s.problemName}'),
                                  subtitle: Text(
                                      '${s.solved ? 'Solved' : 'Attempted'} · ${s.relativeTime()}'),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded),
                                );
                              },
                            ),
                          ),
                  ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _StatsError extends StatelessWidget {
  final String message;

  const _StatsError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
