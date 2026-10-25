import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'api_config.dart';

/// What the app tells the backend about itself on every request.
///
/// Sent as headers by [ApiClient] and read server-side by `ClientContext`:
/// traffic reports are split by platform and version, the release policy
/// gates on `X-App-Version`, blocking works on `X-Device-Id`, and A/B results
/// are grouped by `X-AB-Group`.
class ClientContext {
  ClientContext._();

  /// The A/B variant the backend assigned this device (null = no experiment).
  /// Set once the remote config arrives.
  static String? abGroup;

  static String get appVersion => ApiConfig.appVersion;

  static String get platform {
    if (kIsWeb) return 'web';
    // `Platform` is dart:io — unavailable on the web, hence the guard above.
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  static Map<String, String> headers({required String deviceId}) => {
        'X-App-Platform': platform,
        'X-App-Version': appVersion,
        'X-Device-Id': deviceId,
        if (abGroup != null && abGroup!.isNotEmpty) 'X-AB-Group': abGroup!,
      };
}

/// Compares dotted versions numerically ("1.10.0" > "1.9.3").
/// Returns <0, 0 or >0 like [Comparable.compareTo].
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();

  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }

  return 0;
}
