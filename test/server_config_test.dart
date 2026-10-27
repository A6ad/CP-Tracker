import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cp_tracker/services/api_config.dart';
import 'package:cp_tracker/services/server_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeServerUrl', () {
    test('adds http:// when the scheme is missing', () {
      expect(
        normalizeServerUrl('192.168.1.17:8000'),
        'http://192.168.1.17:8000',
      );
    });

    test('trims spaces and trailing slashes', () {
      expect(
        normalizeServerUrl('  http://192.168.1.17:8000//  '),
        'http://192.168.1.17:8000',
      );
    });

    test('keeps https and base paths', () {
      expect(
        normalizeServerUrl('https://api.example.com/cp/'),
        'https://api.example.com/cp',
      );
    });

    test('rejects empty input', () {
      expect(() => normalizeServerUrl('   '), throwsFormatException);
    });

    test('rejects unsupported schemes', () {
      expect(
        () => normalizeServerUrl('ftp://example.com'),
        throwsFormatException,
      );
    });

    test('rejects a missing host', () {
      expect(() => normalizeServerUrl('http://'), throwsFormatException);
    });
  });

  group('ServerConfig', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists a custom address across instances', () async {
      final config = ServerConfig();
      await config.setBaseUrl('http://10.0.0.5:8000/');

      expect(config.baseUrl, 'http://10.0.0.5:8000');
      expect(config.isCustom, isTrue);

      final reloaded = ServerConfig();
      await reloaded.load();
      expect(reloaded.baseUrl, 'http://10.0.0.5:8000');
      expect(reloaded.isCustom, isTrue);
    });

    test('reset returns to the build-time default', () async {
      final config = ServerConfig();
      await config.setBaseUrl('http://10.0.0.5:8000');
      await config.reset();

      expect(config.baseUrl, ApiConfig.baseUrl);
      expect(config.isCustom, isFalse);
    });

    test('ignores a corrupt stored value', () async {
      SharedPreferences.setMockInitialValues({'api_base_url': 'http://'});

      final config = ServerConfig();
      await config.load();

      expect(config.baseUrl, ApiConfig.baseUrl);
    });
  });
}
