import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/contest.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_exception.dart';
import '../../theme/app_theme.dart';

/// Upcoming and finished Codeforces rounds from the public contest list.
class ContestsTab extends ConsumerWidget {
  const ContestsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contests = ref.watch(contestsProvider);

    return DefaultTabController(
      length: 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            floating: true,
            title: const Text('Contests'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(contestsProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            bottom: const TabBar(
              tabs: [Tab(text: 'Upcoming'), Tab(text: 'History')],
            ),
          ),
        ],
        body: contests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ContestsMessage(
            icon: Icons.cloud_off_outlined,
            message: errorMessage(error),
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(contestsProvider),
          ),
          data: (result) => TabBarView(
            children: [
              _ContestList(
                contests: result.upcoming,
                emptyMessage: 'No upcoming contests scheduled right now.',
                upcoming: true,
              ),
              _ContestList(
                contests: result.finished,
                emptyMessage: 'No finished contests found.',
                upcoming: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContestList extends StatelessWidget {
  final List<CfContest> contests;
  final String emptyMessage;
  final bool upcoming;

  const _ContestList({
    required this.contests,
    required this.emptyMessage,
    required this.upcoming,
  });

  @override
  Widget build(BuildContext context) {
    if (contests.isEmpty) {
      return _ContestsMessage(
        icon: Icons.event_busy_rounded,
        message: emptyMessage,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: contests.length,
      itemBuilder: (context, i) => _ContestCard(
        contest: contests[i],
        upcoming: upcoming,
      ),
    );
  }
}

class _ContestCard extends StatelessWidget {
  final CfContest contest;
  final bool upcoming;

  const _ContestCard({required this.contest, required this.upcoming});

  Future<void> _open(BuildContext context) async {
    try {
      final opened = await launchUrl(
        Uri.parse(contest.url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        _snack(context, 'Could not open Codeforces.');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not open Codeforces.');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final running = contest.isRunning;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: running
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.primary.withValues(alpha: 0.10),
          child: Icon(
            running ? Icons.play_arrow_rounded : Icons.emoji_events_outlined,
            color: running ? AppColors.success : AppColors.primary,
            size: 22,
          ),
        ),
        title: Text(
          contest.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            upcoming ? _upcomingLabel(contest) : _finishedLabel(contest),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => _open(context),
      ),
    );
  }
}

String _upcomingLabel(CfContest contest) {
  if (contest.isRunning) {
    return 'In progress · ends ${DateFormat('MMM d, HH:mm').format(
      contest.startTime.add(Duration(seconds: contest.durationSeconds)),
    )}';
  }

  final remaining = contest.startTime.difference(DateTime.now());
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  final relative = days > 0
      ? '${days}d ${hours}h'
      : hours > 0
          ? '${hours}h ${minutes}m'
          : '${minutes}m';

  return 'Starts in $relative · ${DateFormat('MMM d, HH:mm').format(contest.startTime)}';
}

String _finishedLabel(CfContest contest) {
  final hours = contest.durationSeconds ~/ 3600;
  final minutes = (contest.durationSeconds % 3600) ~/ 60;
  final duration = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

  return 'Ended ${DateFormat('MMM d, yyyy').format(contest.startTime)} · $duration';
}

class _ContestsMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ContestsMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
