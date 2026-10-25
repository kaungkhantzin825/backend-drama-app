import '../core/api_client.dart' as api;
import '../core/client_context.dart';
import 'ad_settings.dart';

/// Everything `GET /api/v1/app-config` returns.
class RemoteConfig {
  const RemoteConfig({
    required this.ads,
    required this.release,
    required this.maintenance,
    this.abTest,
    this.abGroup,
  });

  final AdSettings ads;
  final ReleasePolicy release;
  final Maintenance maintenance;

  /// The running A/B experiment and this device's variant, if any.
  final String? abTest;
  final String? abGroup;

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) =>
        json[key] is Map ? Map<String, dynamic>.from(json[key] as Map) : const {};

    return RemoteConfig(
      ads: AdSettings.fromJson(json),
      release: ReleasePolicy.fromJson(section('app_version')),
      maintenance: Maintenance.fromJson(section('maintenance')),
      abTest: json['ab_test'] as String?,
      abGroup: json['ab_group'] as String?,
    );
  }

  /// Used when the config cannot be fetched: build-time ads, no gates.
  factory RemoteConfig.fallback() => RemoteConfig(
        ads: AdSettings.fallback(),
        release: const ReleasePolicy(),
        maintenance: const Maintenance(),
      );
}

/// Forced and optional updates.
class ReleasePolicy {
  const ReleasePolicy({
    this.minSupported = '',
    this.latest = '',
    this.updateUrlAndroid = '',
    this.updateUrlIos = '',
    this.updateMessage = '',
  });

  final String minSupported;
  final String latest;
  final String updateUrlAndroid;
  final String updateUrlIos;
  final String updateMessage;

  /// This build is below the minimum: block the app until it is updated.
  bool get updateRequired =>
      minSupported.isNotEmpty &&
      compareVersions(ClientContext.appVersion, minSupported) < 0;

  /// A newer build exists but this one still works.
  bool get updateAvailable =>
      !updateRequired &&
      latest.isNotEmpty &&
      compareVersions(ClientContext.appVersion, latest) < 0;

  /// Store link for the running platform ('' when not configured).
  String get updateUrl =>
      ClientContext.platform == 'ios' ? updateUrlIos : updateUrlAndroid;

  factory ReleasePolicy.fromJson(Map<String, dynamic> json) => ReleasePolicy(
        minSupported: api.as<String>(json, 'min_supported', ''),
        latest: api.as<String>(json, 'latest', ''),
        updateUrlAndroid: api.as<String>(json, 'update_url_android', ''),
        updateUrlIos: api.as<String>(json, 'update_url_ios', ''),
        updateMessage: api.as<String>(json, 'update_message', ''),
      );
}

class Maintenance {
  const Maintenance({this.enabled = false, this.message = ''});

  final bool enabled;
  final String message;

  factory Maintenance.fromJson(Map<String, dynamic> json) => Maintenance(
        enabled: api.as<bool>(json, 'enabled', false),
        message: api.as<String>(json, 'message', ''),
      );
}
