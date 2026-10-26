import 'package:dramaloop/models/ad_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `unit()` picks the running platform; pin it so the tests are stable.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Map<String, dynamic> payload() => {
        'is_ads_enabled': true,
        'ad_provider': 'applovin_max',
        'applovin_sdk_key': 'sdk-key-123',
        'ad_test_device_ids': ['38400000-8cf0-11bd-b23e-10b96e40000d', ' '],
        'ad_interval_seconds': 90,
        'config_version': 'abc123',
        'ad_units': {
          'android': {
            'interstitial': [
              {'unit_id': 'a1b2c3d4e5f60789', 'label': null},
            ],
            'mrec': [
              {'unit_id': 'f1e2d3c4b5a60789', 'label': null},
            ],
            'banner': [],
          },
          'ios': {
            'interstitial': [
              {'unit_id': 'c0ffee00c0ffee00', 'label': null},
            ],
          },
        },
      };

  test('AdSettings reads the MAX key, test devices and one unit per format', () {
    final settings = AdSettings.fromJson(payload());

    expect(settings.sdkKey, 'sdk-key-123');
    expect(settings.testDeviceIds, ['38400000-8cf0-11bd-b23e-10b96e40000d']);
    expect(settings.unit('interstitial'), 'a1b2c3d4e5f60789');
    expect(settings.unit('mrec'), 'f1e2d3c4b5a60789');
    expect(settings.interval, const Duration(seconds: 90));
    expect(settings.isRemote, isTrue);
  });

  test('AdSettings picks the iOS unit on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(AdSettings.fromJson(payload()).unit('interstitial'), 'c0ffee00c0ffee00');
  });

  test('AdSettings treats an empty or missing format as "do not show"', () {
    final settings = AdSettings.fromJson(payload());

    expect(settings.unit('banner'), isNull);
    expect(settings.unit('rewarded'), isNull);
    expect(settings.unit('app_open'), isNull);
  });

  test('AdSettings respects the remote kill switch', () {
    final settings = AdSettings.fromJson({...payload(), 'is_ads_enabled': false});

    expect(settings.enabled, isFalse);
  });

  test('An old payload without a MAX key leaves ads unable to start', () {
    final settings = AdSettings.fromJson(const {'is_ads_enabled': true});

    expect(settings.sdkKey, isEmpty);
    expect(settings.testDeviceIds, isEmpty);
    expect(settings.unit('interstitial'), isNull);
  });

  test('AdSettings fallback uses only build-time values (none by default)', () {
    final settings = AdSettings.fallback();

    expect(settings.isRemote, isFalse);
    expect(settings.enabled, isTrue);
    // No --dart-define in tests: no key, no units.
    expect(settings.sdkKey, isEmpty);
    expect(settings.unit('interstitial'), isNull);
  });
}
