import 'package:flutter/foundation.dart';

/// Build-time AppLovin MAX settings.
///
/// The backend normally supplies the SDK key, the ad units and the test
/// devices (`GET /api/v1/app-config`, edited on the admin Ads page). These
/// defines are only the fallback for a launch where that config cannot be
/// fetched. MAX has no public test units: with nothing configured, the app
/// simply shows no ads.
///
/// ```sh
/// flutter build apk \
///   --dart-define=APPLOVIN_SDK_KEY=YOUR_SDK_KEY \
///   --dart-define=MAX_BANNER=xxxxxxxxxxxxxxxx \
///   --dart-define=MAX_MREC=xxxxxxxxxxxxxxxx \
///   --dart-define=MAX_INTERSTITIAL=xxxxxxxxxxxxxxxx \
///   --dart-define=MAX_REWARDED=xxxxxxxxxxxxxxxx \
///   --dart-define=MAX_APP_OPEN=xxxxxxxxxxxxxxxx
/// ```
///
/// Test mode on a phone: add its advertising id (GAID / IDFA) on the admin Ads
/// page, or `--dart-define=AD_TEST_DEVICE_IDS=id1,id2`.
class AdConfig {
  const AdConfig._();

  static const String sdkKey = String.fromEnvironment('APPLOVIN_SDK_KEY');

  static const Map<String, String> _units = {
    'banner': String.fromEnvironment('MAX_BANNER'),
    'mrec': String.fromEnvironment('MAX_MREC'),
    'interstitial': String.fromEnvironment('MAX_INTERSTITIAL'),
    'rewarded': String.fromEnvironment('MAX_REWARDED'),
    'app_open': String.fromEnvironment('MAX_APP_OPEN'),
  };

  static const String _testDeviceIds =
      String.fromEnvironment('AD_TEST_DEVICE_IDS');

  /// format → unit id, only the formats that were defined.
  static Map<String, String> get units => {
        for (final entry in _units.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      };

  /// Test device advertising ids, comma separated in the define.
  static List<String> get testDeviceIds => _testDeviceIds
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  /// The MAX SDK has no web or desktop implementation, so every ad call is
  /// short-circuited outside Android/iOS rather than throwing a missing-plugin
  /// error into the UI.
  static bool get isSupported {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
