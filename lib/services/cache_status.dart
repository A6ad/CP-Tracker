import 'package:flutter/foundation.dart';

/// Tracks whether the UI is currently showing saved data because the backend
/// could not be reached.
///
/// A successful request clears the banner; the first cached fallback turns it
/// on and records the age of the saved data for display.
class CacheStatus extends ChangeNotifier {
  bool _offline = false;
  DateTime? _savedAt;

  bool get offline => _offline;
  DateTime? get savedAt => _savedAt;

  void markLive() {
    if (!_offline && _savedAt == null) return;
    _offline = false;
    _savedAt = null;
    notifyListeners();
  }

  void markCached(DateTime savedAt) {
    _offline = true;
    // Keep the oldest timestamp seen while offline: it is the most honest
    // answer to "how old is this data?".
    if (_savedAt == null || savedAt.isBefore(_savedAt!)) {
      _savedAt = savedAt;
    }
    notifyListeners();
  }

  void reset() {
    if (!_offline && _savedAt == null) return;
    _offline = false;
    _savedAt = null;
    notifyListeners();
  }
}
