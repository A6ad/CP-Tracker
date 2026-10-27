import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cp_tracker/models/rating_bucket.dart';
import 'package:cp_tracker/models/rating_point.dart';
import 'package:cp_tracker/models/recent_submission.dart';
import 'package:cp_tracker/models/topic_stat.dart';
import 'package:cp_tracker/models/user_goals.dart';
import 'package:cp_tracker/models/user_model.dart';
import 'package:cp_tracker/models/user_stats.dart';
import 'package:cp_tracker/providers/auth_provider.dart';
import 'package:cp_tracker/screens/auth/forgot_password_screen.dart';
import 'package:cp_tracker/screens/auth/login_screen.dart';
import 'package:cp_tracker/screens/auth/register_screen.dart';
import 'package:cp_tracker/screens/connect/connect_codeforces_screen.dart';
import 'package:cp_tracker/screens/dashboard/dashboard_shell.dart';
import 'package:cp_tracker/screens/onboarding/onboarding_screen.dart';
import 'package:cp_tracker/screens/splash/splash_screen.dart';
import 'package:cp_tracker/services/api_client.dart';
import 'package:cp_tracker/services/token_store.dart';
import 'package:cp_tracker/theme/app_theme.dart';

/// Renders every CP Tracker screen against the real theme and real backend
/// data, writing phone-shaped PNGs to test/goldens/ for the pitch deck.
///
///   flutter test --update-goldens test/screenshot_test.dart

const _fontDir =
    '/home/asad/snap/flutter/common/flutter/bin/cache/dart-sdk/bin/resources/'
    'devtools/assets/fonts/Roboto';

// Logical phone viewport; goldens are captured at 3x for slide resolution.
const _logicalSize = Size(412, 900);
const _dpr = 3.0;

late final AppUser _user;
late final UserStats _stats;
late final UserGoals _goals;
late final List<RecentSubmission> _subs;
late final List<RatingPoint> _points;
late final List<RatingBucket> _buckets;
late final List<TopicStat> _topics;

Map<String, dynamic> _read(String name) => jsonDecode(
      File('test/data/$name.json').readAsStringSync(),
    ) as Map<String, dynamic>;

Future<void> _loadRoboto() async {
  Future<ByteData> bytes(String file) async {
    final data = await File('$_fontDir/$file').readAsBytes();
    return ByteData.sublistView(data);
  }

  await (FontLoader('Roboto')
        ..addFont(bytes('Roboto-Regular.ttf'))
        ..addFont(bytes('Roboto-Medium.ttf'))
        ..addFont(bytes('Roboto-Bold.ttf')))
      .load();

  // Material asks for the separate 'Roboto_medium' family at w500.
  await (FontLoader('Roboto_medium')..addFont(bytes('Roboto-Medium.ttf')))
      .load();
}

/// Minimal stand-in so auth-dependent widgets see a signed-in user without
/// ever touching SharedPreferences or the network.
class _StubAuth extends AuthController {
  _StubAuth(AppUser? user)
      : super(ApiClient(tokens: TokenStore()), TokenStore()) {
    state = user;
  }
}

List<Override> _overrides({AppUser? user}) => [
      authProvider.overrideWith((ref) => _StubAuth(user)),
      statsProvider.overrideWith((ref) async => _stats),
      goalsProvider.overrideWith((ref) async => _goals),
      recentSubmissionsProvider.overrideWith((ref) async => _subs),
      ratingHistoryProvider.overrideWith((ref) async => _points),
      solvedByRatingProvider.overrideWith((ref) async => _buckets),
      topicsProvider.overrideWith((ref) async => _topics),
    ];

void _resize(WidgetTester tester) {
  tester.view.physicalSize = _logicalSize * _dpr;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  AppUser? user,
  Duration extra = const Duration(milliseconds: 500),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(user: user),
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  if (extra > Duration.zero) {
    await tester.pump(extra);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

Future<void> _goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(BottomNavigationBar, label));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadRoboto();

    final me = _read('user_me');
    _user = AppUser(
      id: me['id'] as String,
      email: me['email'] as String,
      codeforcesHandle: me['codeforces_handle'] as String?,
      currentRating: me['current_rating'] as int?,
      maxRating: me['max_rating'] as int?,
    );
    _stats = UserStats.fromJson(_read('user_stats'));
    _goals = UserGoals.fromJson(_read('user_goals'));
    _subs = (_read('user_recent-submissions_limit_6')['submissions'] as List)
        .map((e) => RecentSubmission.fromJson(e as Map<String, dynamic>))
        .toList();
    _points = (_read('stats_rating-history')['points'] as List)
        .map((e) => RatingPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    _buckets = (_read('stats_by-rating')['buckets'] as List)
        .map((e) => RatingBucket.fromJson(e as Map<String, dynamic>))
        .toList();
    _topics = (_read('stats_topics')['topics'] as List)
        .map((e) => TopicStat.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  testWidgets('01 splash', (tester) async {
    _resize(tester);
    // Captured before the 1200ms boot delay fires and navigates away.
    await _pump(tester, const SplashScreen(),
        extra: const Duration(milliseconds: 400));
    await _shot(tester, '01_splash');
  });

  testWidgets('02 onboarding start', (tester) async {
    _resize(tester);
    await _pump(tester, const OnboardingScreen());
    await _shot(tester, '02_onboarding_1');
  });

  testWidgets('03 onboarding final', (tester) async {
    _resize(tester);
    await _pump(tester, const OnboardingScreen(), extra: Duration.zero);
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
    }
    await _shot(tester, '03_onboarding_3');
  });

  testWidgets('04 login', (tester) async {
    _resize(tester);
    await _pump(tester, const LoginScreen());
    await _shot(tester, '04_login');
  });

  testWidgets('05 register', (tester) async {
    _resize(tester);
    await _pump(tester, const RegisterScreen());
    await _shot(tester, '05_register');
  });

  testWidgets('06 forgot password', (tester) async {
    _resize(tester);
    await _pump(tester, const ForgotPasswordScreen());
    await _shot(tester, '06_forgot_password');
  });

  testWidgets('07 connect codeforces', (tester) async {
    _resize(tester);
    await _pump(tester, const ConnectCodeforcesScreen());
    await _shot(tester, '07_connect');
  });

  testWidgets('08 dashboard home', (tester) async {
    _resize(tester);
    await _pump(tester, const DashboardShell(), user: _user);
    await _shot(tester, '08_home');
  });

  testWidgets('09 dashboard progress', (tester) async {
    _resize(tester);
    await _pump(tester, const DashboardShell(), user: _user);
    await _goToTab(tester, 'Progress');
    await _shot(tester, '09_progress');
  });

  testWidgets('10 dashboard practice', (tester) async {
    _resize(tester);
    await _pump(tester, const DashboardShell(), user: _user);
    await _goToTab(tester, 'Practice');
    await _shot(tester, '10_practice');
  });

  testWidgets('11 dashboard contests', (tester) async {
    _resize(tester);
    await _pump(tester, const DashboardShell(), user: _user);
    await _goToTab(tester, 'Contests');
    await _shot(tester, '11_contests');
  });

  testWidgets('12 dashboard profile', (tester) async {
    _resize(tester);
    await _pump(tester, const DashboardShell(), user: _user);
    await _goToTab(tester, 'Profile');
    await _shot(tester, '12_profile');
  });
}
