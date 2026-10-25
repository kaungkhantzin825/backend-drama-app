import 'package:flutter/foundation.dart';

/// AdMob configuration.
///
/// Every default here is one of Google's published **test** ad units, so the
/// app can be built and exercised end to end without an AdMob account. Test ads
/// always carry a "Test Ad" label and are never billed — they exist precisely
/// so a format can be verified before a real unit is created.
///
/// To ship with real inventory, create the units in the AdMob console and build
/// with the defines below. Any unit left empty falls back to the test id, so a
/// half-configured build still runs instead of crashing on an empty ad unit.
///
/// ```sh
/// flutter build apk --dart-define=USE_TEST_ADS=false \
///   --dart-define=ADMOB_BANNER=ca-app-pub-XXXXXXXX/YYYYYYYY \
///   --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXXXXXXX/YYYYYYYY \
///   --dart-define=ADMOB_REWARDED=ca-app-pub-XXXXXXXX/YYYYYYYY \
///   --dart-define=ADMOB_NATIVE=ca-app-pub-XXXXXXXX/YYYYYYYY \
///   --dart-define=ADMOB_APP_OPEN=ca-app-pub-XXXXXXXX/YYYYYYYY
/// ```
///
/// To silence the "test ad" warning on a physical device, pass your own device
/// hash: `--dart-define=AD_TEST_DEVICE_IDS=ABCDEF1234567890`.
class AdConfig {
  const AdConfig._();

  // ─── App ids ──────────────────────────────────────────────────────────────
  // Must match the `com.google.android.gms.ads.APPLICATION_ID` meta-data in
  // AndroidManifest.xml, or the SDK aborts on launch.

  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// Kept for an eventual iOS target; unused until an iOS runner exists.
  static const String iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  // ─── Test ad units ────────────────────────────────────────────────────────

  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testNative = 'ca-app-pub-3940256099942544/2247696110';
  static const String _testAppOpen = 'ca-app-pub-3940256099942544/9257395921';

  // ─── Live ad units (empty until the console issues them) ──────────────────

  static const String _liveBanner = String.fromEnvironment('ADMOB_BANNER');
  static const String _liveInterstitial =
      String.fromEnvironment('ADMOB_INTERSTITIAL');
  static const String _liveRewarded = String.fromEnvironment('ADMOB_REWARDED');
  static const String _liveNative = String.fromEnvironment('ADMOB_NATIVE');
  static const String _liveAppOpen = String.fromEnvironment('ADMOB_APP_OPEN');

  /// When true every placement resolves to a Google test unit.
  static const bool useTestAds =
      bool.fromEnvironment('USE_TEST_ADS', defaultValue: true);

  static const String _testDeviceIds =
      String.fromEnvironment('AD_TEST_DEVICE_IDS');

  static String get bannerAdUnitId => _pick(_liveBanner, _testBanner);

  static String get interstitialAdUnitId =>
      _pick(_liveInterstitial, _testInterstitial);

  static String get rewardedAdUnitId => _pick(_liveRewarded, _testRewarded);

  static String get nativeAdUnitId => _pick(_liveNative, _testNative);

  static String get appOpenAdUnitId => _pick(_liveAppOpen, _testAppOpen);

  /// Test device hashes, comma separated in the define.
  static List<String> get testDeviceIds => _testDeviceIds
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  /// The mobile SDK has no web or desktop implementation, so every ad call is
  /// short-circuited outside Android/iOS rather than throwing a missing-plugin
  /// error into the UI.
  static bool get isSupported {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String _pick(String live, String test) =>
      useTestAds || live.isEmpty ? test : live;
}
