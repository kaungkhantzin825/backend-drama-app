import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'client_context.dart';

/// Persists the bearer token and the device identity.
///
/// The device id is generated once on first launch and never changes. It is
/// what lets the backend recognise a returning guest and hand back the same
/// account, so it must survive reinstalls of the token.
class TokenStore {
  static const _tokenKey = 'dramaloop.auth_token';
  static const _deviceIdKey = 'dramaloop.device_id';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> readToken() async => (await _store).getString(_tokenKey);

  Future<void> writeToken(String token) async =>
      (await _store).setString(_tokenKey, token);

  Future<void> clearToken() async => (await _store).remove(_tokenKey);

  /// The stable device identity, created on first use.
  Future<String> deviceId() async {
    final prefs = await _store;
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.length >= 8) return existing;

    final generated = _generateDeviceId();
    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }

  String _generateDeviceId() {
    // Not a cryptographic identifier — just a stable, low-collision handle.
    final rand = Random.secure();
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final body = List.generate(24, (_) => alphabet[rand.nextInt(alphabet.length)]).join();
    return 'dl-${_platformTag()}-$body';
  }

  /// The platform segment of the device id.
  ///
  /// `dart:io`'s `Platform` throws `UnsupportedError` on the web, and this is
  /// called during guest sign-in — so an unguarded read here surfaced to the
  /// user as "Could not reach the server" even though nothing was ever sent.
  String _platformTag() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}

/// A thin wrapper over Dio that speaks the backend's unified envelope.
///
/// Every call returns the unwrapped `data` payload, so callers never touch
/// `response.data['data']` themselves. Failures are normalised to
/// [ApiException] with a message the UI can show as-is.
class ApiClient {
  ApiClient({required TokenStore tokens, Dio? dio})
      : _tokens = tokens,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.connectTimeout,
                receiveTimeout: ApiConfig.receiveTimeout,
                headers: {'Accept': 'application/json'},
                // We validate status codes ourselves so the envelope's message
                // is never lost behind a generic DioException.
                validateStatus: (_) => true,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers.addAll(
            ClientContext.headers(deviceId: await _tokens.deviceId()),
          );
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;

  /// Called when the server answers 426 (update required) or 503
  /// (maintenance), so the app can re-read its config and show the gate.
  VoidCallback? onReleasePolicyResponse;

  Dio get dio => _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.post(path, data: body, queryParameters: query));

  Future<Map<String, dynamic>> delete(String path) =>
      _send(() => _dio.delete(path));

  /// Runs a request and unwraps the envelope.
  ///
  /// Returns the `data` payload as a map. List payloads (paginated responses)
  /// are wrapped as `{'items': [...], 'meta': {...}}` by [getList].
  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    final Response<dynamic> response;

    try {
      response = await request();
    } on DioException catch (error) {
      throw ApiException(message: _transportMessage(error), statusCode: null);
    }

    final body = response.data;
    final status = response.statusCode ?? 0;

    if (body is! Map) {
      throw MalformedResponseException(
        'The server returned an unexpected response (HTTP $status).',
      );
    }

    final envelope = Map<String, dynamic>.from(body);
    final success = envelope['success'] == true;

    if (!success || status >= 400) {
      if (status == 426 || status == 503) onReleasePolicyResponse?.call();

      final data = envelope['data'];
      throw ApiException(
        message: (envelope['message'] as String?)?.trim().isNotEmpty == true
            ? envelope['message'] as String
            : 'Something went wrong. Please try again.',
        statusCode: status == 0 ? null : status,
        errors: _extractErrors(data),
        data: data,
      );
    }

    final data = envelope['data'];

    if (data == null) return <String, dynamic>{};
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      // Paginated endpoints attach `meta` beside `data` in the envelope.
      if (envelope['meta'] != null) {
        map['meta'] = envelope['meta'];
      }
      return map;
    }

    return {'items': data};
  }

  Map<String, List<String>> _extractErrors(dynamic data) {
    if (data is! Map) return const {};
    final raw = data['errors'];
    if (raw is! Map) return const {};

    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is List ? value.map((e) => e.toString()).toList() : <String>[value.toString()],
      ),
    );
  }

  String _transportMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection timed out. Please check your network and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Please check your connection.';
      case DioExceptionType.badCertificate:
        return 'The server certificate could not be verified.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }
}

/// A page of results plus the paginator metadata.
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  static Paginated<T> fromMap<T>(
    Map<String, dynamic> payload,
    T Function(Map<String, dynamic>) parse,
  ) {
    final rawItems = payload['data'];
    final items = <T>[];

    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) items.add(parse(Map<String, dynamic>.from(item)));
      }
    }

    final meta = payload['meta'];
    final metaMap = meta is Map ? meta : const {};

    return Paginated<T>(
      items: items,
      currentPage: _int(metaMap['current_page'] ?? payload['current_page'], 1),
      lastPage: _int(metaMap['last_page'] ?? payload['last_page'], 1),
      total: _int(metaMap['total'] ?? payload['total'], items.length),
    );
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

/// Read a field from a JSON map with a sane fallback, so a missing or
/// null field never crashes the UI.
T as<T>(Map<String, dynamic> json, String key, T fallback) {
  final value = json[key];
  if (value is T) return value;
  if (value is num && T == double) return value.toDouble() as T;
  if (value is num && T == int) return value.toInt() as T;
  if (value is String && T == int) return (int.tryParse(value) ?? fallback) as T;
  return fallback;
}
