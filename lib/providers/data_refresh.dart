import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Drops every cached network result so the visible tabs refetch.
///
/// Used by the offline banner's Retry and after the server URL changes.
void invalidateRemoteData(WidgetRef ref) {
  ref.invalidate(statsProvider);
  ref.invalidate(goalsProvider);
  ref.invalidate(recentSubmissionsProvider);
  ref.invalidate(ratingHistoryProvider);
  ref.invalidate(solvedByRatingProvider);
  ref.invalidate(topicsProvider);
  ref.invalidate(practiceProblemsProvider);
  ref.invalidate(contestsProvider);
}
