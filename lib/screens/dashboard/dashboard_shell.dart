import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/data_refresh.dart';
import '../../providers/navigation_provider.dart';
import 'contests_tab.dart';
import 'home_tab.dart';
import 'practice_tab.dart';
import 'profile_tab.dart';
import 'progress_tab.dart';

/// Wraps the 5 bottom-nav tabs. Uses IndexedStack so each tab keeps
/// its scroll position / state when switching away and back.
class DashboardShell extends ConsumerWidget {
  const DashboardShell({super.key});

  static const _tabs = [
    HomeTab(),
    ProgressTab(),
    PracticeTab(),
    ContestsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(bottomNavIndexProvider);
    final cacheStatus = ref.watch(cacheStatusProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (cacheStatus.offline)
              _OfflineBanner(
                savedAt: cacheStatus.savedAt,
                onRetry: () => invalidateRemoteData(ref),
              ),
            Expanded(
              child: IndexedStack(index: index, children: _tabs),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => ref.read(bottomNavIndexProvider.notifier).state = i,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up_outlined),
            activeIcon: Icon(Icons.trending_up_rounded),
            label: 'Progress',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center_outlined),
            activeIcon: Icon(Icons.fitness_center_rounded),
            label: 'Practice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_outlined),
            activeIcon: Icon(Icons.emoji_events_rounded),
            label: 'Contests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// A thin strip shown above every tab when the last response came from disk.
class _OfflineBanner extends StatelessWidget {
  final DateTime? savedAt;
  final VoidCallback onRetry;

  const _OfflineBanner({required this.savedAt, required this.onRetry});

  static const _foreground = Color(0xFF92400E);
  static const _background = Color(0xFFFFF4E5);

  @override
  Widget build(BuildContext context) {
    final label = savedAt == null
        ? 'Offline · showing saved data'
        : 'Offline · saved ${DateFormat('MMM d, h:mm a').format(savedAt!)}';

    return Container(
      width: double.infinity,
      color: _background,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: _foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: _foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: _foreground,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
