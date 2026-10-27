import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cp_tracker/app.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CpTrackerApp()));

    expect(find.text('CP Tracker'), findsOneWidget);

    // Let the splash screen's delayed navigation timer fire and settle.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
  });
}
