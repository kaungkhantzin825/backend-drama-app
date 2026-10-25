import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_config.dart';
import '../models/models.dart';

/// Sign-in and session lifecycle.
class AuthService {
  AuthService(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// Sign in as a guest, creating the account on first launch.
  ///
  /// The device id is the account's anchor, so calling this again from the
  /// same install returns the same account rather than a new one.
  Future<({AppUser user, String token})> signInAsGuest() async {
    final deviceId = await _tokens.deviceId();

    final data = await _api.post('/auth/guest', body: {
      'device_id': deviceId,
      'platform': _platform(),
      'app_version': ApiConfig.appVersion,
      'model': _deviceModel(),
      'os_version': _osVersion(),
      'is_emulator': _looksLikeEmulator(),
    });

    final token = data['token'] as String? ?? '';
    if (token.isEmpty) {
      throw StateError('The server did not return an access token.');
    }

    await _tokens.writeToken(token);

    return (
      user: AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map)),
      token: token,
    );
  }

  /// The current user, or null when the stored token is no longer valid.
  Future<AppUser?> currentUser() async {
    final token = await _tokens.readToken();
    if (token == null || token.isEmpty) return null;

    try {
      final data = await _api.get('/me');
      return AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    } catch (_) {
      // An expired or revoked token is not an error — the caller falls back
      // to a fresh guest sign-in.
      return null;
    }
  }

  /// Revoke this device's token server-side, then forget it locally.
  Future<void> signOut() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Even if the network call fails, the local token must go.
    } finally {
      await _tokens.clearToken();
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  /// The OS build string.
  ///
  /// `Platform` comes from `dart:io`, which is not available on the web — an
  /// unguarded read throws `UnsupportedError` mid-sign-in, which the session
  /// controller reports as a connection failure.
  String _osVersion() {
    if (kIsWeb) return 'web';

    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return 'unknown';
    }
  }

  String _deviceModel() {
    if (kIsWeb) return 'browser';
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }

  /// A cheap heuristic used only as a fraud signal, never as a hard block.
  bool _looksLikeEmulator() {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('ANDROID_EMULATOR') ||
          Platform.localHostname.toLowerCase().contains('emulator');
    } catch (_) {
      return false;
    }
  }
}
