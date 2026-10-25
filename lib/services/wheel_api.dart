import '../core/api_client.dart';
import '../models/models.dart';

/// The lucky wheel.
///
/// The server owns the prize table and the outcome; this service only asks for
/// the wheel and then reports the spin.
class WheelApi {
  WheelApi(this._api);

  final ApiClient _api;

  Future<LuckyWheelState> state() async {
    final data = await _api.get('/rewards/lucky-wheel');
    return LuckyWheelState.fromJson(data);
  }

  /// Spin once. Returns the prize the server picked and the segment to land on.
  Future<({int prizePoints, int segmentIndex, int spinsRemaining, Wallet wallet})> spin() async {
    final data = await _api.post('/rewards/lucky-wheel/spin');

    return (
      prizePoints: as<int>(data, 'prize_points', 0),
      segmentIndex: as<int>(data, 'segment_index', 0),
      spinsRemaining: as<int>(data, 'spins_remaining', 0),
      wallet: Wallet.fromJson(
        Map<String, dynamic>.from(data['wallet'] as Map? ?? const {}),
      ),
    );
  }
}
