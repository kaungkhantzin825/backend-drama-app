import 'dart:async';
import 'dart:math' as math;

import 'package:applovin_max/applovin_max.dart';
import 'package:flutter/foundation.dart';
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

/// One place that owns every AppLovin MAX call.
///
/// **Mediation.** MAX runs the auction itself — AppLovin, Meta Audience
/// Network and Mintegral bid, Unity Ads fills from a waterfall — all set up in
/// the MAX dashboard. The app only knows one MAX ad unit per format.
///
/// **Remote config.** The SDK key, the units, the test devices, the master
/// switch, the interstitial gap and the per-placement rules come from the
/// backend (`GET /api/v1/app-config` → [init]). Without an SDK key nothing
/// starts and no ad is shown.
///
/// **Readiness.** MAX reports loads through callbacks; this class mirrors them
/// into plain flags so the player can ask "is an ad ready?" synchronously.
/// Failed loads are retried with exponential backoff, as MAX recommends.
///
/// **Traffic.** Requests, fills, impressions, clicks and revenue are reported
/// through [AdTrafficReporter] for the admin Traffic → Ads screen.
///
/// Nothing in this class throws. A missing ad is a normal outcome, not an
/// error, and never blocks the video player.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const _fullScreen = ['interstitial', 'rewarded', 'app_open'];

  AdSettings _settings = AdSettings.fallback();
  final Completer<void> _configReady = Completer<void>();
  AdTrafficReporter? _reporter;

  Future<bool>? _starting;
  bool _initialized = false;

  // ─── Full-screen state, mirrored from the SDK callbacks ──────────────────
  final Map<String, bool> _ready = {};
  final Map<String, bool> _loading = {};
  final Map<String, int> _retries = {};
  final Map<String, Completer<bool>> _loadWaiters = {};
  final Map<String, String> _placements = {};

  Completer<bool>? _interstitialShowing;
  Completer<bool>? _appOpenShowing;
  Completer<RewardedOutcome>? _rewardedShowing;
  bool _rewardEarned = false;

  // ─── Banner / MREC preloads ───────────────────────────────────────────────
  final Map<AdViewId, Completer<bool>> _adViewWaiters = {};
  final Map<AdViewId, bool> _adViewResults = {};

  /// When the last interstitial actually appeared on screen. Drives the
  /// `ad_interval_seconds` cap; null until the first one is shown.
  DateTime? _lastInterstitialAt;
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

  /// True when this platform can show ads, the backend allows them, and there
  /// is an SDK key to start MAX with.
  bool get adsEnabled =>
      AdConfig.isSupported && _settings.enabled && _settings.sdkKey.isNotEmpty;

  bool get isInitialized => _initialized;

  bool get hasRewardedAd => _ready['rewarded'] ?? false;

  bool get hasInterstitial => _ready['interstitial'] ?? false;

  bool get hasAppOpenAd => _ready['app_open'] ?? false;

  DateTime? get lastInterstitialAt => _lastInterstitialAt;

  int get interstitialsThisSession => _interstitialsThisSession;

  int get interstitialsToday => _interstitialsToday;

  int get rewardedToday => _rewardedToday;

  /// Completes once the remote config has been applied (or given up on).
  /// Ads that appear on their own — app open, banners — wait on this, so a
  /// backend "ads off" is respected from the very first frame.
  Future<void> get ready => _configReady.future;

  /// The MAX unit for [format] on this platform, or null when unset.
  String? unitFor(String format) {
    final unit = _settings.unit(format);
    return unit == null || unit.isEmpty ? null : unit;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Where ad traffic events go. Set once at startup.
  void attachReporter(AdTrafficReporter reporter) => _reporter = reporter;

  /// Applies the backend's ad config, starts MAX and preloads the full-screen
  /// formats.
  ///
  /// Safe to call again (e.g. after a config refresh): the new interval,
  /// rules and units apply from the next load. The SDK key and test devices
  /// only take effect on the first start, as MAX initializes once per process.
  Future<void> init(AdSettings config) async {
    _settings = config;
    await _loadCounters();
    if (!_configReady.isCompleted) _configReady.complete();

    if (!await _start()) return;

    _load('interstitial');
    _load('rewarded');
    if (rules.appOpenEnabled) _load('app_open');
  }

  /// Starts MAX once, with the configured SDK key. True when it is running.
  Future<bool> _start() {
    if (!adsEnabled) return Future<bool>.value(false);

    return _starting ??= _startOnce();
  }

  Future<bool> _startOnce() async {
    try {
      _attachListeners();

      // Must be set before initialize to take effect.
      if (_settings.testDeviceIds.isNotEmpty) {
        AppLovinMAX.setTestDeviceAdvertisingIds(_settings.testDeviceIds);
      }

      _initialized = await AppLovinMAX.initialize(_settings.sdkKey) != null;
    } catch (error, stack) {
      // A failed SDK start must never take the app down with it.
      debugPrint('AppLovin MAX init failed: $error\n$stack');
      _initialized = false;
    }

    if (!_initialized) _starting = null;

    return _initialized;
  }

  /// Opens MAX's built-in panel listing every network adapter and whether it
  /// initialized — the first thing to check when a network never fills.
  Future<void> showMediationDebugger() async {
    if (await _start()) AppLovinMAX.showMediationDebugger();
  }

  // ─── SDK callbacks ────────────────────────────────────────────────────────

  void _attachListeners() {
    AppLovinMAX.setInterstitialListener(InterstitialListener(
      onAdLoadedCallback: (ad) => _loaded('interstitial'),
      onAdLoadFailedCallback: (unitId, error) => _loadFailed('interstitial', unitId, error),
      onAdDisplayedCallback: (ad) {
        _lastInterstitialAt = DateTime.now();
        _countShown(interstitial: true);
        _trackAd('impression', 'interstitial', ad);
      },
      onAdDisplayFailedCallback: (ad, error) {
        _trackAd('show_failed', 'interstitial', ad);
        _finishInterstitial(false);
      },
      onAdClickedCallback: (ad) => _trackAd('click', 'interstitial', ad),
      onAdHiddenCallback: (ad) => _finishInterstitial(true),
      onAdRevenuePaidCallback: (ad) => _trackRevenue('interstitial', ad),
    ));

    AppLovinMAX.setRewardedAdListener(RewardedAdListener(
      onAdLoadedCallback: (ad) => _loaded('rewarded'),
      onAdLoadFailedCallback: (unitId, error) => _loadFailed('rewarded', unitId, error),
      onAdDisplayedCallback: (ad) {
        _countShown(rewarded: true);
        _trackAd('impression', 'rewarded', ad);
      },
      onAdDisplayFailedCallback: (ad, error) {
        _trackAd('show_failed', 'rewarded', ad);
        _finishRewarded(RewardedOutcome.unavailable);
      },
      onAdClickedCallback: (ad) => _trackAd('click', 'rewarded', ad),
      onAdHiddenCallback: (ad) => _finishRewarded(
        _rewardEarned ? RewardedOutcome.earned : RewardedOutcome.dismissed,
      ),
      onAdReceivedRewardCallback: (ad, reward) => _rewardEarned = true,
      onAdRevenuePaidCallback: (ad) => _trackRevenue('rewarded', ad),
    ));

    AppLovinMAX.setAppOpenAdListener(AppOpenAdListener(
      onAdLoadedCallback: (ad) => _loaded('app_open'),
      onAdLoadFailedCallback: (unitId, error) => _loadFailed('app_open', unitId, error),
      onAdDisplayedCallback: (ad) => _trackAd('impression', 'app_open', ad),
      onAdDisplayFailedCallback: (ad, error) {
        _trackAd('show_failed', 'app_open', ad);
        _finishAppOpen(false);
      },
      onAdClickedCallback: (ad) => _trackAd('click', 'app_open', ad),
      onAdHiddenCallback: (ad) => _finishAppOpen(true),
      onAdRevenuePaidCallback: (ad) => _trackRevenue('app_open', ad),
    ));

    AppLovinMAX.setWidgetAdViewAdListener(WidgetAdViewAdListener(
      onAdLoadedCallback: (ad) {
        final id = ad.adViewId;
        if (id != null) _adViewSettled(id, true);
        _trackAd('fill', ad.adFormat.toLowerCase(), ad, placement: 'preload');
      },
      onAdLoadFailedCallback: (unitId, error) {
        final id = error.adViewId;
        if (id != null) _adViewSettled(id, false);
        _reporter?.track('no_fill', format: _formatOfUnit(unitId), placement: 'preload', unitId: unitId, tier: 1);
      },
    ));
  }

  void _loaded(String format) {
    _ready[format] = true;
    _loading[format] = false;
    _retries[format] = 0;
    _trackUnit('fill', format, placement: 'preload');
    _loadWaiters.remove(format)?.complete(true);
  }

  /// MAX's recommended retry: 2, 4, 8 … up to 64 seconds between attempts.
  void _loadFailed(String format, String unitId, MaxError error) {
    debugPrint('$format no fill: ${error.message}');
    _ready[format] = false;
    _loading[format] = false;
    _reporter?.track('no_fill', format: format, placement: 'preload', unitId: unitId, tier: 1);
    _loadWaiters.remove(format)?.complete(false);

    final attempt = math.min((_retries[format] ?? 0) + 1, 6);
    _retries[format] = attempt;
    Future<void>.delayed(Duration(seconds: math.pow(2, attempt).toInt()), () => _load(format));
  }

  /// Requests a full-screen ad for [format] unless one is loaded or loading.
  void _load(String format) {
    final unit = unitFor(format);
    if (!_initialized || !adsEnabled || unit == null) return;
    if ((_ready[format] ?? false) || (_loading[format] ?? false)) return;
    if (format == 'app_open' && !rules.appOpenEnabled) return;

    _loading[format] = true;
    _trackUnit('request', format, placement: 'preload');

    try {
      switch (format) {
        case 'interstitial':
          AppLovinMAX.loadInterstitial(unit);
        case 'rewarded':
          AppLovinMAX.loadRewardedAd(unit);
        case 'app_open':
          AppLovinMAX.loadAppOpenAd(unit);
      }
    } catch (error) {
      debugPrint('$format load threw: $error');
      _loading[format] = false;
    }
  }

  /// Waits up to [timeout] for [format] to load (starting a load if needed).
  Future<bool> _waitForLoad(String format, Duration timeout) async {
    if (_ready[format] ?? false) return true;

    final waiter = _loadWaiters.putIfAbsent(format, Completer<bool>.new);
    _load(format);

    return waiter.future.timeout(timeout, onTimeout: () => _ready[format] ?? false);
  }

  // ─── Telemetry ────────────────────────────────────────────────────────────

  String _formatOfUnit(String unitId) {
    for (final format in [..._fullScreen, 'banner', 'mrec']) {
      if (unitFor(format) == unitId) return format;
    }
    return 'unknown';
  }

  void _trackUnit(String event, String format, {String? placement}) {
    _reporter?.track(event, format: format, placement: placement, unitId: unitFor(format), tier: 1);
  }

  void _trackAd(String event, String format, MaxAd ad, {String? placement}) {
    _reporter?.track(
      event,
      format: format,
      placement: placement ?? _placements[format] ?? ad.placement,
      unitId: ad.adUnitId,
      tier: 1,
    );
  }

  /// MAX reports revenue per impression in USD; the backend stores micros.
  void _trackRevenue(String format, MaxAd ad) {
    _reporter?.track(
      'paid',
      format: format,
      placement: _placements[format] ?? ad.placement,
      unitId: ad.adUnitId,
      tier: 1,
      valueMicros: (ad.revenue * 1000000).round(),
    );
  }

  /// Banner / MREC events from a mounted [MaxAdView].
  void trackAdView(String event, String format, MaxAd ad, {required String placement}) {
    if (event == 'paid') {
      _reporter?.track('paid',
          format: format, placement: placement, unitId: ad.adUnitId, tier: 1, valueMicros: (ad.revenue * 1000000).round());
      return;
    }
    _trackAd(event, format, ad, placement: placement);
  }

  // ─── Placement-rule counters ──────────────────────────────────────────────

  /// The player calls this each time the viewer swipes past a video.
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

  // ─── Interstitial ─────────────────────────────────────────────────────────

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
      isInterstitialDue && _episodesFinished >= rules.interstitialFirstAfterEpisodes;

  /// Like [isEpisodeInterstitialDue] but without the first-N-videos gate —
  /// for the ad that follows each completed watch minute.
  bool get isInterstitialDue =>
      adsEnabled && _interstitialAllowed && hasInterstitial && _interstitialShowing == null;

  /// The between-videos ad break.
  ///
  /// [onAdDismissed] is always called exactly once:
  ///  * immediately, when ads are off, a rule says not yet (interval, first
  ///    N videos, session/day cap), or no ad is loaded (one is then requested
  ///    in the background for next time);
  ///  * after the ad closes, or fails to show, otherwise.
  ///
  /// The player never waits on a network load here — only on an ad that is
  /// already loaded.
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

    if (!hasInterstitial) {
      done();
      _load('interstitial');
      return;
    }

    await _presentInterstitial(placement);
    done();
  }

  /// Shows an interstitial at another natural break, subject to the same
  /// interval and caps as video breaks.
  ///
  /// [force] bypasses every rule and waits for a load — only the ad test bench
  /// uses it. Returns true when an ad was actually presented.
  Future<bool> maybeShowInterstitial({
    bool force = false,
    String placement = 'natural_break',
  }) async {
    if (!adsEnabled) return false;
    if (!force && !_interstitialAllowed) return false;

    if (!hasInterstitial) {
      if (!force) {
        _load('interstitial');
        return false;
      }
      if (!await _start() || !await _waitForLoad('interstitial', const Duration(seconds: 15))) {
        return false;
      }
    }

    return _presentInterstitial(force ? 'test_bench' : placement);
  }

  /// Shows the loaded interstitial; completes when it closes. The next one is
  /// requested as soon as this one is gone.
  Future<bool> _presentInterstitial(String placement) {
    final unit = unitFor('interstitial');
    if (unit == null || _interstitialShowing != null) return Future<bool>.value(false);

    final showing = _interstitialShowing = Completer<bool>();
    _ready['interstitial'] = false;
    _placements['interstitial'] = placement;

    try {
      AppLovinMAX.showInterstitial(unit, placement: placement);
    } catch (error) {
      debugPrint('Interstitial show threw: $error');
      _finishInterstitial(false);
    }

    return showing.future.timeout(_showGuard, onTimeout: () {
      _finishInterstitial(true);
      return true;
    });
  }

  void _finishInterstitial(bool shown) {
    final showing = _interstitialShowing;
    _interstitialShowing = null;
    if (showing != null && !showing.isCompleted) showing.complete(shown);
    _load('interstitial');
  }

  // ─── Rewarded ─────────────────────────────────────────────────────────────

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

    final unit = unitFor('rewarded');
    if (!adsEnabled || unit == null || !rewardedAllowed || _rewardedShowing != null) {
      return RewardedOutcome.unavailable;
    }

    if (!await _start() || !await _waitForLoad('rewarded', const Duration(seconds: 10))) {
      return RewardedOutcome.unavailable;
    }

    final showing = _rewardedShowing = Completer<RewardedOutcome>();
    _rewardEarned = false;
    _ready['rewarded'] = false;
    _placements['rewarded'] = placement;

    try {
      AppLovinMAX.showRewardedAd(unit, placement: placement);
    } catch (error) {
      debugPrint('Rewarded show threw: $error');
      _finishRewarded(RewardedOutcome.unavailable);
    }

    return showing.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => _rewardEarned ? RewardedOutcome.earned : RewardedOutcome.unavailable,
    );
  }

  void _finishRewarded(RewardedOutcome outcome) {
    final showing = _rewardedShowing;
    _rewardedShowing = null;
    if (showing != null && !showing.isCompleted) showing.complete(outcome);
    _load('rewarded');
  }

  // ─── App open ─────────────────────────────────────────────────────────────

  /// Shows the app-open ad once per session, on the first frame of the shell.
  Future<bool> maybeShowAppOpen({bool force = false}) async {
    if (!AdConfig.isSupported) return false;
    if (_appOpenShownThisSession && !force) return false;

    // Respect a remote "ads off" even though the shell asks on its first frame.
    await _awaitConfig();
    final unit = unitFor('app_open');
    if (!adsEnabled || unit == null || (!rules.appOpenEnabled && !force)) return false;
    if (!await _start()) return false;

    // A cold start gets a short grace period for the first load, no more.
    if (!await _waitForLoad('app_open', Duration(seconds: force ? 15 : 4))) return false;

    _appOpenShownThisSession = true;
    final showing = _appOpenShowing = Completer<bool>();
    _ready['app_open'] = false;
    _placements['app_open'] = force ? 'test_bench' : 'app_launch';

    try {
      AppLovinMAX.showAppOpenAd(unit, placement: _placements['app_open']);
    } catch (error) {
      debugPrint('App open show threw: $error');
      _finishAppOpen(false);
    }

    return showing.future.timeout(_showGuard, onTimeout: () => true);
  }

  void _finishAppOpen(bool shown) {
    final showing = _appOpenShowing;
    _appOpenShowing = null;
    if (showing != null && !showing.isCompleted) showing.complete(shown);
  }

  // ─── Banner & MREC ────────────────────────────────────────────────────────

  /// Preloads a banner or MREC and resolves to its view id once it has
  /// actually filled, or null (ads off, no unit, no fill, timeout). Only a
  /// filled ad is then mounted, so an empty slot never takes up space.
  ///
  /// The caller owns the id and must pass it to [destroyAdView].
  Future<AdViewId?> preloadAdView(String format, {required String placement}) async {
    if (format == 'banner' && !rules.bannerEnabled) return null;

    await _awaitConfig();
    final unit = unitFor(format);
    if (!adsEnabled || unit == null || !await _start()) return null;

    _reporter?.track('request', format: format, placement: placement, unitId: unit, tier: 1);

    AdViewId? id;
    try {
      id = await AppLovinMAX.preloadWidgetAdView(
        unit,
        format == 'mrec' ? AdFormat.mrec : AdFormat.banner,
        placement: placement,
      );
    } catch (error) {
      debugPrint('$format preload threw: $error');
      return null;
    }
    if (id == null) return null;

    // The load callback can beat the method-channel reply.
    final early = _adViewResults.remove(id);
    final filled = early ??
        await _adViewWaiters
            .putIfAbsent(id, Completer<bool>.new)
            .future
            .timeout(const Duration(seconds: 20), onTimeout: () => false);
    _adViewWaiters.remove(id);

    if (filled) return id;

    unawaited(destroyAdView(id));
    return null;
  }

  void _adViewSettled(AdViewId id, bool filled) {
    final waiter = _adViewWaiters[id];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(filled);
    } else {
      _adViewResults[id] = filled;
    }
  }

  Future<void> destroyAdView(AdViewId id) async {
    try {
      await AppLovinMAX.destroyWidgetAdView(id);
    } catch (error) {
      debugPrint('Destroying ad view $id failed: $error');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Waits briefly for the remote config, then carries on with whatever is
  /// in place — a slow backend must not hold the UI hostage.
  Future<void> _awaitConfig() =>
      ready.timeout(const Duration(seconds: 4), onTimeout: () {});
}
