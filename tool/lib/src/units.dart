/// Byte sizes: parsing budget strings ("25MB", "500 KB", "2%") and
/// formatting numbers for humans.
///
/// All units are binary (1 KB = 1024 B), the same convention
/// `flutter build --analyze-size` uses when it prints its table.
library;

const _units = <String, int>{
  'b': 1,
  'k': 1024,
  'kb': 1024,
  'kib': 1024,
  'm': 1024 * 1024,
  'mb': 1024 * 1024,
  'mib': 1024 * 1024,
  'g': 1024 * 1024 * 1024,
  'gb': 1024 * 1024 * 1024,
  'gib': 1024 * 1024 * 1024,
};

final _sizePattern = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]*)\s*$');

/// Parses "25MB", "25 mb", "1.5MiB", "4096" (bytes) into bytes.
///
/// Throws [FormatException] for anything else.
int parseBytes(String input) {
  final match = _sizePattern.firstMatch(input);
  if (match == null) {
    throw FormatException('Not a size: "$input" (expected e.g. 25MB, 500KB, 4096)');
  }
  final value = double.parse(match.group(1)!);
  final unit = match.group(2)!.toLowerCase();
  final factor = unit.isEmpty ? 1 : _units[unit];
  if (factor == null) {
    throw FormatException('Unknown size unit "${match.group(2)}" in "$input" (use B, KB, MB or GB)');
  }
  return (value * factor).round();
}

/// A limit on growth: either an absolute number of bytes or a percentage of
/// the baseline.
class Threshold {
  const Threshold.bytes(int this.bytes) : percent = null;
  const Threshold.percent(double this.percent) : bytes = null;

  /// Parses "500KB" or "2%" / "2.5 %".
  factory Threshold.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.endsWith('%')) {
      final number = double.tryParse(trimmed.substring(0, trimmed.length - 1).trim());
      if (number == null || number < 0) {
        throw FormatException('Not a percentage: "$input"');
      }
      return Threshold.percent(number);
    }
    return Threshold.bytes(parseBytes(trimmed));
  }

  final int? bytes;
  final double? percent;

  /// The allowed increase in bytes over [base].
  int allowedIncrease(int base) => bytes ?? (base * percent! / 100).floor();

  @override
  String toString() => bytes != null ? formatBytes(bytes!) : '${_trimNumber(percent!)}%';
}

/// 1536 -> "1.5 KB", 0 -> "0 B". Always non-negative input expected; use
/// [formatDelta] for signed values.
String formatBytes(int bytes) {
  final abs = bytes.abs();
  final sign = bytes < 0 ? '-' : '';
  if (abs < 1024) {
    return '$sign$abs B';
  }
  if (abs < 1024 * 1024) {
    return '$sign${(abs / 1024).toStringAsFixed(1)} KB';
  }
  if (abs < 1024 * 1024 * 1024) {
    return '$sign${(abs / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '$sign${(abs / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// +2048 -> "+2.0 KB", -10 -> "-10 B", 0 -> "0 B".
String formatDelta(int delta) {
  if (delta == 0) {
    return '0 B';
  }
  return delta > 0 ? '+${formatBytes(delta)}' : formatBytes(delta);
}

/// Percentage change from [base] to [head], or null when there is no
/// meaningful base.
double? percentChange(int base, int head) {
  if (base == 0) {
    return null;
  }
  return (head - base) * 100 / base;
}

/// 1.234 -> "+1.23%", -0.5 -> "-0.50%".
String formatPercent(double? percent) {
  if (percent == null) {
    return 'new';
  }
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}

String _trimNumber(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
