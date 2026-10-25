/// Where the mobile client finds the Laravel API.
///
/// Defaults to the production server. Override at build time, e.g. to use a
/// local backend:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static const String _production = 'https://backenddrama.mmcertify.com/api/v1';

  /// The API root, including the `/api/v1` prefix.
  static String get baseUrl => _override.isNotEmpty ? _override : _production;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Human-readable build identifier reported to the backend on sign-in.
  static const String appVersion = '1.0.0';

  /// Public web origin used to build shareable drama links.
  ///
  /// Override at build time:
  ///   flutter build apk --dart-define=SHARE_BASE_URL=https://dramaloop.example
  static const String _shareOverride = String.fromEnvironment('SHARE_BASE_URL');

  static String get shareBaseUrl =>
      _shareOverride.isNotEmpty ? _shareOverride : 'https://dramaloop.app';

  /// The canonical share link for a drama.
  static String dramaShareUrl(String slug) => '$shareBaseUrl/d/$slug';
}
