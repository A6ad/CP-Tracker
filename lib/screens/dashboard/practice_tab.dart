import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/practice_problem.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';

/// Unsolved problems near the user's rating, straight from the Codeforces
/// problemset. Opening a problem hands off to the Codeforces website/app.
class PracticeTab extends ConsumerStatefulWidget {
  const PracticeTab({super.key});

  @override
  ConsumerState<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends ConsumerState<PracticeTab> {
  static const _modes = <String, String>{
    'recommended': 'For you',
    'unsolved': 'Unsolved',
    'harder': 'Harder',
    'random': 'Random',
  };

  String _mode = 'recommended';

  void _refresh() => ref.invalidate(practiceProblemsProvider(_mode));

  Future<void> _open(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _snack('Could not open Codeforces.');
    } catch (_) {
      if (mounted) _snack('Could not open Codeforces.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(practiceProblemsProvider(_mode));

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Practice'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _modes.entries
                  .map(
                    (entry) => ChoiceChip(
                      label: Text(entry.value),
                      selected: _mode == entry.key,
                      onSelected: (_) => setState(() => _mode = entry.key),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          sliver: SliverToBoxAdapter(
            child: async.maybeWhen(
              data: (result) => Text(
                result.rating == null
                    ? 'Unsolved problems from the Codeforces problemset'
                    : 'Unsolved problems around ${result.rating} rating',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              orElse: () => const Text(
                'Unsolved problems you have not attempted yet',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        ...async.when(
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _PracticeMessage(
                icon: Icons.cloud_off_outlined,
                message: errorMessage(error),
                actionLabel: 'Retry',
                onAction: _refresh,
              ),
            ),
          ],
          data: (result) {
            if (result.problems.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _PracticeMessage(
                    icon: Icons.search_off_rounded,
                    message:
                        'No unsolved problems match this filter. Try another one.',
                    actionLabel: 'Refresh',
                    onAction: _refresh,
                  ),
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final problem = result.problems[i];
                      return _ProblemCard(
                        problem: problem,
                        onTap: () => _open(problem.url),
                      );
                    },
                    childCount: result.problems.length,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}

class _ProblemCard extends StatelessWidget {
  final PracticeProblem problem;
  final VoidCallback onTap;

  const _ProblemCard({required this.problem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rating = problem.rating;
    final color = rating == null
        ? AppColors.textSecondary
        : AppColors.ratingColor(rating);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            rating?.toString() ?? '—',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        title: Text(
          '${problem.problemId} · ${problem.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
        subtitle: problem.tags.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  problem.tags.take(3).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _PracticeMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PracticeMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
