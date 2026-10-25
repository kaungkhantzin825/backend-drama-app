import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ad_config.dart';
import '../models/ad_settings.dart';
import 'ad_traffic_reporter.dart';

/// What happened when a rewarded ad was requested.
enum RewardedOutcome {
  /// The user watched far enough to earn the reward.
  earned,

  /// The user closed the ad early. Nothing should be credited.
  dismissed,

  /// No ad could be shown (no fill, offline, ads disabled, daily cap reached,
  /// or unsupported platform).
  unavailable,
}

/// Where a loaded ad came from, so its impression/click/revenue can be
/// attributed to the right waterfall step.
class _Origin {
  const _Origin(this.format, this.unitId, this.tier);

  final String format;
  final String unitId;
  final int tier;
}

/// One place that owns every AdMob call.
///
/// The SDK is a process-wide singleton with real lifecycle constraints — an ad
/// object can only be shown once, and showing a second one before the first is
/// dismissed crashes. Keeping every load/show here means the screens never have
/// to reason about that; they ask for an ad and get an answer.
///
/// **Remote config.** What to show is decided by the backend
/// (`GET /api/v1/app-config` → [init]): the master switch, the interstitial
/// gap, per-placement rules, and the ad units. Until that arrives (or if it
/// never does) the build-time units in [AdConfig] are used.
///
/// **Waterfall.** Each format has an ordered list of units, highest eCPM floor
/// first. A load walks the list and keeps the first unit that fills; each step
/// is capped at [AdSettings.loadTimeout] so a slow network cannot stall it.
///
/// **Traffic.** Every step and every shown ad is reported through
/// [AdTrafficReporter], which feeds the admin Traffic → Ads screen.
///
/// Nothing in this class throws. A missing ad is a normal outcome, not an
/// error, and never blocks the video player.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  AdSettings _settings = AdSettings.fallback();
  final Completer<void> _configReady = Completer<void>();
  AdTrafficReporter? _reporter;
  final Expando<_Origin> _origins = Expando('adOrigin');

  Future<void>? _initializing;
  bool _initialized = false;

  RewardedAd? _rewarded;
  bool _loadingRewarded = false;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  /// When the last interstitial actually appeared on screen. Drives the
  /// `ad_interval_seconds` cap; null until the first one is shown.
  DateTime? _lastInterstitialAt;

  AppOpenAd? _appOpen;
  bool _loadingAppOpen = false;
  bool _appOpenShownThisSession = false;

  // ─── Placement-rule counters ──────────────────────────────────────────────
  int _episodesFinished = 0;
  int _interstitialsThisSession = 0;
  int _interstitialsToday = 0;
  int _rewardedToday = 0;
  String _counterDay = '';
  SharedPreferences? _prefs;

  static const _prefDay = 'dramaloop.ads.day';
  static const _prefInterstitials = 'dramaloop.ads.interstitials';
  static const _prefRewarded = 'dramaloop.ads.rewarded';

  /// A full-screen ad whose callbacks never fire must not freeze the player.
  static const Duration _showGuard = Duration(minutes: 2);

  AdSettings get settings => _settings;

  AdRules get rules => _settings.rules;

  bool get isSupported => AdConfig.isSupported;

  /// True when this platform can show ads *and* the backend allows them.
  bool get adsEnabled => AdConfig.isSupported && _settings.enabled;

  bool get isInitialized => _initialized;

  bool get hasRewardedAd => _rewarded != null;

  bool get hasInterstitial => _interstitial != null;

  bool get hasAppOpenAd => _appOpen != null;

  DateTime? get lastInterstitialAt => _lastInterstitialAt;

  int get interstitialsThisSession => _interstitialsThisSession;

  int get interstitialsToday => _interstitialsToday;

  int get rewardedToday => _rewardedToday;

  /// Completes once the remote config has been applied (or given up on).
  /// Ads that appear on their own — app open, banners — wait on this, so a
  /// backend "ads off" is respected from the very first frame.
  Future<void> get ready => _configReady.future;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Where ad traffic events go. Set once at startup.
  void attachReporter(AdTrafficReporter reporter) => _reporter = reporter;

  /// Applies the backend's ad config, starts the SDK and preloads the
  /// full-screen formats through their waterfalls.
  ///
  /// Safe to call again (e.g. after a config refresh): cached ads are kept,
  /// and the new interval/rules/units apply from the next load.
  Future<void> init(AdSettings config) async {
    _settings = config;
    await _loadCounters();
    if (!_configReady.isCompleted) _configReady.complete();

    if (!adsEnabled) {
      _disposeCachedAds();
      return;
    }

    await initialize();

    unawaited(loadInterstitial());
    unawaited(loadRewarded());
    if (rules.appOpenEnabled) unawaited(loadAppOpen());
  }

  /// Starts the Mobile Ads SDK once. Does not preload — [init] does that once
  /// it knows which units to use.
  Future<void> initialize() {
    if (!AdConfig.isSupported) return Future<void>.value();

    return _initializing ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      if (AdConfig.testDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: AdConfig.testDeviceIds),
        );
      }

      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (error, stack) {
      // A failed SDK init must never take the app down with it.
      debugPrint('AdMob init failed: $error\n$stack');
    }
  }

  void _disposeCachedAds() {
    _interstitial?.dispose();
    _interstitial = null;
    _rewarded?.dispose();
    _rewarded = null;
    _appOpen?.dispose();
    _appOpen = null;
  }

  // ─── Placement-rule counters ──────────────────────────────────────────────

  /// The player calls this each time the viewer moves past an episode.
  /// Interstitials start only after `first_after_episodes` of them.
  void noteEpisodeFinished() => _episodesFinished++;

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _loadCounters() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      _counterDay = prefs.getString(_prefDay) ?? '';

      if (_counterDay == _today) {
        _interstitialsToday = prefs.getInt(_prefInterstitials) ?? 0;
        _rewardedToday = prefs.getInt(_prefRewarded) ?? 0;
      } else {
        _resetDay();
      }
    } catch (error) {
      debugPrint('Ad counters unavailable: $error');
    }
  }

  void _resetDay() {
    _counterDay = _today;
    _interstitialsToday = 0;
    _rewardedToday = 0;
  }

  /// Rolls the daily counters over at midnight, then persists them.
  void _countShown({bool interstitial = false, bool rewarded = false}) {
    if (_counterDay != _today) _resetDay();

    if (interstitial) {
      _interstitialsThisSession++;
      _interstitialsToday++;
    }
    if (rewarded) _rewardedToday++;

    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setString(_prefDay, _counterDay));
    unawaited(prefs.setInt(_prefInterstitials, _interstitialsToday));
    unawaited(prefs.setInt(_prefRewarded, _rewardedToday));
  }

  /// 0 means "no limit" for every cap.
  bool _under(int used, int cap) => cap <= 0 || used < cap;

  // ─── Waterfall ────────────────────────────────────────────────────────────

  void _track(
    String event,
    String format, {
    String? placement,
    String? unitId,
    int? tier,
    int? valueMicros,
  }) {
    _reporter?.track(
      event,
      format: format,
      placement: placement,
      unitId: unitId,
      tier: tier,
      valueMicros: valueMicros,
    );
  }

  /// Walks [units] in order and returns the first ad that loads, or null.
  Future<T?> _loadWaterfall<T extends Ad>(
    String format,
    List<String> units,
    void Function(
      String unitId,
      void Function(T ad) onLoaded,
      void Function(LoadAdError error) onFailed,
    ) start,
  ) async {
    for (var tier = 0; tier < units.length; tier++) {
      final ad = await _loadOne<T>(format, tier + 1, units[tier], start);
      if (ad != null) return ad;
    }

    return null;
  }

  /// One waterfall step (1-based [tier]), capped at the configured timeout.
  ///
  /// An ad that arrives after the step has timed out is disposed rather than
  /// leaked — the waterfall has already moved on to the next unit.
  Future<T?> _loadOne<T extends Ad>(
    String format,
    int tier,
    String unitId,
    void Function(
      String unitId,
      void Function(T ad) onLoaded,
      void Function(LoadAdError error) onFailed,
    ) start,
  ) {
    final completer = Completer<T?>();
    var abandoned = false;

    _track('request', format, placement: 'preload', unitId: unitId, tier: tier);

    try {
      start(
        unitId,
        (ad) {
          if (abandoned || completer.isCompleted) {
            ad.dispose();
            return;
          }
          _origins[ad] = _Origin(format, unitId, tier);
          _track('fill', format, placement: 'preload', unitId: unitId, tier: tier);
          completer.complete(ad);
        },
        (error) {
          debugPrint('$format tier $tier no fill: ${error.message}');
          _track('no_fill', format, placement: 'preload', unitId: unitId, tier: tier);
          if (!completer.isCompleted) completer.complete(null);
        },
      );
    } catch (error) {
      debugPrint('$format tier $tier load threw: $error');
      _track('no_fill', format, placement: 'preload', unitId: unitId, tier: tier);
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future.timeout(
      _settings.loadTimeout,
      onTimeout: () {
        abandoned = true;
        debugPrint('$format tier $tier timed out');
        _track('timeout', format, placement: 'preload', unitId: unitId, tier: tier);
        return null;
      },
    );
  }

  /// Reports what a shown full-screen ad does: impression, click, revenue.
  FullScreenContentCallback<T> _trackedCallback<T extends AdWithoutView>(
    T ad,
    String placement, {
    void Function(T ad)? onShowed,
    required void Function(T ad) onDismissed,
    required void Function(T ad, AdError error) onFailed,
  }) {
    final origin = _origins[ad];

    void track(String event, {int? value}) => _track(
          event,
          origin?.format ?? 'unknown',
          placement: placement,
          unitId: origin?.unitId,
          tier: origin?.tier,
          valueMicros: value,
        );

    ad.onPaidEvent = (_, valueMicros, precision, currency) =>
        track('paid', value: valueMicros.round());

    return FullScreenContentCallback<T>(
      onAdShowedFullScreenContent: onShowed,
      onAdImpression: (_) => track('impression'),
      onAdClicked: (_) => track('click'),
      onAdDismissedFullScreenContent: onDismissed,
      onAdFailedToShowFullScreenContent: (ad, error) {
        track('show_failed');
        onFailed(ad, error);
      },
    );
  }

  // ─── Interstitial ─────────────────────────────────────────────────────────

  /// Preloads an interstitial in the background, if none is cached.
  Future<void> loadInterstitial() async {
    if (!adsEnabled || _loadingInterstitial || _interstitial != null) return;

    _loadingInterstitial = true;
    await initialize();

    try {
      _interstitial = await _loadWaterfall<InterstitialAd>(
        'interstitial',
        _settings.waterfall('interstitial'),
        (unitId, onLoaded, onFailed) => InterstitialAd.load(
          adUnitId: unitId,
          request: const AdRequest(),
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        ),
      );
    } finally {
      _loadingInterstitial = false;
    }
  }

  /// True when the `ad_interval_seconds` gap since the last interstitial has
  /// passed (or none has been shown yet this session).
  bool get _intervalElapsed {
    final last = _lastInterstitialAt;
    return last == null || DateTime.now().difference(last) >= _settings.interval;
  }

  /// The interval plus the session and daily caps.
  bool get _interstitialAllowed =>
      _intervalElapsed &&
      _under(_interstitialsThisSession, rules.interstitialMaxPerSession) &&
      _under(_counterDay == _today ? _interstitialsToday : 0, rules.interstitialMaxPerDay);

  /// Whether [showEpisodeInterstitialAd] would actually show an ad right now.
  ///
  /// Synchronous, so the player can decide to pause *before* calling it — a
  /// skipped break then costs the viewer nothing, not even a frame.
  bool get isEpisodeInterstitialDue =>
      isInterstitialDue &&
      _episodesFinished >= rules.interstitialFirstAfterEpisodes;

  /// Like [isEpisodeInterstitialDue] but without the first-N-episodes gate —
  /// for the ad that follows each completed watch minute.
  bool get isInterstitialDue =>
      adsEnabled && _interstitialAllowed && _interstitial != null;

  /// The between-episodes ad break.
  ///
  /// [onAdDismissed] is always called exactly once:
  ///  * immediately, when ads are off, a rule says not yet (interval, first
  ///    N episodes, session/day cap), or no ad is preloaded (one is then
  ///    requested in the background for next time);
  ///  * after the ad closes, or fails to show, otherwise.
  ///
  /// The player never waits on a network load here — only on an ad that is
  /// already in memory.
  Future<void> showEpisodeInterstitialAd({
    required VoidCallback onAdDismissed,
    String placement = 'episode_break',
    bool requireEpisodes = true,
  }) async {
    var settled = false;
    void done() {
      if (settled) return;
      settled = true;
      onAdDismissed();
    }

    if (!adsEnabled ||
        (requireEpisodes && _episodesFinished < rules.interstitialFirstAfterEpisodes) ||
        !_interstitialAllowed) {
      done();
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      done();
      unawaited(loadInterstitial());
      return;
    }

    _interstitial = null;
    await _present(ad, placement);
    done();
  }

  /// Shows an interstitial at another natural break (e.g. after an unlock),
  /// subject to the same interval and caps as episode breaks.
  ///
  /// [force] bypasses every rule and waits for a load — only the ad test bench
  /// uses it. Returns true when an ad was actually presented.
  Future<bool> maybeShowInterstitial({
    bool force = false,
    String placement = 'natural_break',
  }) async {
    if (!adsEnabled) return false;
    if (!force && !_interstitialAllowed) return false;

    if (_interstitial == null) {
      if (!force) {
        unawaited(loadInterstitial());
        return false;
      }
      await loadInterstitial();
    }

    final ad = _interstitial;
    if (ad == null) return false;

    _interstitial = null;
    return _present(ad, force ? 'test_bench' : placement);
  }

  /// Shows a cached interstitial; completes when it closes. Always queues the
  /// next one, so the following break has an ad ready.
  Future<bool> _present(InterstitialAd ad, String placement) async {
    final completer = Completer<bool>();

    void finish(bool shown) {
      if (!completer.isCompleted) completer.complete(shown);
      unawaited(loadInterstitial());
    }

    ad.fullScreenContentCallback = _trackedCallback<InterstitialAd>(
      ad,
      placement,
      onShowed: (_) {
        _lastInterstitialAt = DateTime.now();
        _countShown(interstitial: true);
      },
      onDismissed: (ad) {
        ad.dispose();
        finish(true);
      },
      onFailed: (ad, error) {
        ad.dispose();
        debugPrint('Interstitial failed to show: ${error.message}');
        finish(false);
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('Interstitial show threw: $error');
      ad.dispose();
      finish(false);
    }

    return completer.future.timeout(_showGuard, onTimeout: () => true);
  }

  // ─── Rewarded ─────────────────────────────────────────────────────────────

  Future<void> loadRewarded() async {
    if (!adsEnabled || _loadingRewarded || _rewarded != null) return;

    _loadingRewarded = true;
    await initialize();

    try {
      _rewarded = await _loadWaterfall<RewardedAd>(
        'rewarded',
        _settings.waterfall('rewarded'),
        (unitId, onLoaded, onFailed) => RewardedAd.load(
          adUnitId: unitId,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        ),
      );
    } finally {
      _loadingRewarded = false;
    }
  }

  /// Whether the daily rewarded cap still allows another one.
  bool get rewardedAllowed =>
      _under(_counterDay == _today ? _rewardedToday : 0, rules.rewardedMaxPerDay);

  /// Shows a rewarded ad and reports whether the reward was earned.
  ///
  /// On a platform without the SDK (web/desktop) this returns [earned] in debug
  /// builds so the local preview can still exercise the reward flow, and
  /// [unavailable] in release.
  Future<RewardedOutcome> showRewarded({String placement = 'rewarded'}) async {
    if (!AdConfig.isSupported) {
      return kDebugMode ? RewardedOutcome.earned : RewardedOutcome.unavailable;
    }

    if (!adsEnabled || !rewardedAllowed) return RewardedOutcome.unavailable;

    if (_rewarded == null) await loadRewarded();

    final ad = _rewarded;
    if (ad == null) return RewardedOutcome.unavailable;

    // Take it out of the cache immediately: an ad instance is single-use, and a
    // second `show()` on the same object is a hard crash.
    _rewarded = null;

    final completer = Completer<RewardedOutcome>();
    var earned = false;

    void settle(RewardedOutcome outcome) {
      if (!completer.isCompleted) completer.complete(outcome);
    }

    ad.fullScreenContentCallback = _trackedCallback<RewardedAd>(
      ad,
      placement,
      onShowed: (_) => _countShown(rewarded: true),
      onDismissed: (ad) {
        ad.dispose();
        unawaited(loadRewarded());
        settle(earned ? RewardedOutcome.earned : RewardedOutcome.dismissed);
      },
      onFailed: (ad, error) {
        ad.dispose();
        unawaited(loadRewarded());
        debugPrint('Rewarded ad failed to show: ${error.message}');
        settle(RewardedOutcome.unavailable);
      },
    );

    try {
      await ad.show(onUserEarnedReward: (ad, reward) => earned = true);
    } catch (error) {
      debugPrint('Rewarded show threw: $error');
      ad.dispose();
      return RewardedOutcome.unavailable;
    }

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () =>
          earned ? RewardedOutcome.earned : RewardedOutcome.unavailable,
    );
  }

  // ─── App open ─────────────────────────────────────────────────────────────

  /// App open is not part of the remote waterfall; it uses the build-time unit.
  Future<void> loadAppOpen() async {
    if (!adsEnabled || !rules.appOpenEnabled || _loadingAppOpen || _appOpen != null) {
      return;
    }

    _loadingAppOpen = true;
    await initialize();

    try {
      _appOpen = await _loadWaterfall<AppOpenAd>(
        'app_open',
        [AdConfig.appOpenAdUnitId],
        (unitId, onLoaded, onFailed) => AppOpenAd.load(
          adUnitId: unitId,
          request: const AdRequest(),
          adLoadCallback: AppOpenAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        ),
      );
    } finally {
      _loadingAppOpen = false;
    }
  }

  /// Shows the app-open ad once per session, on the first frame of the shell.
  Future<bool> maybeShowAppOpen({bool force = false}) async {
    if (!AdConfig.isSupported) return false;
    if (_appOpenShownThisSession && !force) return false;

    // Respect a remote "ads off" even though the shell asks on its first frame.
    await _awaitConfig();
    if (!adsEnabled || (!rules.appOpenEnabled && !force)) return false;

    if (_appOpen == null) await loadAppOpen();

    final ad = _appOpen;
    if (ad == null) return false;

    _appOpen = null;
    _appOpenShownThisSession = true;

    final completer = Completer<bool>();

    ad.fullScreenContentCallback = _trackedCallback<AppOpenAd>(
      ad,
      force ? 'test_bench' : 'app_launch',
      onDismissed: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(true);
      },
      onFailed: (ad, error) {
        ad.dispose();
        debugPrint('App open ad failed to show: ${error.message}');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('App open show threw: $error');
      ad.dispose();
      return false;
    }

    return completer.future.timeout(_showGuard, onTimeout: () => true);
  }

  // ─── Banner & native ──────────────────────────────────────────────────────

  /// How many banner units the waterfall holds.
  int get bannerTiers => _settings.waterfall('banner').length;

  /// The banner for waterfall step [tier] (0-based). The caller owns it and
  /// must dispose it; on a no-fill, [BannerAdBar] asks for `tier + 1`.
  BannerAd? createBanner({
    int tier = 0,
    String placement = 'tab_bar',
    VoidCallback? onLoaded,
    VoidCallback? onFailed,
  }) {
    if (!adsEnabled || !rules.bannerEnabled) return null;

    final units = _settings.waterfall('banner');
    if (tier >= units.length) return null;

    final unitId = units[tier];
    void track(String event, {int? value}) => _track(
          event,
          'banner',
          placement: placement,
          unitId: unitId,
          tier: tier + 1,
          valueMicros: value,
        );

    track('request');

    return BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          track('fill');
          onLoaded?.call();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner tier ${tier + 1} failed to load: ${error.message}');
          track('no_fill');
          ad.dispose();
          onFailed?.call();
        },
        onAdImpression: (_) => track('impression'),
        onAdClicked: (_) => track('click'),
        onPaidEvent: (_, valueMicros, precision, currency) =>
            track('paid', value: valueMicros.round()),
      ),
    );
  }

  /// A native ad rendered with the SDK's built-in medium template, so no
  /// platform-side factory has to be registered. Not part of the remote
  /// waterfall; it uses the build-time unit.
  NativeAd? createNativeAd({NativeAdListener? listener}) {
    if (!adsEnabled) return null;

    return NativeAd(
      adUnitId: AdConfig.nativeAdUnitId,
      listener: listener ??
          NativeAdListener(
            onAdFailedToLoad: (ad, error) {
              debugPrint('Native ad failed to load: ${error.message}');
              ad.dispose();
            },
          ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF1B1B23),
        cornerRadius: 14,
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFF5F5F7),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFA0A0AC),
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFA0A0AC),
          style: NativeTemplateFontStyle.normal,
          size: 11,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFFFFFFF),
          backgroundColor: const Color(0xFFE50914),
          style: NativeTemplateFontStyle.bold,
          size: 12,
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Waits briefly for the remote config, then carries on with whatever is
  /// in place — a slow backend must not hold the UI hostage.
  Future<void> _awaitConfig() =>
      ready.timeout(const Duration(seconds: 4), onTimeout: () {});
}
