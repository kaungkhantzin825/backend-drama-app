import '../core/api_client.dart';
import '../models/models.dart';

/// Per-viewer library: playback progress, history, and the saved list.
///
/// The progress call is also how watch-time points are earned — the server
/// decides what the reported playback is worth, so this service never
/// computes a reward.
class LibraryApi {
  LibraryApi(this._api);

  final ApiClient _api;

  /// Report where playback is and how many seconds were watched since the
  /// last report. Returns the points the server just credited.
  Future<({WatchProgressItem progress, int pointsAwarded, Wallet wallet})> recordProgress({
    required int dramaId,
    required int positionSeconds,
    required int durationSeconds,
    required int watchedSeconds,
  }) async {
    final data = await _api.post('/dramas/$dramaId/progress', body: {
      'position_seconds': positionSeconds,
      'duration_seconds': durationSeconds,
      'watched_seconds': watchedSeconds,
    });

    return (
      progress: WatchProgressItem.fromJson(
        Map<String, dynamic>.from(data['progress'] as Map? ?? const {}),
      ),
      pointsAwarded: as<int>(data, 'points_awarded', 0),
      wallet: Wallet.fromJson(
        Map<String, dynamic>.from(data['wallet'] as Map? ?? const {}),
      ),
    );
  }

  Future<List<WatchProgressItem>> continueWatching() async {
    final data = await _api.get('/continue-watching');
    final items = data['items'];

    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map((e) => WatchProgressItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Paginated<WatchProgressItem>> history({int page = 1}) async {
    final data = await _api.get('/history', query: {'page': page});
    return Paginated.fromMap(data, WatchProgressItem.fromJson);
  }

  Future<Paginated<Drama>> favorites({int page = 1}) async {
    final data = await _api.get('/favorites', query: {'page': page});
    return Paginated.fromMap(data, Drama.fromJson);
  }

  /// Toggle the saved state. Returns the new value.
  Future<bool> toggleFavorite(int dramaId) async {
    final data = await _api.post('/dramas/$dramaId/favorite');
    return as<bool>(data, 'is_favorite', false);
  }
}
