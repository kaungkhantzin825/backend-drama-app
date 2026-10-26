import 'package:dramaloop/models/models.dart';
import 'package:dramaloop/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player's reward ring. It must keep its progress when the viewer swipes
/// to another video, and stay in step with the server's meter.
void main() {
  late ProviderContainer container;
  late WatchMeterController meter;

  WatchReward read() => container.read(watchMeterProvider);

  setUp(() {
    container = ProviderContainer();
    meter = container.read(watchMeterProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('ticks on from where the server left off and wraps at the interval', () {
    meter.sync(const WatchReward(seconds: 50, intervalSeconds: 60));
    expect(meter.isSynced, isTrue);

    for (var i = 0; i < 9; i++) {
      meter.tick();
    }
    expect(read().seconds, 59);

    meter.tick();
    expect(read().seconds, 0);
  });

  test('adds the seconds played since the heartbeat it answers', () {
    meter.sync(const WatchReward(seconds: 20, intervalSeconds: 60), unreportedSeconds: 3);

    expect(read().seconds, 23);
  });

  test('a switched-off meter does not tick', () {
    meter.sync(const WatchReward(enabled: false, seconds: 30, intervalSeconds: 60));

    meter.tick();

    expect(read().enabled, isFalse);
    expect(read().seconds, 0);
  });

  test('a capped meter stays empty and does not tick', () {
    meter.sync(const WatchReward(seconds: 40, intervalSeconds: 60, capped: true));

    meter.tick();

    expect(read().capped, isTrue);
    expect(read().seconds, 0);
  });
}
