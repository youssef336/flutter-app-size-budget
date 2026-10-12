import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final base = baseSnapshot();
  final head = headSnapshot();
  final diff = SizeDiff.compare(base, head);

  group('Budget.parse', () {
    test('full file', () {
      final budget = Budget.parse('''
max-size: 25MB
max-increase: 2%
categories:
  assets:
    max-size: 5MB
  dart:
    max-increase: 300KB
packages:
  "*":
    max-increase: 100KB
  http:
    max-size: 10KB
''');
      expect(budget.total.maxSize, 25 * 1024 * 1024);
      expect(budget.total.maxIncrease.toString(), '2%');
      expect(budget.categories['assets']!.maxSize, 5 * 1024 * 1024);
      expect(budget.categories['dart']!.maxIncrease!.bytes, 300 * 1024);
      expect(budget.packages.keys, ['*', 'http']);
      expect(budget.isEmpty, isFalse);
    });

    test('empty file is an empty budget', () {
      expect(Budget.parse('').isEmpty, isTrue);
      expect(Budget.parse('# nothing').isEmpty, isTrue);
    });

    test('typos are errors, not silently ignored', () {
      expect(() => Budget.parse('max_size: 1MB'), throwsFormatException);
      expect(() => Budget.parse('categories:\n  images:\n    max-size: 1MB'), throwsFormatException);
      expect(() => Budget.parse('categories:\n  dart:\n    limit: 1MB'), throwsFormatException);
      expect(() => Budget.parse('max-size: lots'), throwsFormatException);
    });

    test('inputs override the file, blanks keep it', () {
      final budget = Budget.parse('max-size: 25MB\nmax-increase: 2%');
      final same = budget.withOverrides(maxSize: '', maxIncrease: ' ');
      expect(same.total.maxSize, 25 * 1024 * 1024);
      final overridden = budget.withOverrides(maxSize: '20MB', maxIncrease: '500KB');
      expect(overridden.total.maxSize, 20 * 1024 * 1024);
      expect(overridden.total.maxIncrease!.bytes, 500 * 1024);
    });
  });

  group('evaluateBudget on the real pair (+315.4 KB, +2.09%)', () {
    test('passes generous limits', () {
      final budget = const Budget().withOverrides(maxSize: '20MB', maxIncrease: '500KB');
      expect(evaluateBudget(budget, head, diff: diff), isEmpty);
    });

    test('max-size', () {
      final budget = const Budget().withOverrides(maxSize: '15MB');
      final v = evaluateBudget(budget, head, diff: diff);
      expect(v.single.scope, 'total');
      expect(v.single.message, contains('over the 15.00 MB limit'));
    });

    test('max-increase in bytes and percent', () {
      expect(
        evaluateBudget(const Budget().withOverrides(maxIncrease: '300KB'), head, diff: diff).single.message,
        allOf(contains('+315.4 KB'), contains('+2.09%'), contains('300.0 KB')),
      );
      expect(evaluateBudget(const Budget().withOverrides(maxIncrease: '2%'), head, diff: diff), hasLength(1));
      expect(evaluateBudget(const Budget().withOverrides(maxIncrease: '2.1%'), head, diff: diff), isEmpty);
    });

    test('increase limits are skipped without a baseline', () {
      final budget = const Budget().withOverrides(maxSize: '20MB', maxIncrease: '1KB');
      expect(evaluateBudget(budget, head), isEmpty);
    });

    test('categories', () {
      final budget = Budget.parse('''
categories:
  assets:
    max-increase: 50KB
  engine:
    max-size: 12MB
''');
      final v = evaluateBudget(budget, head, diff: diff);
      expect(v.map((x) => x.scope), ['category:assets']);
      expect(v.single.message, startsWith('Assets grew by +59.3 KB'));
    });

    test('packages: wildcard catches a new package, explicit limit wins', () {
      final wildcard = Budget.parse('packages:\n  "*":\n    max-increase: 10KB');
      final v = evaluateBudget(wildcard, head, diff: diff);
      // dart:_http (+105 KB), dart:io, dart:async ... and http itself (+12.4 KB from 0)
      expect(v.map((x) => x.scope), containsAll(['library:dart:_http', 'library:package:http']));

      final explicit = Budget.parse('packages:\n  "*":\n    max-increase: 1MB\n  http:\n    max-size: 10KB');
      final e = evaluateBudget(explicit, head, diff: diff);
      expect(e.single.scope, 'library:package:http');
      expect(e.single.message, contains('`package:http` is 12.4 KB, over the 10.0 KB limit'));
    });
  });
}
