import '../core/api_client.dart';
import '../models/models.dart';

/// Reads the public catalogue.
class ContentService {
  ContentService(this._api);

  final ApiClient _api;

  /// Every rail the home screen renders, in one request.
  Future<HomeFeed> home() async {
    final data = await _api.get('/home');
    return HomeFeed.fromJson(data);
  }

  Future<List<Category>> categories() async {
    final data = await _api.get('/categories');
    final items = data['items'] ?? data['data'] ?? const [];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Browse with an optional category slug, search term and sort order.
  Future<Paginated<Drama>> browse({
    String? category,
    String? query,
    String sort = 'latest',
    int page = 1,
  }) async {
    final data = await _api.get('/dramas', query: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'sort': sort,
      'page': page,
    });

    return Paginated.fromMap(data, Drama.fromJson);
  }

  /// Full video detail. Fetching it also records a view.
  Future<DramaDetail> drama(String slug) async {
    final data = await _api.get('/dramas/$slug');
    return DramaDetail.fromJson(data);
  }
}
