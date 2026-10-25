/// Presentation helpers shared across screens.
class Fmt {
  const Fmt._();

  /// 12_400 → "12.4K", 1_200_000 → "1.2M".
  static String compact(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final k = value / 1000;
      return '${_trim(k)}K';
    }
    final m = value / 1000000;
    return '${_trim(m)}M';
  }

  /// 950 → "950", 1250 → "1,250".
  static String points(int value) => withThousands(value);

  static String withThousands(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    return '${value < 0 ? '-' : ''}$buffer';
  }

  /// 2.5 → "$2.50".
  static String cash(double amount, {String currency = 'USD'}) {
    final symbol = switch (currency) {
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };

    return '$symbol${amount.toStringAsFixed(2)}';
  }

  /// 95 seconds → "1:35".
  static String duration(int seconds) {
    if (seconds <= 0) return '0:00';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// A relative timestamp for the ledger: "Today", "Yesterday", "3d ago".
  static String relative(DateTime? value) {
    if (value == null) return '';

    final now = DateTime.now();
    final date = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final days = today.difference(that).inDays;

    if (days == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d ago';

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _trim(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }
}
