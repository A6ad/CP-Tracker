import 'dart:convert';

import 'package:http/http.dart' as http;

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
import 'api_config.dart';
import 'api_exception.dart';
import 'cache_status.dart';
import 'local_cache.dart';
import 'server_config.dart';
import 'token_store.dart';

/// Response shape for /auth/login and /auth/register.
class AuthResult {
  final AppUser user;
  final String accessToken;
  final String refreshToken;
  final String? devVerificationCode;

  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.devVerificationCode,
  });
}

/// Response from `POST /auth/resend-verification`.
class ResendResult {
  final String message;
  final String? devVerificationCode;

  const ResendResult({required this.message, this.devVerificationCode});
}

/// Thin HTTP wrapper for the CP Tracker backend.
///
/// Owns no state beyond the injected [TokenStore]; every method either
/// returns a decoded model or throws [ApiException] with a user-safe message.
class ApiClient {
  final TokenStore tokens;
  final ServerConfig serverConfig;
  final LocalCache? cache;
  final CacheStatus? cacheStatus;
  final http.Client _http;

  ApiClient({
    required this.tokens,
    ServerConfig? serverConfig,
    this.cache,
    this.cacheStatus,
    http.Client? httpClient,
  })  : serverConfig = serverConfig ?? ServerConfig(),
        _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('${serverConfig.baseUrl}$path');

  Map<String, String> _headers({bool auth = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && tokens.accessToken != null) {
      headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    return headers;
  }

  /// Parses a response body into a map, tolerating empty and non-JSON bodies.
  ///
  /// A proxy or crash can return HTML where JSON is expected; that must not
  /// surface as an unhandled [FormatException] from inside the client.
  Map<String, dynamic> _jsonBody(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  /// Extracts a user-safe `detail` message from an error body.
  ///
  /// FastAPI sends `detail` as a string for an `HTTPException`, but as a list
  /// of objects for 422 validation errors. Only the string form is safe to show.
  String? _detailMessage(Map<String, dynamic> body) {
    final detail = body['detail'];
    return detail is String ? detail : null;
  }

  /// Sends an authenticated request, transparently refreshing once on 401.
  ///
  /// [request] is called with the current access token. If the server replies
  /// 401, the token pair is refreshed and [request] is retried a single time
  /// with the new token. A second 401, or a failed refresh, surfaces as an
  /// [ApiException] so the caller can route the user back to login.
  Future<T> _sendAuthenticated<T>(
    Future<http.Response> Function() request, {
    required T Function(Map<String, dynamic> json) onSuccess,
    Map<int, String> errorMessages = const {},
    String? cacheKey,
    Duration? timeout,
  }) async {
    try {
      final first = await _raw(request, timeout: timeout);
      http.Response response;

      if (first.statusCode != 401) {
        response = first;
      } else {
        // Access token rejected — try to refresh and retry once.
        try {
          await _performRefresh();
        } catch (_) {
          await tokens.clear();
          throw const ApiException(
            'Your session expired. Please log in again.',
            statusCode: 401,
          );
        }

        response = await _raw(request, timeout: timeout);
        if (response.statusCode == 401) {
          await tokens.clear();
          throw const ApiException(
            'Your session expired. Please log in again.',
            statusCode: 401,
          );
        }
      }

      final value = _decode(
        response,
        onSuccess: onSuccess,
        errorMessages: errorMessages,
      );
      await _saveToCache(cacheKey, response);
      cacheStatus?.markLive();
      return value;
    } on ApiException catch (error) {
      final cached = await _readFromCache(cacheKey, error, onSuccess);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Performs the request and converts transport failures to [ApiException].
  Future<http.Response> _raw(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    try {
      return await request().timeout(timeout ?? ApiConfig.timeout);
    } catch (_) {
      throw const ApiException(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Decodes [response], returning the success value or throwing [ApiException].
  T _decode<T>(
    http.Response response, {
    required T Function(Map<String, dynamic> json) onSuccess,
    required Map<int, String> errorMessages,
  }) {
    final body = _jsonBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return onSuccess(body);
    }

    throw ApiException(
      errorMessages[response.statusCode] ??
          _detailMessage(body) ??
          'Something went wrong (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  /// Unauthenticated send: no refresh, no retry.
  Future<T> _send<T>(
    Future<http.Response> Function() request, {
    required T Function(Map<String, dynamic> json) onSuccess,
    Map<int, String> errorMessages = const {},
    String? cacheKey,
    Duration? timeout,
  }) async {
    try {
      final response = await _raw(request, timeout: timeout);
      final value = _decode(
        response,
        onSuccess: onSuccess,
        errorMessages: errorMessages,
      );
      await _saveToCache(cacheKey, response);
      cacheStatus?.markLive();
      return value;
    } on ApiException catch (error) {
      final cached = await _readFromCache(cacheKey, error, onSuccess);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Network failures, rate limits, and server errors are worth answering
  /// from the cache; auth/validation/not-found responses are not.
  bool _canUseCache(ApiException error) {
    final code = error.statusCode;
    return code == null || code == 429 || code >= 500;
  }

  Future<void> _saveToCache(String? key, http.Response response) async {
    if (key == null || cache == null || response.statusCode != 200) return;

    final body = _jsonBody(response.body);
    if (body.isEmpty) return;

    try {
      await cache!.save(key, body);
    } catch (_) {
      // Caching is a convenience; never fail a live request because of it.
    }
  }

  Future<T?> _readFromCache<T>(
    String? key,
    ApiException error,
    T Function(Map<String, dynamic>) onSuccess,
  ) async {
    if (key == null || cache == null || !_canUseCache(error)) return null;

    try {
      final entry = await cache!.read(key);
      if (entry == null) return null;

      final value = onSuccess(entry.data);
      cacheStatus?.markCached(entry.savedAt);
      return value;
    } catch (_) {
      // A schema change or corrupt entry behaves like a cache miss.
      await cache!.remove(key);
      return null;
    }
  }

  /// Exchanges the stored refresh token for a new pair and persists it.
  /// Bypasses [_send] so a failing refresh cannot recurse.
  Future<void> _performRefresh() async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      throw const ApiException('No refresh token available.');
    }

    final response = await _raw(
      () => _http.post(
        _uri('/auth/refresh'),
        headers: _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
      ),
    );

    final body = _jsonBody(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Refresh failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    await tokens.save(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
  }

  AppUser _userFromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        emailVerified: json['email_verified'] as bool? ?? true,
        codeforcesHandle: json['codeforces_handle'] as String?,
        currentRating: json['current_rating'] as int?,
        maxRating: json['max_rating'] as int?,
      );

  /// POST /auth/login
  Future<AuthResult> login(String email, String password) {
    return _send(
      () => _http.post(
        _uri('/auth/login'),
        headers: _headers(),
        body: jsonEncode({'email': email, 'password': password}),
      ),
      onSuccess: (json) => AuthResult(
        user: _userFromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      ),
      errorMessages: const {
        401: 'Incorrect email or password.',
      },
    );
  }

  /// POST /auth/register
  Future<AuthResult> register(String email, String password) {
    return _send(
      () => _http.post(
        _uri('/auth/register'),
        headers: _headers(),
        body: jsonEncode({'email': email, 'password': password}),
      ),
      onSuccess: (json) => AuthResult(
        user: _userFromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        devVerificationCode: json['dev_verification_code'] as String?,
      ),
      errorMessages: const {
        409: 'An account with that email already exists.',
      },
    );
  }

  /// POST /auth/verify-email — proves ownership of the email address.
  Future<AppUser> verifyEmail(String email, String code) {
    return _send(
      () => _http.post(
        _uri('/auth/verify-email'),
        headers: _headers(),
        body: jsonEncode({'email': email, 'code': code}),
      ),
      onSuccess: _userFromJson,
    );
  }

  /// POST /auth/resend-verification — issues a fresh code (rate-limited).
  Future<ResendResult> resendVerification(String email) {
    return _send(
      () => _http.post(
        _uri('/auth/resend-verification'),
        headers: _headers(),
        body: jsonEncode({'email': email}),
      ),
      onSuccess: (json) => ResendResult(
        message:
            json['message'] as String? ?? 'A new verification code was sent.',
        devVerificationCode: json['dev_verification_code'] as String?,
      ),
    );
  }

  /// POST /auth/refresh — exchanges the refresh token for a new pair.
  Future<AuthResult> refresh() {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      throw const ApiException('Your session expired. Please log in again.');
    }
    return _send(
      () => _http.post(
        _uri('/auth/refresh'),
        headers: _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
      ),
      onSuccess: (json) => AuthResult(
        user: _userFromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      ),
      errorMessages: const {
        401: 'Your session expired. Please log in again.',
      },
    );
  }

  /// GET /user/me — fetches the authenticated user's profile.
  ///
  /// Cached so a cold start with no backend can still open the dashboard.
  /// The shorter timeout keeps an offline splash from hanging.
  Future<AppUser> me() {
    return _sendAuthenticated(
      () => _http.get(_uri('/user/me'), headers: _headers(auth: true)),
      onSuccess: _userFromJson,
      errorMessages: const {401: 'Not authenticated.'},
      cacheKey: 'user_me',
      timeout: const Duration(seconds: 5),
    );
  }

  /// POST /user/link-codeforces/start — validates the handle and returns the
  /// code the user must add to their Codeforces profile.
  Future<CodeforcesLinkStart> startCodeforcesLink(String handle) {
    return _sendAuthenticated(
      () => _http.post(
        _uri('/user/link-codeforces/start'),
        headers: _headers(auth: true),
        body: jsonEncode({'handle': handle}),
      ),
      onSuccess: CodeforcesLinkStart.fromJson,
      errorMessages: const {
        404: 'That Codeforces handle does not exist.',
        409: 'That handle is already linked to another account.',
      },
    );
  }

  /// POST /user/link-codeforces/verify — confirms the code is in the
  /// Codeforces profile and links the handle.
  Future<AppUser> verifyCodeforcesLink(String code) {
    return _sendAuthenticated(
      () => _http.post(
        _uri('/user/link-codeforces/verify'),
        headers: _headers(auth: true),
        body: jsonEncode({'code': code}),
      ),
      onSuccess: _userFromJson,
    );
  }

  /// GET /user/stats — aggregate ratings and solving stats for the user.
  Future<UserStats> getStats() {
    return _sendAuthenticated(
      () => _http.get(_uri('/user/stats'), headers: _headers(auth: true)),
      onSuccess: UserStats.fromJson,
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see stats.',
      },
      cacheKey: 'user_stats',
    );
  }

  /// GET /user/goals — personal rating goal and streak for the Profile tab.
  Future<UserGoals> getGoals() {
    return _sendAuthenticated(
      () => _http.get(_uri('/user/goals'), headers: _headers(auth: true)),
      onSuccess: UserGoals.fromJson,
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see goals.',
      },
      cacheKey: 'user_goals',
    );
  }

  /// GET /user/recent-submissions — latest submissions for Recent Activity.
  Future<List<RecentSubmission>> getRecentSubmissions({int limit = 3}) {
    return _sendAuthenticated(
      () => _http.get(
        _uri('/user/recent-submissions?limit=$limit'),
        headers: _headers(auth: true),
      ),
      onSuccess: (json) => (json['submissions'] as List<dynamic>)
          .map((e) => RecentSubmission.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see submissions.',
      },
      cacheKey: 'recent_submissions_$limit',
    );
  }

  /// GET /stats/rating-history — rating over time for the line chart.
  Future<List<RatingPoint>> getRatingHistory() {
    return _sendAuthenticated(
      () => _http.get(_uri('/stats/rating-history'), headers: _headers(auth: true)),
      onSuccess: (json) => (json['points'] as List<dynamic>)
          .map((e) => RatingPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see rating history.',
      },
      cacheKey: 'rating_history',
    );
  }

  /// GET /stats/by-rating — solved counts per rating bucket for the bar chart.
  Future<List<RatingBucket>> getSolvedByRating() {
    return _sendAuthenticated(
      () => _http.get(_uri('/stats/by-rating'), headers: _headers(auth: true)),
      onSuccess: (json) => (json['buckets'] as List<dynamic>)
          .map((e) => RatingBucket.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see difficulty stats.',
      },
      cacheKey: 'solved_by_rating',
    );
  }

  /// GET /stats/topics — solved counts per topic for the topic analysis list.
  Future<List<TopicStat>> getTopics() {
    return _sendAuthenticated(
      () => _http.get(_uri('/stats/topics'), headers: _headers(auth: true)),
      onSuccess: (json) => (json['topics'] as List<dynamic>)
          .map((e) => TopicStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to see topic stats.',
      },
      cacheKey: 'topics',
    );
  }

  /// GET /practice/problems — unsolved problems near the user's rating.
  Future<PracticeResult> getPracticeProblems({
    String mode = 'recommended',
    int limit = 20,
  }) {
    return _sendAuthenticated(
      () => _http.get(
        _uri('/practice/problems?mode=$mode&limit=$limit'),
        headers: _headers(auth: true),
      ),
      onSuccess: PracticeResult.fromJson,
      errorMessages: const {
        401: 'Not authenticated.',
        404: 'Connect your Codeforces account to get practice problems.',
        502: 'Codeforces is unreachable right now. Please try again.',
      },
      cacheKey: 'practice_${mode}_$limit',
    );
  }

  /// GET /contests — upcoming and recently finished Codeforces rounds.
  Future<ContestsResult> getContests({int limit = 20}) {
    return _sendAuthenticated(
      () => _http.get(
        _uri('/contests?limit=$limit'),
        headers: _headers(auth: true),
      ),
      onSuccess: ContestsResult.fromJson,
      errorMessages: const {
        401: 'Not authenticated.',
        502: 'Codeforces is unreachable right now. Please try again.',
      },
      cacheKey: 'contests_$limit',
    );
  }
}
