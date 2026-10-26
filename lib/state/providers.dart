import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/client_context.dart';
import '../models/models.dart';
import '../models/remote_config.dart';
import '../services/ad_service.dart';
import '../services/ad_traffic_reporter.dart';
import '../services/app_config_api.dart';
import '../services/auth_service.dart';
import '../services/content_service.dart';
import '../services/feedback_api.dart';
import '../services/library_api.dart';
import '../services/notification_api.dart';
import '../services/wallet_api.dart';
import '../services/wheel_api.dart';

// ─── Infrastructure ───────────────────────────────────────────────────────────

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

// Explicitly typed: it references remoteConfigProvider, which reads it back.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokens: ref.watch(tokenStoreProvider))
    // A 426 (update required) or 503 (maintenance) mid-session means the
    // release policy changed under us: re-read the config so the gate shows.
    ..onReleasePolicyResponse = () => ref.invalidate(remoteConfigProvider);
});

final contentServiceProvider = Provider<ContentService>((ref) {
  return ContentService(ref.watch(apiClientProvider));
});

final walletApiProvider = Provider<WalletApi>((ref) {
  return WalletApi(ref.watch(apiClientProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider));
});

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(apiClientProvider));
});

final libraryApiProvider = Provider<LibraryApi>((ref) {
  return LibraryApi(ref.watch(apiClientProvider));
});

final wheelApiProvider = Provider<WheelApi>((ref) {
  return WheelApi(ref.watch(apiClientProvider));
});

final feedbackApiProvider = Provider<FeedbackApi>((ref) {
  return FeedbackApi(ref.watch(apiClientProvider));
});

final feedbackCategoriesProvider = FutureProvider<List<FeedbackCategory>>((ref) async {
  try {
    return await ref.watch(feedbackApiProvider).categories();
  } on Exception {
    return FeedbackApi.fallbackCategories;
  }
});

final appConfigApiProvider = Provider<AppConfigApi>((ref) {
  return AppConfigApi(ref.watch(apiClientProvider));
});

// ─── Remote config ────────────────────────────────────────────────────────────

/// Ad traffic telemetry, attached to [AdService] on startup.
final adTrafficReporterProvider = Provider<AdTrafficReporter>((ref) {
  final api = ref.watch(appConfigApiProvider);
  return AdTrafficReporter(api.sendAdTraffic);
});

/// Fetches the remote config and applies it: ad setup to [AdService], the A/B
/// group to every later request. The app root watches this to show the
/// maintenance and update-required gates.
///
/// A failed fetch is not an error for the user: the app falls back to the
/// build-time ad units, with no gates, and carries on.
final FutureProvider<RemoteConfig> remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  RemoteConfig config;

  try {
    config = await ref.read(appConfigApiProvider).fetch();
  } catch (error) {
    debugPrint('Remote config unavailable, using build-time defaults: $error');
    config = RemoteConfig.fallback();
  }

  ClientContext.abGroup = config.abGroup;
  AdService.instance.attachReporter(ref.read(adTrafficReporterProvider));
  await AdService.instance.init(config.ads);

  return config;
});

// ─── Session ──────────────────────────────────────────────────────────────────

enum SessionStatus { booting, authenticated, failed }

class SessionState {
  const SessionState({
    this.status = SessionStatus.booting,
    this.user,
    this.error,
  });

  final SessionStatus status;
  final AppUser? user;
  final String? error;

  bool get isReady => status == SessionStatus.authenticated;
  bool get hasFailed => status == SessionStatus.failed;

  SessionState copyWith({SessionStatus? status, AppUser? user, String? error}) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// Owns the sign-in lifecycle.
///
/// Cold start always resolves to a signed-in session: an existing token is
/// reused, and if it is missing or revoked the app silently signs in as a
/// guest. The user is never shown a login wall.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Kick off the bootstrap once; the widget tree renders a splash meanwhile.
    Future.microtask(bootstrap);
    return const SessionState();
  }

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> bootstrap() async {
    state = state.copyWith(status: SessionStatus.booting);

    try {
      final existing = await _auth.currentUser();
      if (existing != null) {
        state = SessionState(status: SessionStatus.authenticated, user: existing);
        recordSession();
        return;
      }

      final result = await _auth.signInAsGuest();
      state = SessionState(status: SessionStatus.authenticated, user: result.user);
      recordSession();
    } on ApiException catch (error) {
      state = SessionState(status: SessionStatus.failed, error: error.message);
    } catch (error) {
      // This used to say "could not reach the server" for every failure, which
      // sent debugging in entirely the wrong direction when the real cause was
      // a client-side error (e.g. reading `Platform` on the web). Keep the
      // friendly copy in release builds, but surface the cause in debug.
      state = SessionState(
        status: SessionStatus.failed,
        error: kDebugMode
            ? 'Startup failed: $error'
            : 'Could not reach the server. Please check your connection.',
      );
    }
  }

  /// Count a session for the activity report (DAU, sessions per user).
  /// Fire-and-forget: analytics must never block or fail the app.
  void recordSession() {
    if (!state.isReady) return;
    ref.read(appConfigApiProvider).recordSession().catchError((_) {});
  }

  /// Refresh the cached balance after the wallet changes it elsewhere.
  void updateBalance(int points) {
    final user = state.user;
    if (user == null) return;
    state = state.copyWith(user: user.copyWith(pointsBalance: points));
  }

  Future<void> signOutAndRestart() async {
    await _auth.signOut();
    state = const SessionState();
    await bootstrap();
  }
}

final sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

// ─── Wallet ───────────────────────────────────────────────────────────────────

/// Holds the wallet summary and mediates every earning/spending action.
///
/// Actions update the cached wallet from the server's response rather than
/// recomputing locally — the server is the only authority on the balance.
class WalletController extends AsyncNotifier<Wallet> {
  @override
  Future<Wallet> build() async {
    // Wait for the session so the token is in place before the first call.
    final session = ref.watch(sessionProvider);
    if (!session.isReady) {
      throw const _NotReady();
    }

    return ref.read(walletApiProvider).wallet();
  }

  WalletApi get _api => ref.read(walletApiProvider);

  void _syncSession(Wallet wallet) {
    ref.read(sessionProvider.notifier).updateBalance(wallet.pointsBalance);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _api.wallet());
  }

  /// Claim the daily bonus. Returns the points awarded.
  Future<int> checkIn() async {
    final result = await _api.checkIn();
    state = AsyncValue.data(result.wallet);
    _syncSession(result.wallet);
    return result.pointsAwarded;
  }

  /// Credit a verified ad impression. Returns the points awarded.
  Future<int> claimAdReward({required String placement}) async {
    final deviceId = await ref.read(tokenStoreProvider).deviceId();
    final key = '$placement-${DateTime.now().microsecondsSinceEpoch}';

    final result = await _api.claimAdReward(
      placement: placement,
      idempotencyKey: key,
      deviceId: deviceId,
    );

    state = AsyncValue.data(result.wallet);
    _syncSession(result.wallet);
    return result.pointsAwarded;
  }

  /// Move the balance after a payout request consumed it.
  Future<void> applyLocalWallet(Wallet wallet) async {
    state = AsyncValue.data(wallet);
    _syncSession(wallet);
  }
}

/// Sentinel used while the session is still booting.
class _NotReady implements Exception {
  const _NotReady();
}

final walletProvider =
    AsyncNotifierProvider<WalletController, Wallet>(WalletController.new);

// ─── Catalogue ────────────────────────────────────────────────────────────────

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  return ref.watch(contentServiceProvider).home();
});

final dramaDetailProvider = FutureProvider.family<DramaDetail, String>((ref, slug) {
  return ref.watch(contentServiceProvider).drama(slug);
});

// ─── Watch-to-earn meter ──────────────────────────────────────────────────────

/// The player's reward ring, kept app-wide so it carries on from one video to
/// the next (and across player screens) instead of restarting at zero.
///
/// The server owns the real meter; this copy ticks locally between heartbeats
/// and is corrected from every heartbeat response.
class WatchMeterController extends Notifier<WatchReward> {
  bool _synced = false;

  @override
  WatchReward build() => const WatchReward();

  /// Whether the meter has been loaded from the server yet this session.
  bool get isSynced => _synced;

  /// One second of playback.
  void tick() {
    if (state.capped || !state.enabled) return;

    final interval = state.intervalSeconds > 0 ? state.intervalSeconds : 60;
    state = WatchReward(
      seconds: (state.seconds + 1) % interval,
      intervalSeconds: interval,
      pointsPerInterval: state.pointsPerInterval,
      capped: false,
    );
  }

  /// Adopt the server's meter, plus [unreportedSeconds] played since the
  /// heartbeat it answers.
  void sync(WatchReward server, {int unreportedSeconds = 0}) {
    _synced = true;

    final interval = server.intervalSeconds > 0 ? server.intervalSeconds : 60;
    final idle = server.capped || !server.enabled;
    state = WatchReward(
      enabled: server.enabled,
      seconds: idle ? 0 : (server.seconds + unreportedSeconds) % interval,
      intervalSeconds: interval,
      pointsPerInterval: server.pointsPerInterval,
      capped: server.capped,
    );
  }
}

final watchMeterProvider =
    NotifierProvider<WatchMeterController, WatchReward>(WatchMeterController.new);

/// Browse results for one (category, query, sort) combination.
class BrowseQuery {
  const BrowseQuery({this.category, this.query, this.sort = 'latest'});

  final String? category;
  final String? query;
  final String sort;

  @override
  bool operator ==(Object other) =>
      other is BrowseQuery &&
      other.category == category &&
      other.query == query &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(category, query, sort);
}

final browseProvider = FutureProvider.family<Paginated<Drama>, BrowseQuery>(
  (ref, key) => ref.watch(contentServiceProvider).browse(
        category: key.category,
        query: key.query,
        sort: key.sort,
      ),
);

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(contentServiceProvider).categories();
});

final ledgerProvider = FutureProvider<Paginated<LedgerEntry>>((ref) {
  return ref.watch(walletApiProvider).ledger();
});

final withdrawalsProvider = FutureProvider<Paginated<Withdrawal>>((ref) {
  return ref.watch(walletApiProvider).withdrawals();
});

// ─── Inbox ────────────────────────────────────────────────────────────────────

final notificationsProvider = FutureProvider<Paginated<AppNotification>>((ref) async {
  // Nothing to fetch until the guest token exists.
  if (!ref.watch(sessionProvider).isReady) {
    return const Paginated(items: [], currentPage: 1, lastPage: 1, total: 0);
  }

  return ref.read(notificationApiProvider).list();
});

/// Badge count. Returns 0 while the session is still booting so the bell does
/// not flash a spinner on cold start.
final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(sessionProvider).isReady) return 0;

  return ref.read(notificationApiProvider).unreadCount();
});

// ─── Library & wheel ─────────────────────────────────────────────────────────

final continueWatchingProvider = FutureProvider<List<WatchProgressItem>>((ref) async {
  if (!ref.watch(sessionProvider).isReady) return const [];

  return ref.read(libraryApiProvider).continueWatching();
});

final historyProvider = FutureProvider<Paginated<WatchProgressItem>>((ref) async {
  if (!ref.watch(sessionProvider).isReady) {
    return const Paginated(items: [], currentPage: 1, lastPage: 1, total: 0);
  }

  return ref.read(libraryApiProvider).history();
});

final favoritesProvider = FutureProvider<Paginated<Drama>>((ref) async {
  if (!ref.watch(sessionProvider).isReady) {
    return const Paginated(items: [], currentPage: 1, lastPage: 1, total: 0);
  }

  return ref.read(libraryApiProvider).favorites();
});

final luckyWheelProvider = FutureProvider<LuckyWheelState>((ref) async {
  if (!ref.watch(sessionProvider).isReady) {
    return const LuckyWheelState(
      segments: [],
      dailyLimit: 0,
      spinsRemaining: 0,
      spinsUsedToday: 0,
    );
  }

  return ref.read(wheelApiProvider).state();
});
