import '../core/api_client.dart';
import '../models/models.dart';

/// Wallet, earning and cash-out.
///
/// Every amount is decided by the server; this service only relays the
/// request and returns whatever the server recorded.
class WalletApi {
  WalletApi(this._api);

  final ApiClient _api;

  Future<Wallet> wallet() async {
    final data = await _api.get('/wallet');
    return Wallet.fromJson(data);
  }

  Future<Paginated<LedgerEntry>> ledger({int page = 1}) async {
    final data = await _api.get('/wallet/ledger', query: {'page': page});
    return Paginated.fromMap(data, LedgerEntry.fromJson);
  }

  /// Once-per-day check-in. Returns the awarded points and the fresh wallet.
  Future<({int pointsAwarded, Wallet wallet})> checkIn() async {
    final data = await _api.post('/rewards/check-in');
    return (
      pointsAwarded: as<int>(data, 'points_awarded', 0),
      wallet: Wallet.fromJson(
        Map<String, dynamic>.from(data['wallet'] as Map? ?? const {}),
      ),
    );
  }

  /// Report a completed rewarded-ad impression.
  ///
  /// [idempotencyKey] must be stable for one impression so a retry on a flaky
  /// connection cannot mint points twice.
  Future<({int pointsAwarded, Wallet wallet})> claimAdReward({
    required String placement,
    required String idempotencyKey,
    required String deviceId,
    String? provider,
  }) async {
    final data = await _api.post('/ads/events', body: {
      'placement': placement,
      'idempotency_key': idempotencyKey,
      'device_id': deviceId,
      if (provider != null) 'provider': provider,
    });

    return (
      pointsAwarded: as<int>(data, 'points_awarded', 0),
      wallet: Wallet.fromJson(
        Map<String, dynamic>.from(data['wallet'] as Map? ?? const {}),
      ),
    );
  }

  Future<Paginated<Withdrawal>> withdrawals({int page = 1}) async {
    final data = await _api.get('/withdrawals', query: {'page': page});
    return Paginated.fromMap(data, Withdrawal.fromJson);
  }

  /// Request a payout of the whole balance.
  Future<Withdrawal> requestWithdrawal({
    required String method,
    required Map<String, dynamic> accountDetails,
  }) async {
    final data = await _api.post('/withdrawals', body: {
      'method': method,
      'account_details': accountDetails,
    });

    return Withdrawal.fromJson(data);
  }
}
