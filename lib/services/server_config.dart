import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_exception.dart';

/// Validates and canonicalises a user-entered backend address.
///
/// Accepts input without a scheme (`192.168.1.17:8000`), strips trailing
/// slashes, and rejects anything that is not an http(s) URL with a host.
String normalizeServerUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException('Enter a server address.');
  }
  if (!value.contains('://')) {
    value = 'http://$value';
  }

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    throw const FormatException(
      'Use an address like http://192.168.1.17:8000',
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('Only http:// and https:// are supported.');
  }

  return value.replaceFirst(RegExp(r'/+$'), '');
}

/// Calls `GET /health` on [baseUrl] so the user can test before saving.
Future<void> checkServer(String baseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw ApiException('The server replied with ${response.statusCode}.');
    }
  } on ApiException {
    rethrow;
  } catch (_) {
    throw const ApiException(
      'Could not reach that server. Check the address and make sure this '
      'phone is on the same Wi-Fi as the backend.',
    );
  }
}

/// Holds the backend address the app is currently using.
///
/// The build-time `API_BASE_URL` is the default; a value saved from the
/// in-app Server screen overrides it and survives restarts. [ApiClient] reads
/// [baseUrl] on every request, so switching servers needs no rebuild.
class ServerConfig extends ChangeNotifier {
  ServerConfig({String? initial}) : _baseUrl = initial ?? ApiConfig.baseUrl;

  static const _storageKey = 'api_base_url';

  String _baseUrl;
  bool _custom = false;

  String get baseUrl => _baseUrl;
  bool get isCustom => _custom;

  /// Loads the saved override, if any. Corrupt values fall back silently to
  /// the build-time default so a bad preference cannot brick startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.trim().isEmpty) return;

    try {
      _baseUrl = normalizeServerUrl(stored);
      _custom = _baseUrl != ApiConfig.baseUrl;
      notifyListeners();
    } on FormatException {
      await prefs.remove(_storageKey);
    }
  }

  Future<void> setBaseUrl(String raw) async {
    final value = normalizeServerUrl(raw);
    _baseUrl = value;
    _custom = value != ApiConfig.baseUrl;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, value);
    notifyListeners();
  }

  Future<void> reset() async {
    _baseUrl = ApiConfig.baseUrl;
    _custom = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
}
