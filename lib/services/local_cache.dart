import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One stored API response plus the moment it was fetched.
class CachedEntry {
  final Map<String, dynamic> data;
  final DateTime savedAt;

  const CachedEntry({required this.data, required this.savedAt});
}

/// Persists the last successful JSON response for each dashboard endpoint.
///
/// Values live in `shared_preferences` under a versioned prefix, so they are
/// removed by [clear] without touching the auth tokens or server setting.
class LocalCache {
  static const _prefix = 'cache_v1_';
  static const _savedAtKey = 'saved_at';
  static const _payloadKey = 'payload';

  String _key(String key) => '$_prefix$key';

  Future<void> save(String key, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(key),
      jsonEncode({
        _savedAtKey: DateTime.now().toUtc().toIso8601String(),
        _payloadKey: data,
      }),
    );
  }

  Future<CachedEntry?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(key));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final savedAt = DateTime.tryParse(decoded[_savedAtKey] as String? ?? '');
      final data = decoded[_payloadKey];
      if (savedAt == null || data is! Map<String, dynamic>) return null;

      // Stored as UTC; the UI formats it in local time.
      return CachedEntry(data: data, savedAt: savedAt.toLocal());
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(key));
  }

  /// Drops every cached response, leaving tokens and app settings intact.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
