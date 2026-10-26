import 'package:dramaloop/core/api_client.dart';
import 'package:dramaloop/core/format.dart';
import 'package:dramaloop/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// These fixtures are verbatim responses from the Laravel API, so a change in
/// the backend's resource shape fails here rather than silently producing an
/// empty screen on a phone.
void main() {
  group('Fmt', () {
    test('compacts large counts', () {
      expect(Fmt.compact(999), '999');
      expect(Fmt.compact(12400), '12.4K');
      expect(Fmt.compact(1200000), '1.2M');
    });

    test('groups thousands', () {
      expect(Fmt.points(950), '950');
      expect(Fmt.points(1250), '1,250');
      expect(Fmt.points(5000), '5,000');
      expect(Fmt.points(1234567), '1,234,567');
    });

    test('formats cash with a currency symbol', () {
      expect(Fmt.cash(2.5), r'$2.50');
      expect(Fmt.cash(0), r'$0.00');
      expect(Fmt.cash(12.345), r'$12.35');
      expect(Fmt.cash(1234.5), r'$1,234.50');
    });

    test('formats whole-unit currencies like MMK without decimals', () {
      expect(Fmt.cash(5000, currency: 'MMK'), '5,000 MMK');
      expect(Fmt.cash(1250.6, currency: 'mmk'), '1,251 MMK');
      expect(Fmt.cash(3.5, currency: 'THB'), '3.50 THB');
    });

    test('formats video durations', () {
      expect(Fmt.duration(0), '0:00');
      expect(Fmt.duration(95), '1:35');
      expect(Fmt.duration(180), '3:00');
    });
  });

  group('Wallet', () {
    test('parses the wallet summary payload', () {
      final wallet = Wallet.fromJson({
        'points_balance': 2500,
        'total_points_earned': 3000,
        'total_points_spent': 500,
        'points_per_currency_unit': 1000,
        'currency': 'USD',
        'cash_value': 2.5,
        'min_withdrawal_points': 5000,
        'can_withdraw': false,
        'check_in_available': true,
        'check_in_points': 20,
        'ad_reward_points': 10,
        'ads_claimed_today': 4,
        'daily_ad_limit': 20,
      });

      expect(wallet.pointsBalance, 2500);
      expect(wallet.cashValue, 2.5);
      expect(wallet.canWithdraw, isFalse);
      expect(wallet.adsRemainingToday, 16);
      expect(wallet.pointsToWithdrawal, 2500);
      expect(wallet.withdrawalProgress, 0.5);
    });

    test('never reports negative progress or remaining points', () {
      final wallet = Wallet.fromJson({
        'points_balance': 9000,
        'min_withdrawal_points': 5000,
        'ads_claimed_today': 25,
        'daily_ad_limit': 20,
      });

      expect(wallet.pointsToWithdrawal, 0);
      expect(wallet.withdrawalProgress, 1.0);
      expect(wallet.adsRemainingToday, 0);
    });

    test('parses the watch-to-earn meter', () {
      final wallet = Wallet.fromJson({
        'points_balance': 10,
        'watch_reward': {
          'seconds': 50,
          'interval_seconds': 60,
          'points_per_interval': 1,
          'earned_today': 3,
          'daily_cap': 100,
          'capped': false,
        },
      });

      expect(wallet.watchReward.seconds, 50);
      expect(wallet.watchReward.intervalSeconds, 60);
      expect(wallet.watchReward.pointsPerInterval, 1);
      expect(wallet.watchReward.capped, isFalse);
    });

    test('parses the admin switches and payment methods', () {
      final wallet = Wallet.fromJson({
        'points_balance': 10,
        'currency': 'MMK',
        'check_in_enabled': false,
        'ad_reward_enabled': true,
        'payout_methods': [
          {
            'code': 'kbzpay',
            'name': 'KBZPay',
            'account_label': 'KBZPay phone number',
            'account_hint': '09xxxxxxxxx',
            'input': 'phone',
          },
          {'code': '', 'name': 'Broken'},
        ],
      });

      expect(wallet.currency, 'MMK');
      expect(wallet.checkInEnabled, isFalse);
      expect(wallet.adRewardEnabled, isTrue);
      expect(wallet.payoutMethods, hasLength(1));
      expect(wallet.payoutMethods.single.accountLabel, 'KBZPay phone number');
      expect(wallet.payoutMethods.single.input, 'phone');
    });

    test('an older payload without a meter starts it at zero', () {
      final wallet = Wallet.fromJson({'points_balance': 10});

      expect(wallet.watchReward.seconds, 0);
      expect(wallet.watchReward.intervalSeconds, 60);
    });
  });

  group('Drama', () {
    test('a feed item carries its stream url and duration', () {
      final video = Drama.fromJson({
        'id': 10,
        'title': 'Midnight Oath',
        'slug': 'demo-midnight-oath',
        'tagline': 'A detective wakes with no memory…',
        'video_url': 'https://www.youtube.com/embed/2Z1UYAFdaIg',
        'duration_seconds': 180,
        'duration_label': '3:00',
        'category': {'id': 2, 'name': 'Suspense', 'slug': 'suspense'},
      });

      expect(video.videoUrl, 'https://www.youtube.com/embed/2Z1UYAFdaIg');
      expect(video.durationSeconds, 180);
      expect(video.durationLabel, '3:00');
      expect(video.category?.name, 'Suspense');
    });

    test('a video without media parses safely', () {
      final video = Drama.fromJson({'id': 1, 'title': 'Draft', 'slug': 'draft'});

      expect(video.videoUrl, isNull);
      expect(video.durationSeconds, 0);
      expect(video.durationLabel, '');
    });
  });

  group('HomeFeed', () {
    test('parses every rail from the home payload', () {
      final feed = HomeFeed.fromJson({
        'featured': [
          {'id': 1, 'title': 'Featured One', 'slug': 'f1', 'duration_seconds': 60},
        ],
        'latest': [
          {'id': 2, 'title': 'New One', 'slug': 'n1', 'duration_seconds': 40},
        ],
        'trending': [
          {'id': 3, 'title': 'Hot One', 'slug': 'h1', 'duration_seconds': 80},
        ],
        'categories': [
          {'id': 1, 'name': 'CEO', 'slug': 'ceo'},
        ],
      });

      expect(feed.featured.single.title, 'Featured One');
      expect(feed.latest.single.durationSeconds, 40);
      expect(feed.trending.single.slug, 'h1');
      expect(feed.categories.single.name, 'CEO');
      expect(feed.isEmpty, isFalse);
    });

    test('tolerates empty rails', () {
      final feed = HomeFeed.fromJson({
        'featured': <dynamic>[],
        'latest': <dynamic>[],
        'trending': <dynamic>[],
        'categories': <dynamic>[],
      });

      expect(feed.isEmpty, isTrue);
    });
  });

  group('DramaDetail', () {
    test('parses the video and the list state', () {
      final detail = DramaDetail.fromJson({
        'id': 1,
        'title': 'The Billionaire Heir',
        'slug': 'heir',
        'synopsis': 'The whole story.',
        'video_url': 'https://cdn.example/heir.m3u8',
        'is_favorite': true,
      });

      expect(detail.drama.title, 'The Billionaire Heir');
      expect(detail.drama.synopsis, 'The whole story.');
      expect(detail.drama.videoUrl, 'https://cdn.example/heir.m3u8');
      expect(detail.isFavorite, isTrue);
    });
  });

  group('Paginated', () {
    test('reads items and metadata from the paginator payload', () {
      final page = Paginated.fromMap(
        {
          'data': [
            {'id': 1, 'description': 'Daily check-in', 'delta': 20},
          ],
          'meta': {'current_page': 2, 'last_page': 3, 'total': 8},
        },
        LedgerEntry.fromJson,
      );

      expect(page.items.single.description, 'Daily check-in');
      expect(page.currentPage, 2);
      expect(page.lastPage, 3);
      expect(page.total, 8);
      expect(page.hasMore, isTrue);
    });

    test('handles an empty page', () {
      final page = Paginated.fromMap(
        {'data': <dynamic>[], 'meta': {'current_page': 1, 'last_page': 1, 'total': 0}},
        LedgerEntry.fromJson,
      );

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('LedgerEntry', () {
    test('marks credits and debits by sign', () {
      final credit = LedgerEntry.fromJson({'id': 1, 'delta': 20, 'balance_after': 20});
      final debit = LedgerEntry.fromJson({'id': 2, 'delta': -30, 'balance_after': 0});

      expect(credit.isCredit, isTrue);
      expect(debit.isCredit, isFalse);
    });
  });

  group('AppUser', () {
    test('falls back to Guest when the account has no name', () {
      final user = AppUser.fromJson({'id': 7, 'name': null, 'is_guest': true});

      expect(user.displayName, 'Guest');
      expect(user.initials, 'G');
    });

    test('derives initials from a full name', () {
      final user = AppUser.fromJson({'id': 7, 'name': 'Ada Lovelace'});

      expect(user.initials, 'AL');
    });

    test('copyWith updates only the balance', () {
      final user = AppUser.fromJson({'id': 7, 'name': 'Ada', 'points_balance': 100});
      final updated = user.copyWith(pointsBalance: 500);

      expect(updated.pointsBalance, 500);
      expect(updated.name, 'Ada');
    });
  });

  group('AppNotification', () {
    test('parses the inbox payload', () {
      final notification = AppNotification.fromJson({
        'id': 12,
        'type': 'withdrawal_paid',
        'type_label': 'Withdrawal paid',
        'title': 'Withdrawal paid',
        'body': r'$5.00 has been sent to your paypal account.',
        'data': {'withdrawal_id': 3, 'status': 'paid'},
        'route': 'wallet',
        'is_read': false,
        'read_at': null,
        'created_at': '2026-10-24T10:00:00+00:00',
      });

      expect(notification.id, 12);
      expect(notification.type, 'withdrawal_paid');
      expect(notification.route, 'wallet');
      expect(notification.isRead, isFalse);
      expect(notification.data?['withdrawal_id'], 3);
      expect(notification.createdAt, isNotNull);
    });

    test('falls back to safe defaults when the payload is thin', () {
      final notification = AppNotification.fromJson({'id': 1});

      expect(notification.title, '');
      expect(notification.type, 'system');
      expect(notification.route, 'home');
      expect(notification.isRead, isFalse);
      expect(notification.body, isNull);
      expect(notification.data, isNull);
    });

    test('copyWith marks read without losing the content', () {
      final notification = AppNotification.fromJson({
        'id': 5,
        'title': 'Reward granted',
        'body': 'You earned 20 points.',
      });

      final read = notification.copyWith(isRead: true, readAt: DateTime(2026));

      expect(read.isRead, isTrue);
      expect(read.readAt, isNotNull);
      expect(read.title, 'Reward granted');
      expect(read.body, 'You earned 20 points.');
    });
  });

  group('WatchProgressItem', () {
    test('parses a continue-watching row with its drama', () {
      final item = WatchProgressItem.fromJson({
        'drama_id': 7,
        'position_seconds': 90,
        'duration_seconds': 180,
        'percent': 50,
        'is_completed': false,
        'last_watched_at': '2026-10-24T09:30:00+00:00',
        'drama': {
          'id': 7,
          'slug': 'the-heir',
          'title': 'The Heir',
          'cover_image': 'https://cdn.example/cover.jpg',
        },
      });

      expect(item.dramaId, 7);
      expect(item.percent, 50);
      expect(item.position, const Duration(seconds: 90));
      expect(item.isCompleted, isFalse);
      expect(item.drama?.slug, 'the-heir');
      expect(item.lastWatchedAt, isNotNull);
    });

    test('survives a row with no drama embedded', () {
      final item = WatchProgressItem.fromJson({'drama_id': 2});

      expect(item.drama, isNull);
      expect(item.percent, 0);
      expect(item.positionSeconds, 0);
      expect(item.isCompleted, isFalse);
    });
  });

  group('LuckyWheelState', () {
    test('parses segments and the daily allowance', () {
      final wheel = LuckyWheelState.fromJson({
        'segments': [
          {'index': 0, 'points': 5},
          {'index': 1, 'points': 50},
        ],
        'daily_limit': 3,
        'spins_remaining': 2,
        'spins_used_today': 1,
      });

      expect(wheel.segments, hasLength(2));
      expect(wheel.segments.last.points, 50);
      expect(wheel.dailyLimit, 3);
      expect(wheel.spinsRemaining, 2);
      expect(wheel.spinsUsedToday, 1);
      expect(wheel.canSpin, isTrue);
    });

    test('refuses to spin when the allowance is spent', () {
      final wheel = LuckyWheelState.fromJson({
        'segments': [
          {'index': 0, 'points': 5},
        ],
        'daily_limit': 3,
        'spins_remaining': 0,
        'spins_used_today': 3,
      });

      expect(wheel.canSpin, isFalse);
    });

    test('refuses to spin when the server sends no segments', () {
      final wheel = LuckyWheelState.fromJson({
        'segments': <Object>[],
        'daily_limit': 3,
        'spins_remaining': 3,
        'spins_used_today': 0,
      });

      expect(wheel.segments, isEmpty);
      expect(wheel.canSpin, isFalse);
    });
  });
}
