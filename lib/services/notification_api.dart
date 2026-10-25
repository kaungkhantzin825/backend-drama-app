import '../core/api_client.dart';
import '../models/models.dart';

/// The in-app inbox.
///
/// Notifications are written server-side when something happens to the user
/// (a payout is approved, a reward lands). The client can only read them and
/// move the read markers.
class NotificationApi {
  NotificationApi(this._api);

  final ApiClient _api;

  Future<Paginated<AppNotification>> list({int page = 1}) async {
    final data = await _api.get('/notifications', query: {'page': page});
    return Paginated.fromMap(data, AppNotification.fromJson);
  }

  /// Count for the bell badge. Kept as its own call so the badge can refresh
  /// without pulling a page of notifications.
  Future<int> unreadCount() async {
    final data = await _api.get('/notifications/unread-count');
    return as<int>(data, 'unread_count', 0);
  }

  Future<AppNotification> markRead(int id) async {
    final data = await _api.post('/notifications/$id/read');
    return AppNotification.fromJson(data);
  }

  /// Returns how many rows were changed.
  Future<int> markAllRead() async {
    final data = await _api.post('/notifications/read-all');
    return as<int>(data, 'updated', 0);
  }
}
