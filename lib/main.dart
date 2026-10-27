import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/auth_provider.dart';
import 'services/server_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load any saved server override before the first request is made.
  final serverConfig = ServerConfig();
  await serverConfig.load();

  runApp(
    ProviderScope(
      overrides: [serverConfigProvider.overrideWithValue(serverConfig)],
      child: const CpTrackerApp(),
    ),
  );
}
