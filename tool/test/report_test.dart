import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  Report report({
    Budget budget = const Budget(),
    bool withBase = true,
    List<String> labels = const [],
    BaselineSource source = BaselineSource.exact,
  }) =>
      Report(
        head: headSnapshot(),
        base: withBase ? baseSnapshot() : null,
        baselineSource: withBase ? source : BaselineSource.missing,
        budget: budget,
        labels: labels,
        allowLabel: 'size-increase-approved',
        markerId: 'apk',
      );

  group('status and outputs', () {
    test('pass', () {
      final r = report(budget: const Budget().withOverrides(maxIncrease: '500KB'));
      expect(r.status, Status.pass);
      expect(r.failureMessage, isEmpty);
      expect(r.outputs, {
        'status': 'pass',
        'total-size': '$headApkBytes',
        'diff-bytes': '323003',
        'base-size': '$baseApkBytes',
        'baseline': 'exact',
        'violations': '0',
      });
    });

    test('fail, then approved by label', () {
      final budget = const Budget().withOverrides(maxIncrease: '100KB');
      final failed = report(budget: budget, labels: ['other']);
      expect(failed.status, Status.fail);
      expect(failed.failureMessage, contains('App size budget exceeded'));
      expect(failed.failureMessage, contains('"size-increase-approved"'));

      final approved = report(budget: budget, labels: ['size-increase-approved']);
      expect(approved.status, Status.approved);
      expect(approved.violations, hasLength(1));
      expect(approved.failureMessage, isEmpty);
    });

    test('no baseline: empty diff output, only absolute checks', () {
      final r = report(withBase: false, budget: const Budget().withOverrides(maxSize: '15MB', maxIncrease: '1KB'));
      expect(r.outputs['diff-bytes'], '');
      expect(r.outputs['baseline'], 'missing');
      expect(r.violations.single.scope, 'total');
    });
  });

  group('markdown', () {
    test('diff comment', () {
      final md = renderMarkdown(report(budget: const Budget().withOverrides(maxSize: '25MB', maxIncrease: '2%')));
      expect(md, startsWith('<!-- flutter-app-size-budget:apk -->\n'));
      expect(md, contains('### ❌ App size · `app-release.apk` · over budget'));
      expect(md, contains('| **Total (apk)** | 14.77 MB | **15.08 MB** | **▲ +315.4 KB (+2.09%)** |'));
      expect(md, contains('| Dart code (AOT) | 3.06 MB | 3.31 MB | ▲ +256.0 KB (+8.16%) |'));
      expect(md, contains('| Flutter engine | 11.20 MB | 11.20 MB | 0 B |'));
      // Empty categories are left out.
      expect(md, isNot(contains('Other native libs')));
      expect(md, contains('- ▲ `dart:_http` +105.0 KB\n'));
      expect(md, contains('- ▲ Assets +59.3 KB\n'));
      expect(md, contains('**New Dart packages:** `http` (12.4 KB)'));
      expect(md, contains('| `http` | — | 12.4 KB | ▲ +12.4 KB (new) |'));
      expect(md, contains('**Budget exceeded**'));
      expect(md, contains('add the `size-increase-approved` label'));
      expect(md, contains('base `1111111` (cached) · head `2222222` · budget: max 25.00 MB, max +2%'));
    });

    test('approved and fallback baseline wording', () {
      final md = renderMarkdown(report(
        budget: const Budget().withOverrides(maxIncrease: '1KB'),
        labels: ['size-increase-approved'],
        source: BaselineSource.fallback,
      ));
      expect(md, contains('🟡 App size'));
      expect(md, contains('approved with `size-increase-approved`'));
      expect(md, contains('**Budget exceeded (approved)**'));
      expect(md, isNot(contains('add the `size-increase-approved` label')));
      expect(md, contains('latest cached baseline, not the exact merge base'));
    });

    test('pass without budget', () {
      final md = renderMarkdown(report());
      expect(md, contains('### ✅ App size · `app-release.apk` · no budget set'));
      expect(md, isNot(contains('Budget exceeded')));
    });

    test('no baseline', () {
      final md = renderMarkdown(report(withBase: false));
      expect(md, contains('| **Total (apk)** | **15.08 MB** |'));
      expect(md, contains('No baseline found'));
      expect(md, contains('no baseline · head `2222222`'));
    });

    test('baseline run', () {
      final r = Report(
        head: headSnapshot(),
        base: null,
        baselineSource: BaselineSource.missing,
        budget: const Budget().withOverrides(maxSize: '25MB'),
        labels: const [],
        allowLabel: '',
        markerId: 'apk',
        savedBaseline: true,
      );
      final md = renderMarkdown(r);
      expect(md, contains('Saved as the baseline for `2222222`'));
      expect(md, contains('baseline run · head `2222222`'));
      expect(r.status, Status.pass);
    });

    test('a shrinking PR shows ▼', () {
      final r = Report(
        head: baseSnapshot(),
        base: headSnapshot(),
        baselineSource: BaselineSource.built,
        budget: const Budget(),
        labels: const [],
        allowLabel: '',
        markerId: 'apk',
      );
      final md = renderMarkdown(r);
      expect(md, contains('**▼ -315.4 KB (-2.04%)**'));
      expect(md, contains('**Removed Dart packages:**'));
      expect(md, contains('(built in this run)'));
    });
  });
}
