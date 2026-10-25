/// A failed API call, carrying the envelope's human-readable message.
///
/// The backend answers every request with `{success, message, data}`, so the
/// UI can always show `message` directly without inspecting status codes.
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.errors = const {},
    this.data,
  });

  /// Message suitable for showing to the user.
  final String message;

  /// HTTP status, or null for network/transport failures.
  final int? statusCode;

  /// Field-level validation errors, keyed by field name.
  final Map<String, List<String>> errors;

  /// Raw `data` payload from the failure envelope, when present.
  final dynamic data;

  bool get isUnauthenticated => statusCode == 401;

  bool get isRateLimited => statusCode == 429;

  /// True when the server rejected the payload on validation grounds.
  bool get isValidationError => errors.isNotEmpty;

  /// A single flattened message from [errors], for snackbars.
  String? get firstFieldError {
    for (final entry in errors.entries) {
      if (entry.value.isNotEmpty) return entry.value.first;
    }
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when the response is not the expected envelope shape.
class MalformedResponseException extends ApiException {
  MalformedResponseException(String message) : super(message: message);
}
