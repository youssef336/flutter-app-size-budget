import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

void main() {
  group('parseBytes', () {
    test('accepts binary units, spaces and case', () {
      expect(parseBytes('4096'), 4096);
      expect(parseBytes('500KB'), 500 * 1024);
      expect(parseBytes('500 kb'), 500 * 1024);
      expect(parseBytes('25MB'), 25 * 1024 * 1024);
      expect(parseBytes('1.5MiB'), (1.5 * 1024 * 1024).round());
      expect(parseBytes('1G'), 1024 * 1024 * 1024);
    });

    test('rejects junk', () {
      expect(() => parseBytes('big'), throwsFormatException);
      expect(() => parseBytes('10 TB'), throwsFormatException);
      expect(() => parseBytes('-5MB'), throwsFormatException);
    });
  });

  group('Threshold', () {
    test('bytes and percent', () {
      final bytes = Threshold.parse('500KB');
      expect(bytes.allowedIncrease(10 * 1024 * 1024), 500 * 1024);
      expect(bytes.toString(), '500.0 KB');

      final pct = Threshold.parse('2%');
      expect(pct.allowedIncrease(1000000), 20000);
      expect(pct.toString(), '2%');
      expect(Threshold.parse('2.5 %').toString(), '2.5%');
    });

    test('rejects bad percentages', () {
      expect(() => Threshold.parse('x%'), throwsFormatException);
    });
  });

  test('formatting', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(15810481), '15.08 MB');
    expect(formatDelta(0), '0 B');
    expect(formatDelta(2048), '+2.0 KB');
    expect(formatDelta(-10), '-10 B');
    expect(formatPercent(percentChange(200, 202)), '+1.00%');
    expect(formatPercent(percentChange(200, 199)), '-0.50%');
    expect(formatPercent(percentChange(0, 10)), 'new');
  });
}
