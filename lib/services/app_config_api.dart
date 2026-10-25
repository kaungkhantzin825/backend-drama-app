import '../core/api_client.dart';
import '../models/remote_config.dart';

/// Remote configuration (`GET /app-config`) and telemetry endpoints.
class AppConfigApi {
  AppConfigApi(this._api);

  final ApiClient _api;

  /// The device id header picks this device's A/B variant server-side.
  Future<RemoteConfig> fetch() async {
    final data = await _api.get('/app-config');
    return RemoteConfig.fromJson(data);
  }

  /// Report a batch of ad SDK events. Analytics only — never moves points.
  Future<void> sendAdTraffic(List<Map<String, dynamic>> events) =>
      _api.post('/ads/traffic', body: {'events': events});

  /// Count a session (cold start, or back after a long pause).
  Future<void> recordSession() => _api.post('/activity/session');
}
