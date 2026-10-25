import 'package:dramaloop/core/client_context.dart';
import 'package:dramaloop/models/ad_settings.dart';
import 'package:dramaloop/models/remote_config.dart';
import 'package:dramaloop/services/ad_traffic_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('compares numerically, not as strings', () {
      expect(compareVersions('1.10.0', '1.9.3'), greaterThan(0));
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('2.0.0', '2.0.1'), lessThan(0));
    });
  });

  group('ReleasePolicy', () {
    // The running build is ClientContext.appVersion (1.0.0 in tests).
    test('requires an update below the minimum', () {
      const policy = ReleasePolicy(minSupported: '9.0.0', latest: '9.1.0');

      expect(policy.updateRequired, isTrue);
      // Required wins over optional — never both prompts.
      expect(policy.updateAvailable, isFalse);
    });

    test('offers an optional update below the latest', () {
      const policy = ReleasePolicy(minSupported: '1.0.0', latest: '1.2.0');

      expect(policy.updateRequired, isFalse);
      expect(policy.updateAvailable, isTrue);
    });

    test('says nothing when the build is current', () {
      final policy = ReleasePolicy(
        minSupported: ClientContext.appVersion,
        latest: ClientContext.appVersion,
      );

      expect(policy.updateRequired, isFalse);
      expect(policy.updateAvailable, isFalse);
    });
  });

  group('RemoteConfig', () {
    test('parses rules, release policy, maintenance and the A/B group', () {
      final config = RemoteConfig.fromJson({
        'is_ads_enabled': true,
        'ad_interval_seconds': 90,
        'ad_rules': {
          'interstitial': {'first_after_episodes': 3, 'max_per_session': 5, 'max_per_day': 0},
          'rewarded': {'max_per_day': 7},
          'app_open': {'enabled': false},
          'banner': {'enabled': true},
        },
        'app_version': {'min_supported': '1.0.0', 'latest': '1.4.0', 'update_url_android': 'https://play.example'},
        'maintenance': {'enabled': true, 'message': 'Back soon'},
        'ab_test': 'gap_test',
        'ab_group': 'B',
      });

      expect(config.ads.rules.interstitialFirstAfterEpisodes, 3);
      expect(config.ads.rules.interstitialMaxPerSession, 5);
      expect(config.ads.rules.interstitialMaxPerDay, 0);
      expect(config.ads.rules.rewardedMaxPerDay, 7);
      expect(config.ads.rules.appOpenEnabled, isFalse);
      expect(config.release.latest, '1.4.0');
      expect(config.maintenance.enabled, isTrue);
      expect(config.maintenance.message, 'Back soon');
      expect(config.abGroup, 'B');
    });

    test('falls back to permissive defaults with no gates', () {
      final config = RemoteConfig.fallback();

      expect(config.maintenance.enabled, isFalse);
      expect(config.release.updateRequired, isFalse);
      expect(config.ads.rules.bannerEnabled, isTrue);
      expect(config.abGroup, isNull);
    });

    test('missing ad_rules uses the defaults', () {
      expect(AdSettings.fromJson(const {}).rules.interstitialFirstAfterEpisodes, 1);
    });
  });

  group('AdTrafficReporter', () {
    test('sends a full batch at once', () async {
      final sent = <List<Map<String, dynamic>>>[];
      final reporter = AdTrafficReporter((events) async => sent.add(events));

      for (var i = 0; i < 25; i++) {
        reporter.track('request', format: 'interstitial', unitId: 'u', tier: 1);
      }
      await Future<void>.delayed(Duration.zero);

      expect(sent, hasLength(1));
      expect(sent.first, hasLength(25));
      expect(sent.first.first, {'event': 'request', 'format': 'interstitial', 'unit_id': 'u', 'tier': 1});
    });

    test('keeps a failed batch and retries it with the next flush', () async {
      var fail = true;
      final sent = <List<Map<String, dynamic>>>[];
      final reporter = AdTrafficReporter((events) async {
        if (fail) throw Exception('offline');
        sent.add(events);
      });

      reporter.track('impression', format: 'banner');
      await reporter.flush();
      expect(sent, isEmpty);

      fail = false;
      reporter.track('click', format: 'banner');
      await reporter.flush();

      expect(sent.single.map((e) => e['event']), ['impression', 'click']);
    });
  });
}
