import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

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

  // AppLovin MAX starts once the remote config has delivered the SDK key and
  // ad units (see adBootstrapProvider → AdService.init).
  runApp(const ProviderScope(child: DramaLoopApp()));
}
