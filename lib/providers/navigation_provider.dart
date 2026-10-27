import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the currently selected bottom-nav tab on the dashboard.
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
