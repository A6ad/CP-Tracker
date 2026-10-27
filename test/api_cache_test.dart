import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cp_tracker/services/api_client.dart';
import 'package:cp_tracker/services/api_exception.dart';
import 'package:cp_tracker/services/cache_status.dart';
import 'package:cp_tracker/services/local_cache.dart';
import 'package:cp_tracker/services/token_store.dart';

const _statsJson = {
  'current_rating': 726,
  'max_rating': 810,
  'problems_solved': 98,
  'current_streak': 1,
};

const _userJson = {
  'id': 'user-1',
  'email': 'asadjr29@gmail.com',
  'email_verified': true,
  'codeforces_handle': 'A6ad',
  'current_rating': 726,
  'max_rating': 810,
};

ApiClient _client(
  http.Client transport, {
  required LocalCache cache,
  required CacheStatus status,
}) {
  return ApiClient(
    tokens: TokenStore(),
    cache: cache,
    cacheStatus: status,
    httpClient: transport,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalCache cache;
  late CacheStatus status;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cache = LocalCache();
    status = CacheStatus();
  });

  group('ApiClient offline cache', () {
    test('serves saved stats when the network fails', () async {
      final online = _client(
        MockClient((_) async => http.Response(jsonEncode(_statsJson), 200)),
        cache: cache,
        status: status,
      );

      final fresh = await online.getStats();
      expect(fresh.currentRating, 726);
      expect(fresh.problemsSolved, 98);
      expect(status.offline, isFalse);
      expect(await cache.read('user_stats'), isNotNull);

      final offline = _client(
        MockClient((_) async => throw http.ClientException('offline')),
        cache: cache,
        status: status,
      );

      final saved = await offline.getStats();
      expect(saved.currentRating, 726);
      expect(saved.maxRating, 810);
      expect(saved.problemsSolved, 98);
      expect(saved.currentStreak, 1);
      expect(status.offline, isTrue);
      expect(status.savedAt, isNotNull);
    });

    test('falls back on a server error (5xx)', () async {
      final online = _client(
        MockClient((_) async => http.Response(jsonEncode(_statsJson), 200)),
        cache: cache,
        status: status,
      );
      await online.getStats();

      final broken = _client(
        MockClient((_) async => http.Response('upstream error', 502)),
        cache: cache,
        status: status,
      );

      final saved = await broken.getStats();
      expect(saved.currentRating, 726);
      expect(status.offline, isTrue);
    });

    test('does not fall back on a 404', () async {
      final online = _client(
        MockClient((_) async => http.Response(jsonEncode(_statsJson), 200)),
        cache: cache,
        status: status,
      );
      await online.getStats();

      final missing = _client(
        MockClient(
          (_) async => http.Response('{"detail":"Connect your handle."}', 404),
        ),
        cache: cache,
        status: status,
      );

      await expectLater(
        missing.getStats(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
      expect(status.offline, isFalse);
    });

    test('throws when there is no saved copy', () async {
      final offline = _client(
        MockClient((_) async => throw http.ClientException('offline')),
        cache: cache,
        status: status,
      );

      await expectLater(
        offline.getStats(),
        throwsA(isA<ApiException>()),
      );
      expect(status.offline, isFalse);
    });

    test('caches the user profile for an offline cold start', () async {
      final online = _client(
        MockClient((_) async => http.Response(jsonEncode(_userJson), 200)),
        cache: cache,
        status: status,
      );

      final user = await online.me();
      expect(user.codeforcesHandle, 'A6ad');

      final offline = _client(
        MockClient((_) async => throw http.ClientException('offline')),
        cache: cache,
        status: status,
      );

      final restored = await offline.me();
      expect(restored.email, 'asadjr29@gmail.com');
      expect(restored.codeforcesHandle, 'A6ad');
      expect(status.offline, isTrue);
    });
  });
}
