import '../core/api_client.dart' as api;

/// A signed-in (or guest) mobile account.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.pointsBalance,
    required this.isGuest,
    this.email,
    this.avatarUrl,
    this.authProvider = 'guest',
    this.createdAt,
  });

  final int id;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final String authProvider;
  final bool isGuest;
  final int pointsBalance;
  final DateTime? createdAt;

  String get displayName {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    return isGuest ? 'Guest' : 'Viewer';
  }

  /// Initials for the avatar placeholder.
  String get initials {
    final value = displayName.trim();
    if (value.isEmpty) return '?';
    final parts = value.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: api.as<int>(json, 'id', 0),
        name: json['name'] as String?,
        email: json['email'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        authProvider: api.as<String>(json, 'auth_provider', 'guest'),
        isGuest: api.as<bool>(json, 'is_guest', true),
        pointsBalance: api.as<int>(json, 'points_balance', 0),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  AppUser copyWith({int? pointsBalance}) => AppUser(
        id: id,
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        authProvider: authProvider,
        isGuest: isGuest,
        pointsBalance: pointsBalance ?? this.pointsBalance,
        createdAt: createdAt,
      );
}

/// A catalogue shelf.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.dramaCount,
  });

  final int id;
  final String name;
  final String slug;
  final int? dramaCount;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: api.as<int>(json, 'id', 0),
        name: api.as<String>(json, 'name', ''),
        slug: api.as<String>(json, 'slug', ''),
        dramaCount: json['drama_count'] == null ? null : api.as<int>(json, 'drama_count', 0),
      );
}

/// One standalone video, as it appears in a rail, a grid or the swipe feed.
class Drama {
  const Drama({
    required this.id,
    required this.title,
    required this.slug,
    this.tagline,
    this.synopsis,
    this.coverImage,
    this.bannerImage,
    this.trailerUrl,
    this.videoUrl,
    this.durationSeconds = 0,
    this.durationLabel = '',
    this.category,
    this.rating,
    this.viewCount = 0,
    this.likeCount = 0,
    this.isFeatured = false,
    this.tags = const [],
    this.releaseYear,
    this.language,
  });

  final int id;
  final String title;
  final String slug;
  final String? tagline;
  final String? synopsis;
  final String? coverImage;
  final String? bannerImage;
  final String? trailerUrl;

  /// MP4/HLS stream or a YouTube link. Every video is free to watch.
  final String? videoUrl;

  final int durationSeconds;

  /// e.g. "1:47"; empty when the duration is unknown.
  final String durationLabel;

  final Category? category;
  final double? rating;
  final int viewCount;
  final int likeCount;
  final bool isFeatured;
  final List<String> tags;
  final int? releaseYear;
  final String? language;

  factory Drama.fromJson(Map<String, dynamic> json) => Drama(
        id: api.as<int>(json, 'id', 0),
        title: api.as<String>(json, 'title', 'Untitled'),
        slug: api.as<String>(json, 'slug', ''),
        tagline: json['tagline'] as String?,
        synopsis: json['synopsis'] as String?,
        coverImage: json['cover_image'] as String?,
        bannerImage: json['banner_image'] as String?,
        trailerUrl: json['trailer_url'] as String?,
        videoUrl: json['video_url'] as String?,
        durationSeconds: api.as<int>(json, 'duration_seconds', 0),
        durationLabel: api.as<String>(json, 'duration_label', ''),
        rating: json['rating'] == null ? null : api.as<double>(json, 'rating', 0),
        viewCount: api.as<int>(json, 'view_count', 0),
        likeCount: api.as<int>(json, 'like_count', 0),
        isFeatured: api.as<bool>(json, 'is_featured', false),
        releaseYear: json['release_year'] == null ? null : api.as<int>(json, 'release_year', 0),
        language: json['language'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        category: json['category'] is Map
            ? Category.fromJson(Map<String, dynamic>.from(json['category'] as Map))
            : null,
      );
}

/// Video detail: the full video plus the viewer's "my list" state.
class DramaDetail {
  const DramaDetail({
    required this.drama,
    this.isFavorite = false,
  });

  final Drama drama;

  /// Whether this title is in the viewer's list. Always false when signed out.
  final bool isFavorite;

  factory DramaDetail.fromJson(Map<String, dynamic> json) => DramaDetail(
        drama: Drama.fromJson(json),
        isFavorite: api.as<bool>(json, 'is_favorite', false),
      );
}

/// The watch-to-earn meter: seconds banked toward the next reward.
///
/// Server-side it runs per user across videos, so the player's reward ring
/// carries on from one video to the next instead of starting over.
class WatchReward {
  const WatchReward({
    this.enabled = true,
    this.seconds = 0,
    this.intervalSeconds = 60,
    this.pointsPerInterval = 1,
    this.capped = false,
  });

  /// Watch rewards switched on by the admin. Off: the player shows no ring.
  final bool enabled;
  final int seconds;
  final int intervalSeconds;
  final int pointsPerInterval;

  /// The daily watch-reward cap is reached; watching earns nothing until tomorrow.
  final bool capped;

  factory WatchReward.fromJson(Map<String, dynamic> json) => WatchReward(
        enabled: api.as<bool>(json, 'enabled', true),
        seconds: api.as<int>(json, 'seconds', 0),
        intervalSeconds: api.as<int>(json, 'interval_seconds', 60),
        pointsPerInterval: api.as<int>(json, 'points_per_interval', 1),
        capped: api.as<bool>(json, 'capped', false),
      );
}

/// A way to be paid (KBZPay, WavePay, PayPal…), as set up by the admin.
class PayoutMethod {
  const PayoutMethod({
    required this.code,
    required this.name,
    required this.accountLabel,
    this.accountHint = '',
    this.input = 'text',
  });

  final String code;
  final String name;

  /// Label for the account field, e.g. "KBZPay phone number".
  final String accountLabel;
  final String accountHint;

  /// "phone", "email" or "text" — picks the keyboard and the validation.
  final String input;

  factory PayoutMethod.fromJson(Map<String, dynamic> json) => PayoutMethod(
        code: api.as<String>(json, 'code', ''),
        name: api.as<String>(json, 'name', ''),
        accountLabel: api.as<String>(json, 'account_label', 'Account'),
        accountHint: api.as<String>(json, 'account_hint', ''),
        input: api.as<String>(json, 'input', 'text'),
      );
}

/// The wallet summary returned by `GET /api/v1/wallet`.
class Wallet {
  const Wallet({
    required this.pointsBalance,
    required this.totalEarned,
    required this.totalSpent,
    required this.pointsPerUnit,
    required this.currency,
    required this.cashValue,
    required this.minWithdrawalPoints,
    required this.canWithdraw,
    required this.checkInAvailable,
    required this.checkInPoints,
    required this.adRewardPoints,
    required this.adsClaimedToday,
    required this.dailyAdLimit,
    this.checkInEnabled = true,
    this.adRewardEnabled = true,
    this.watchReward = const WatchReward(),
    this.payoutMethods = const [],
  });

  final int pointsBalance;
  final int totalEarned;
  final int totalSpent;
  final int pointsPerUnit;
  final String currency;
  final double cashValue;
  final int minWithdrawalPoints;
  final bool canWithdraw;
  final bool checkInAvailable;
  final int checkInPoints;
  final int adRewardPoints;
  final int adsClaimedToday;
  final int dailyAdLimit;

  /// Switched off by the admin: the wallet hides the row.
  final bool checkInEnabled;
  final bool adRewardEnabled;

  final WatchReward watchReward;

  /// The methods a user may cash out with, in the admin's order.
  final List<PayoutMethod> payoutMethods;

  int get adsRemainingToday {
    final remaining = dailyAdLimit - adsClaimedToday;
    return remaining < 0 ? 0 : remaining;
  }

  /// How many points are still needed before a payout can be requested.
  int get pointsToWithdrawal {
    final missing = minWithdrawalPoints - pointsBalance;
    return missing < 0 ? 0 : missing;
  }

  double get withdrawalProgress {
    if (minWithdrawalPoints <= 0) return 1;
    final ratio = pointsBalance / minWithdrawalPoints;
    return ratio.clamp(0, 1).toDouble();
  }

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        pointsBalance: api.as<int>(json, 'points_balance', 0),
        totalEarned: api.as<int>(json, 'total_points_earned', 0),
        totalSpent: api.as<int>(json, 'total_points_spent', 0),
        pointsPerUnit: api.as<int>(json, 'points_per_currency_unit', 1000),
        currency: api.as<String>(json, 'currency', 'USD'),
        cashValue: api.as<double>(json, 'cash_value', 0),
        minWithdrawalPoints: api.as<int>(json, 'min_withdrawal_points', 5000),
        canWithdraw: api.as<bool>(json, 'can_withdraw', false),
        checkInAvailable: api.as<bool>(json, 'check_in_available', true),
        checkInPoints: api.as<int>(json, 'check_in_points', 20),
        adRewardPoints: api.as<int>(json, 'ad_reward_points', 10),
        adsClaimedToday: api.as<int>(json, 'ads_claimed_today', 0),
        dailyAdLimit: api.as<int>(json, 'daily_ad_limit', 20),
        checkInEnabled: api.as<bool>(json, 'check_in_enabled', true),
        adRewardEnabled: api.as<bool>(json, 'ad_reward_enabled', true),
        watchReward: json['watch_reward'] is Map
            ? WatchReward.fromJson(Map<String, dynamic>.from(json['watch_reward'] as Map))
            : const WatchReward(),
        payoutMethods: (json['payout_methods'] as List?)
                ?.whereType<Map>()
                .map((e) => PayoutMethod.fromJson(Map<String, dynamic>.from(e)))
                .where((m) => m.code.isNotEmpty)
                .toList() ??
            const [],
      );
}

/// One row of the append-only points history.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.delta,
    required this.balanceAfter,
    required this.description,
    this.createdAt,
  });

  final int id;
  final String type;
  final String typeLabel;
  final int delta;
  final int balanceAfter;
  final String description;
  final DateTime? createdAt;

  bool get isCredit => delta >= 0;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: api.as<int>(json, 'id', 0),
        type: api.as<String>(json, 'type', 'unknown'),
        typeLabel: api.as<String>(json, 'type_label', 'Adjustment'),
        delta: api.as<int>(json, 'delta', 0),
        balanceAfter: api.as<int>(json, 'balance_after', 0),
        description: api.as<String>(json, 'description', ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

/// A cash-out request.
class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.pointsAmount,
    required this.amount,
    required this.currency,
    required this.method,
    required this.status,
    required this.statusLabel,
    this.methodName,
    this.adminNote,
    this.createdAt,
  });

  final int id;
  final int pointsAmount;
  final String amount;
  final String currency;
  final String method;

  /// e.g. "KBZPay"; null from older servers.
  final String? methodName;
  final String status;
  final String statusLabel;
  final String? adminNote;
  final DateTime? createdAt;

  factory Withdrawal.fromJson(Map<String, dynamic> json) => Withdrawal(
        id: api.as<int>(json, 'id', 0),
        pointsAmount: api.as<int>(json, 'points_amount', 0),
        amount: api.as<String>(json, 'amount', '0.00'),
        currency: api.as<String>(json, 'currency', 'USD'),
        method: api.as<String>(json, 'method', 'paypal'),
        methodName: json['method_name'] as String?,
        status: api.as<String>(json, 'status', 'pending'),
        statusLabel: api.as<String>(json, 'status_label', 'Pending'),
        adminNote: json['admin_note'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

/// The home feed: every rail in one response.
class HomeFeed {
  const HomeFeed({
    required this.featured,
    required this.latest,
    required this.trending,
    required this.categories,
  });

  final List<Drama> featured;
  final List<Drama> latest;
  final List<Drama> trending;
  final List<Category> categories;

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    List<Drama> dramas(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Drama.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return HomeFeed(
      featured: dramas(json['featured']),
      latest: dramas(json['latest']),
      trending: dramas(json['trending']),
      categories: (json['categories'] is List)
          ? (json['categories'] as List)
              .whereType<Map>()
              .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  bool get isEmpty =>
      featured.isEmpty && latest.isEmpty && trending.isEmpty;
}

/// One entry in the user's in-app inbox.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.title,
    required this.isRead,
    required this.route,
    this.body,
    this.data,
    this.readAt,
    this.createdAt,
  });

  final int id;
  final String type;
  final String typeLabel;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;

  /// Which screen the notification points at: home, wallet, player, drama.
  final String route;

  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        typeLabel: typeLabel,
        title: title,
        body: body,
        data: data,
        route: route,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: api.as<int>(json, 'id', 0),
        type: api.as<String>(json, 'type', 'system'),
        typeLabel: api.as<String>(json, 'type_label', 'System message'),
        title: api.as<String>(json, 'title', ''),
        body: json['body'] as String?,
        data: json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : null,
        route: api.as<String>(json, 'route', 'home'),
        isRead: api.as<bool>(json, 'is_read', false),
        readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

/// Where the viewer stopped in one video.
class WatchProgressItem {
  const WatchProgressItem({
    required this.dramaId,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.percent,
    required this.isCompleted,
    this.drama,
    this.lastWatchedAt,
  });

  final int dramaId;
  final int positionSeconds;
  final int durationSeconds;

  /// 0–100.
  final int percent;

  final bool isCompleted;
  final Drama? drama;
  final DateTime? lastWatchedAt;

  Duration get position => Duration(seconds: positionSeconds);

  factory WatchProgressItem.fromJson(Map<String, dynamic> json) {
    final rawDrama = json['drama'];

    return WatchProgressItem(
      dramaId: api.as<int>(json, 'drama_id', 0),
      positionSeconds: api.as<int>(json, 'position_seconds', 0),
      durationSeconds: api.as<int>(json, 'duration_seconds', 0),
      percent: api.as<int>(json, 'percent', 0),
      isCompleted: api.as<bool>(json, 'is_completed', false),
      drama: rawDrama is Map
          ? Drama.fromJson(Map<String, dynamic>.from(rawDrama))
          : null,
      lastWatchedAt: DateTime.tryParse(json['last_watched_at'] as String? ?? ''),
    );
  }
}

/// One wedge of the lucky wheel.
class WheelSegment {
  const WheelSegment({required this.index, required this.points});

  final int index;
  final int points;

  factory WheelSegment.fromJson(Map<String, dynamic> json) => WheelSegment(
        index: api.as<int>(json, 'index', 0),
        points: api.as<int>(json, 'points', 0),
      );
}

/// The wheel as the server describes it.
class LuckyWheelState {
  const LuckyWheelState({
    required this.segments,
    required this.dailyLimit,
    required this.spinsRemaining,
    required this.spinsUsedToday,
    this.enabled = true,
  });

  final List<WheelSegment> segments;
  final int dailyLimit;
  final int spinsRemaining;
  final int spinsUsedToday;

  /// Closed by the admin.
  final bool enabled;

  bool get canSpin => enabled && spinsRemaining > 0 && segments.isNotEmpty;

  factory LuckyWheelState.fromJson(Map<String, dynamic> json) => LuckyWheelState(
        enabled: api.as<bool>(json, 'enabled', true),
        segments: json['segments'] is List
            ? (json['segments'] as List)
                .whereType<Map>()
                .map((e) => WheelSegment.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
        dailyLimit: api.as<int>(json, 'daily_limit', 0),
        spinsRemaining: api.as<int>(json, 'spins_remaining', 0),
        spinsUsedToday: api.as<int>(json, 'spins_used_today', 0),
      );
}
