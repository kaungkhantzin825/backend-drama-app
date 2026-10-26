import 'package:flutter/foundation.dart';

import '../core/ad_config.dart';
import '../core/api_client.dart' as api;

/// The ad setup served by `GET /api/v1/app-config`.
///
/// Lets the backend switch ads off, tune the interstitial gap, change the
/// AppLovin MAX SDK key and ad units, or put a phone in test mode — all
/// without an app release. MAX mediates the networks (Meta, Mintegral, Unity)
/// inside each unit, so every format has exactly one unit.
class AdSettings {
  const AdSettings({
    required this.enabled,
    required this.sdkKey,
    required this.interval,
    required this.units,
    this.testDeviceIds = const [],
    this.rules = const AdRules(),
    this.version,
  });

  /// Per-placement frequency rules, enforced by [AdService].
  final AdRules rules;

  /// Master switch. When false the app shows no ads of any format.
  final bool enabled;

  /// AppLovin MAX SDK key. Empty means MAX cannot start, so no ads.
  final String sdkKey;

  /// Advertising ids (GAID / IDFA) that always get test ads.
  final List<String> testDeviceIds;

  /// Minimum gap between two interstitials.
  final Duration interval;

  /// platform → format → MAX ad unit id.
  final Map<String, Map<String, String>> units;

  /// Short hash of the payload, for logs and the ad test bench.
  final String? version;

  bool get isRemote => version != null;

  /// The MAX unit for [format] (`banner`, `mrec`, `interstitial`, `rewarded`,
  /// `app_open`) on the running platform; null means "do not show this format".
  String? unit(String format) => units[_platformKey]?[format];

  static String get _platformKey =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  factory AdSettings.fromJson(Map<String, dynamic> json) {
    final rawUnits = json['ad_units'];
    final units = <String, Map<String, String>>{};

    if (rawUnits is Map) {
      rawUnits.forEach((platform, formats) {
        if (formats is! Map) return;

        units[platform.toString()] = {
          for (final entry in formats.entries)
            if (entry.value is List &&
                (entry.value as List).isNotEmpty &&
                (entry.value as List).first is Map &&
                ((entry.value as List).first['unit_id'] as String?)?.isNotEmpty == true)
              entry.key.toString(): (entry.value as List).first['unit_id'] as String,
        };
      });
    }

    final testIds = json['ad_test_device_ids'];

    return AdSettings(
      enabled: api.as<bool>(json, 'is_ads_enabled', true),
      sdkKey: api.as<String>(json, 'applovin_sdk_key', ''),
      testDeviceIds: testIds is List
          ? testIds.map((id) => '$id'.trim()).where((id) => id.isNotEmpty).toList()
          : const [],
      interval: Duration(seconds: api.as<int>(json, 'ad_interval_seconds', 120)),
      units: units,
      rules: json['ad_rules'] is Map
          ? AdRules.fromJson(Map<String, dynamic>.from(json['ad_rules'] as Map))
          : const AdRules(),
      version: json['config_version'] as String?,
    );
  }

  /// Used until the remote config arrives, and whenever it cannot be fetched:
  /// the build-time values from [AdConfig] (empty unless defined at build).
  factory AdSettings.fallback() {
    final local = AdConfig.units;

    return AdSettings(
      enabled: true,
      sdkKey: AdConfig.sdkKey,
      testDeviceIds: AdConfig.testDeviceIds,
      interval: const Duration(seconds: 120),
      units: {'android': local, 'ios': local},
    );
  }
}

/// Per-placement frequency rules from the backend (`ad_rules`).
///
/// 0 means "no limit" for every max, matching the admin panel.
class AdRules {
  const AdRules({
    this.interstitialFirstAfterEpisodes = 1,
    this.interstitialMaxPerSession = 10,
    this.interstitialMaxPerDay = 40,
    this.rewardedMaxPerDay = 20,
    this.appOpenEnabled = true,
    this.bannerEnabled = true,
  });

  /// No interstitial until the viewer has swiped past this many videos this
  /// session — first let them get hooked.
  final int interstitialFirstAfterEpisodes;
  final int interstitialMaxPerSession;
  final int interstitialMaxPerDay;
  final int rewardedMaxPerDay;
  final bool appOpenEnabled;
  final bool bannerEnabled;

  factory AdRules.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) =>
        json[key] is Map ? Map<String, dynamic>.from(json[key] as Map) : const {};

    final interstitial = section('interstitial');

    return AdRules(
      interstitialFirstAfterEpisodes: api.as<int>(interstitial, 'first_after_episodes', 1),
      interstitialMaxPerSession: api.as<int>(interstitial, 'max_per_session', 10),
      interstitialMaxPerDay: api.as<int>(interstitial, 'max_per_day', 40),
      rewardedMaxPerDay: api.as<int>(section('rewarded'), 'max_per_day', 20),
      appOpenEnabled: api.as<bool>(section('app_open'), 'enabled', true),
      bannerEnabled: api.as<bool>(section('banner'), 'enabled', true),
    );
  }
}
