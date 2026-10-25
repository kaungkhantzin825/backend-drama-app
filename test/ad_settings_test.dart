import 'package:dramaloop/models/ad_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `waterfall()` picks the running platform; pin it so the tests are stable.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Map<String, dynamic> payload() => {
        'is_ads_enabled': true,
        'ad_provider': 'admob',
        'ad_interval_seconds': 90,
        'ad_load_timeout_seconds': 4,
        'config_version': 'abc123',
        'ad_units': {
          'android': {
            'interstitial': [
              {'unit_id': 'ca-app-pub-1/high', 'label': 'High floor'},
              {'unit_id': 'ca-app-pub-1/low', 'label': 'Fallback'},
            ],
            'banner': [],
          },
          'ios': {
            'interstitial': [
              {'unit_id': 'ca-app-pub-1/ios', 'label': null},
            ],
          },
        },
      };

  test('AdSettings keeps the waterfall in server order', () {
    final settings = AdSettings.fromJson(payload());

    expect(settings.waterfall('interstitial'), ['ca-app-pub-1/high', 'ca-app-pub-1/low']);
    expect(settings.interval, const Duration(seconds: 90));
    expect(settings.loadTimeout, const Duration(seconds: 4));
    expect(settings.isRemote, isTrue);
  });

  test('AdSettings picks the iOS waterfall on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(AdSettings.fromJson(payload()).waterfall('interstitial'), ['ca-app-pub-1/ios']);
  });

  test('AdSettings treats an empty or missing format as "do not show"', () {
    final settings = AdSettings.fromJson(payload());

    expect(settings.waterfall('banner'), isEmpty);
    expect(settings.waterfall('rewarded'), isEmpty);
  });

  test('AdSettings respects the remote kill switch', () {
    final settings = AdSettings.fromJson({...payload(), 'is_ads_enabled': false});

    expect(settings.enabled, isFalse);
  });

  test('AdSettings fallback has one build-time unit per format', () {
    final settings = AdSettings.fallback();

    expect(settings.isRemote, isFalse);
    expect(settings.enabled, isTrue);
    for (final format in ['banner', 'interstitial', 'rewarded']) {
      expect(settings.waterfall(format), hasLength(1));
    }
  });
}
