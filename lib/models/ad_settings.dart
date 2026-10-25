import 'package:flutter/foundation.dart';

import '../core/ad_config.dart';
import '../core/api_client.dart' as api;

/// The ad setup served by `GET /api/v1/app-config`.
///
/// Lets the backend switch ads off, tune the interstitial gap, or swap ad units
/// without an app release. Each format's units are a **waterfall**: an ordered
/// list, highest eCPM floor first, which [AdService] tries top to bottom.
class AdSettings {
  const AdSettings({
    required this.enabled,
    required this.provider,
    required this.interval,
    required this.loadTimeout,
    required this.units,
    this.rules = const AdRules(),
    this.version,
  });

  /// Per-placement frequency rules, enforced by [AdService].
  final AdRules rules;

  /// Master switch. When false the app shows no ads of any format.
  final bool enabled;

  /// Ad SDK name. Only `admob` is implemented; other networks reach the app
  /// through AdMob mediation, configured in the AdMob console.
  final String provider;

  /// Minimum gap between two interstitials.
  final Duration interval;

  /// How long one waterfall step may take before falling through.
  final Duration loadTimeout;

  /// platform → format → ordered unit ids.
  final Map<String, Map<String, List<String>>> units;

  /// Short hash of the payload, for logs and the ad test bench.
  final String? version;

  bool get isRemote => version != null;

  /// The waterfall for [format] (`banner`, `interstitial`, `rewarded`) on the
  /// platform the app is running on. Empty means "do not show this format".
  List<String> waterfall(String format) =>
      units[_platformKey]?[format] ?? const [];

  static String get _platformKey =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  factory AdSettings.fromJson(Map<String, dynamic> json) {
    final rawUnits = json['ad_units'];
    final units = <String, Map<String, List<String>>>{};

    if (rawUnits is Map) {
      rawUnits.forEach((platform, formats) {
        if (formats is! Map) return;

        units[platform.toString()] = {
          for (final entry in formats.entries)
            entry.key.toString(): [
              if (entry.value is List)
                for (final unit in entry.value as List)
                  if (unit is Map && (unit['unit_id'] as String?)?.isNotEmpty == true)
                    unit['unit_id'] as String,
            ],
        };
      });
    }

    return AdSettings(
      enabled: api.as<bool>(json, 'is_ads_enabled', true),
      provider: api.as<String>(json, 'ad_provider', 'admob'),
      interval: Duration(seconds: api.as<int>(json, 'ad_interval_seconds', 120)),
      loadTimeout: Duration(seconds: api.as<int>(json, 'ad_load_timeout_seconds', 5).clamp(1, 30)),
      units: units,
      rules: json['ad_rules'] is Map
          ? AdRules.fromJson(Map<String, dynamic>.from(json['ad_rules'] as Map))
          : const AdRules(),
      version: json['config_version'] as String?,
    );
  }

  /// Used until the remote config arrives, and whenever it cannot be fetched:
  /// the build-time units from [AdConfig] (Google test units by default), so
  /// an offline launch still behaves sensibly.
  factory AdSettings.fallback() {
    final local = {
      'banner': [AdConfig.bannerAdUnitId],
      'interstitial': [AdConfig.interstitialAdUnitId],
      'rewarded': [AdConfig.rewardedAdUnitId],
    };

    return AdSettings(
      enabled: true,
      provider: 'admob',
      interval: const Duration(seconds: 120),
      loadTimeout: const Duration(seconds: 5),
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

  /// No interstitial until the viewer has started this many episodes this
  /// session — first let them get hooked on the story.
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
