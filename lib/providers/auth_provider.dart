import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/codeforces_link_start.dart';
import '../models/contest.dart';
import '../models/practice_problem.dart';
import '../models/rating_bucket.dart';
import '../models/rating_point.dart';
import '../models/recent_submission.dart';
import '../models/topic_stat.dart';
import '../models/user_goals.dart';
import '../models/user_model.dart';
import '../models/user_stats.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/cache_status.dart';
import '../services/local_cache.dart';
import '../services/server_config.dart';
import '../services/token_store.dart';

/// Single TokenStore instance shared by the ApiClient and the app.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Configured backend address. Overridden in `main()` with a loaded instance.
final serverConfigProvider = Provider<ServerConfig>((ref) => ServerConfig());

/// Reactive copy of the configured address, for widgets that display it.
final serverUrlProvider = StateProvider<String>((ref) {
  return ref.watch(serverConfigProvider).baseUrl;
});

/// Last successful responses, persisted across app launches.
final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());

/// Whether the UI is currently showing saved data.
final cacheStatusProvider =
    ChangeNotifierProvider<CacheStatus>((ref) => CacheStatus());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokens: ref.watch(tokenStoreProvider),
    serverConfig: ref.watch(serverConfigProvider),
    cache: ref.watch(localCacheProvider),
    // Read, not watch: status notifications must not rebuild the client.
    cacheStatus: ref.read(cacheStatusProvider),
  );
});

/// Dashboard stats from `GET /user/stats`.
///
/// Dependent on [authProvider], so it refetches whenever the signed-in user
/// changes and is cleared automatically on logout.
final statsProvider = FutureProvider<UserStats>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getStats();
});

/// Personal goals/streak for the Profile tab (`GET /user/goals`).
final goalsProvider = FutureProvider<UserGoals>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getGoals();
});

/// Latest submissions for the dashboard Recent Activity card
/// (`GET /user/recent-submissions`).
final recentSubmissionsProvider =
    FutureProvider<List<RecentSubmission>>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getRecentSubmissions();
});

/// Rating-over-time points for the Progress tab line chart.
final ratingHistoryProvider = FutureProvider<List<RatingPoint>>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getRatingHistory();
});

/// Solved-per-bucket data for the Progress tab bar chart.
final solvedByRatingProvider = FutureProvider<List<RatingBucket>>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getSolvedByRating();
});

/// Per-topic solved counts for the Progress tab topic analysis.
final topicsProvider = FutureProvider<List<TopicStat>>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getTopics();
});

/// Unsolved practice problems for the selected filter
/// (`GET /practice/problems?mode=...`).
final practiceProblemsProvider =
    FutureProvider.family<PracticeResult, String>((ref, mode) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getPracticeProblems(mode: mode);
});

/// Upcoming and recent contests (`GET /contests`).
final contestsProvider = FutureProvider<ContestsResult>((ref) async {
  ref.watch(authProvider);
  return ref.watch(apiClientProvider).getContests();
});

/// Holds the current signed-in user, or null when logged out.
///
/// All calls go to the backend via [ApiClient] and persist the JWT pair
/// through [TokenStore].
class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._api, this._tokens, {LocalCache? cache})
      : _cache = cache,
        super(null);

  final ApiClient _api;
  final TokenStore _tokens;
  final LocalCache? _cache;

  /// True when tokens exist but restoring the profile failed for a reason
  /// other than an invalid session (typically the server is unreachable).
  ///
  /// The UI shows a retry screen instead of silently signing the user out.
  bool restoreFailed = false;

  /// Restores a session from disk. Call once at startup, then if a token
  /// exists fetch the profile to confirm it is still valid.
  Future<void> restoreSession() async {
    await _tokens.load();
    restoreFailed = false;
    if (!_tokens.hasSession) return;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        state = await _api.me();
        return;
      } on ApiException catch (e) {
        // Only a rejected session should erase the saved tokens.
        if (e.statusCode == 401 || e.statusCode == 403) {
          await _tokens.clear();
          state = null;
          return;
        }
        // Network/5xx: keep the session and let the user retry.
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        restoreFailed = true;
      }
    }
  }

  Future<void> login(String email, String password) async {
    final result = await _api.login(email, password);
    await _tokens.save(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    // Never show the previous account's saved data to the new one.
    await _cache?.clear();
    await _cache?.save('user_me', result.user.toJson());
    state = result.user;
  }

  Future<String?> register(String email, String password) async {
    final result = await _api.register(email, password);
    await _tokens.save(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await _cache?.clear();
    await _cache?.save('user_me', result.user.toJson());
    state = result.user;
    // In console-email mode the backend echoes the code for local testing.
    return result.devVerificationCode;
  }

  Future<void> verifyEmail(String email, String code) async {
    final user = await _api.verifyEmail(email, code);
    state = user;
    await _cache?.save('user_me', user.toJson());
  }

  Future<ResendResult> resendVerification(String email) {
    return _api.resendVerification(email);
  }

  Future<CodeforcesLinkStart> startCodeforcesLink(String handle) {
    return _api.startCodeforcesLink(handle);
  }

  Future<void> verifyCodeforcesLink(String code) async {
    final user = await _api.verifyCodeforcesLink(code);
    state = user;
    await _cache?.save('user_me', user.toJson());
  }

  Future<void> logout() async {
    await _tokens.clear();
    await _cache?.clear();
    state = null;
  }
}

final authProvider =
    StateNotifierProvider<AuthController, AppUser?>((ref) {
  return AuthController(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
    cache: ref.watch(localCacheProvider),
  );
});
