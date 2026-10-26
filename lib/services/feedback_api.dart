import '../core/api_client.dart';

/// A feedback topic the server accepts, e.g. ("payment", "Payment / withdrawal").
typedef FeedbackCategory = ({String key, String label});

/// The "Send feedback" screen's backend. Messages are stored and emailed to
/// the support address the admin has set.
class FeedbackApi {
  FeedbackApi(this._api);

  final ApiClient _api;

  /// Used when the category list cannot be loaded; matches the server's keys.
  static const List<FeedbackCategory> fallbackCategories = [
    (key: 'bug', label: 'Problem / bug'),
    (key: 'payment', label: 'Payment / withdrawal'),
    (key: 'video', label: 'Videos'),
    (key: 'suggestion', label: 'Suggestion'),
    (key: 'other', label: 'Other'),
  ];

  Future<List<FeedbackCategory>> categories() async {
    final data = await _api.get('/feedback/categories');
    final items = data['items'];
    if (items is! List) return fallbackCategories;

    final parsed = items
        .whereType<Map>()
        .map((e) => (key: '${e['key'] ?? ''}', label: '${e['label'] ?? ''}'))
        .where((c) => c.key.isNotEmpty)
        .toList();

    return parsed.isEmpty ? fallbackCategories : parsed;
  }

  Future<void> send({
    required String category,
    required String message,
    String? contact,
  }) async {
    await _api.post('/feedback', body: {
      'category': category,
      'message': message,
      if (contact != null && contact.isNotEmpty) 'contact': contact,
    });
  }
}
