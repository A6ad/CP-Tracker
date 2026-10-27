import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cp_tracker/services/cache_status.dart';
import 'package:cp_tracker/services/local_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalCache', () {
    test('round-trips a payload with a timestamp', () async {
      final cache = LocalCache();

      await cache.save('user_stats', {'current_rating': 726, 'solved': 98});
      final entry = await cache.read('user_stats');

      expect(entry, isNotNull);
      expect(entry!.data['current_rating'], 726);
      expect(entry.data['solved'], 98);
      expect(
        DateTime.now().toUtc().difference(entry.savedAt.toUtc()).inSeconds.abs(),
        lessThan(5),
      );
    });

    test('returns null for a missing key', () async {
      final cache = LocalCache();
      expect(await cache.read('never_saved'), isNull);
    });

    test('returns null for a corrupt entry', () async {
      SharedPreferences.setMockInitialValues({
        'cache_v1_user_stats': 'this is not json',
      });
      final cache = LocalCache();
      expect(await cache.read('user_stats'), isNull);
    });

    test('remove drops one entry only', () async {
      final cache = LocalCache();
      await cache.save('one', {'value': 1});
      await cache.save('two', {'value': 2});

      await cache.remove('one');

      expect(await cache.read('one'), isNull);
      expect((await cache.read('two'))?.data['value'], 2);
    });

    test('clear removes cached responses but keeps other settings', () async {
      SharedPreferences.setMockInitialValues({'auth_access_token': 'token'});
      final cache = LocalCache();
      await cache.save('user_stats', {'current_rating': 726});

      await cache.clear();

      expect(await cache.read('user_stats'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_access_token'), 'token');
    });
  });

  group('CacheStatus', () {
    test('turns offline on a cached read and live again on success', () {
      final status = CacheStatus();
      var notifications = 0;
      status.addListener(() => notifications++);

      status.markCached(DateTime(2026, 10, 27, 8, 20));
      expect(status.offline, isTrue);
      expect(status.savedAt, DateTime(2026, 10, 27, 8, 20));

      status.markLive();
      expect(status.offline, isFalse);
      expect(status.savedAt, isNull);
      expect(notifications, 2);
    });

    test('keeps the oldest timestamp while offline', () {
      final status = CacheStatus();
      final older = DateTime(2026, 10, 27, 7);
      final newer = DateTime(2026, 10, 27, 9);

      status.markCached(newer);
      status.markCached(older);

      expect(status.savedAt, older);
    });

    test('reset clears the banner', () {
      final status = CacheStatus();
      status.markCached(DateTime(2026, 10, 27, 8));
      status.reset();
      expect(status.offline, isFalse);
      expect(status.savedAt, isNull);
    });
  });
}
