import 'dart:async';

import 'package:flutter/foundation.dart';

/// Batches ad SDK events and ships them to `POST /api/v1/ads/traffic`.
///
/// Every waterfall step reports `request` → `fill` / `no_fill` / `timeout`,
/// and every shown ad `impression`, `click`, `show_failed` and `paid` (with
/// its revenue). The backend folds them into per-unit daily counters — the
/// admin "Traffic → Ads" screen and the A/B comparison are built from them.
///
/// Sending is best-effort: a failed batch is put back and retried with the
/// next one, and the queue is capped so an offline session cannot grow it
/// without bound.
class AdTrafficReporter {
  AdTrafficReporter(this._send);

  final Future<void> Function(List<Map<String, dynamic>> events) _send;

  static const int _batchSize = 25;
  static const int _maxQueue = 200;
  static const Duration _interval = Duration(seconds: 30);

  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _sending = false;

  void track(
    String event, {
    required String format,
    String? placement,
    String? unitId,
    int? tier,
    int? valueMicros,
  }) {
    _queue.add({
      'event': event,
      'format': format,
      if (placement != null) 'placement': placement,
      if (unitId != null) 'unit_id': unitId,
      if (tier != null) 'tier': tier,
      if (valueMicros != null) 'value_micros': valueMicros,
    });

    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }

    if (_queue.length >= _batchSize) {
      unawaited(flush());
    } else {
      _timer ??= Timer(_interval, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;

    _sending = true;
    final batch = _queue.take(100).toList();
    _queue.removeRange(0, batch.length);

    try {
      await _send(batch);
    } catch (error) {
      // Put it back in front; it goes out with the next flush.
      _queue.insertAll(0, batch);
      if (_queue.length > _maxQueue) {
        _queue.removeRange(_maxQueue, _queue.length);
      }
      debugPrint('Ad traffic report failed, will retry: $error');
    } finally {
      _sending = false;
    }
  }
}
