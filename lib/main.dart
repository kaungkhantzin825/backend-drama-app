import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/ad_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is dark-only, so the status bar icons are always light.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF15151C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Short dramas are portrait-first.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Warm the ad SDK up while the first screen paints; it is a no-op on web.
  // Ads are preloaded later, once the remote config says which units to use
  // (see adBootstrapProvider).
  unawaited(AdService.instance.initialize());

  runApp(const ProviderScope(child: DramaLoopApp()));
}
