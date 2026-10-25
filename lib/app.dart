import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'screens/release_gate_screens.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'state/providers.dart';

class DramaLoopApp extends ConsumerStatefulWidget {
  const DramaLoopApp({super.key});

  @override
  ConsumerState<DramaLoopApp> createState() => _DramaLoopAppState();
}

class _DramaLoopAppState extends ConsumerState<DramaLoopApp> with WidgetsBindingObserver {
  /// Back from the background after this long counts as a new session, and
  /// re-reads the remote config (ads, update policy, maintenance).
  static const _sessionGap = Duration(minutes: 30);

  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      // Ship queued ad events before the OS may kill the process.
      ref.read(adTrafficReporterProvider).flush();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;

      if (pausedAt != null && DateTime.now().difference(pausedAt) >= _sessionGap) {
        ref.invalidate(remoteConfigProvider);
        ref.read(sessionProvider.notifier).recordSession();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    // Fetched on cold start alongside the sign-in. While it loads the session
    // flow carries on; only a maintenance window or a too-old build takes over.
    final config = ref.watch(remoteConfigProvider).valueOrNull;

    final Widget home;
    if (config != null && config.maintenance.enabled) {
      home = MaintenanceScreen(
        message: config.maintenance.message,
        onRetry: () {
          ref.invalidate(remoteConfigProvider);
          // Sign-in failed with 503 during the window; try it again too.
          if (session.hasFailed) ref.read(sessionProvider.notifier).bootstrap();
        },
      );
    } else if (config != null && config.release.updateRequired) {
      home = UpdateRequiredScreen(release: config.release);
    } else {
      home = switch (session.status) {
        SessionStatus.authenticated => const AppShell(),
        SessionStatus.failed => SplashScreen(
            message: session.error ?? 'Could not reach the server.',
            onRetry: () {
              ref.invalidate(remoteConfigProvider);
              ref.read(sessionProvider.notifier).bootstrap();
            },
          ),
        SessionStatus.booting => const SplashScreen(),
      };
    }

    return MaterialApp(
      title: 'DramaLoop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: home,
    );
  }
}
