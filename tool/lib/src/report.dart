/// Builds the result of a run (status + outputs) and renders it as Markdown
/// for the sticky PR comment and the job summary.
library;

import 'budget.dart';
import 'diff.dart';
import 'snapshot.dart';
import 'units.dart';

/// Where the baseline numbers came from.
enum BaselineSource {
  /// Cache entry for the exact base commit.
  exact,

  /// Most recent cached baseline of the base branch (not the exact commit).
  fallback,

  /// The action built the base commit itself (`build-base: true`).
  built,

  /// No baseline: only absolute limits are checked.
  missing;

  static BaselineSource parse(String value) => BaselineSource.values.firstWhere(
        (s) => s.name == value,
        orElse: () => throw FormatException('Unknown baseline source "$value"'),
      );
}

enum Status { pass, fail, approved }

class Report {
  Report({
    required this.head,
    required this.base,
    required this.baselineSource,
    required this.budget,
    required this.labels,
    required this.allowLabel,
    required this.markerId,
    this.topPackages = 10,
    this.savedBaseline = false,
  }) : diff = base == null ? null : SizeDiff.compare(base, head) {
    violations = evaluateBudget(budget, head, diff: diff);
    final hasLabel = allowLabel.isNotEmpty && labels.contains(allowLabel);
    status = violations.isEmpty
        ? Status.pass
        : hasLabel
            ? Status.approved
            : Status.fail;
  }

  final SizeSnapshot head;
  final SizeSnapshot? base;
  final SizeDiff? diff;
  final BaselineSource baselineSource;
  final Budget budget;
  final List<String> labels;
  final String allowLabel;
  final String markerId;
  final int topPackages;

  /// True on a push to the default branch: this run's numbers were saved as
  /// the baseline that pull requests compare against.
  final bool savedBaseline;

  late final List<Violation> violations;
  late final Status status;

  int? get diffBytes => diff?.total.delta;

  /// One line for the job log / `::error::` annotation.
  String get failureMessage {
    if (status != Status.fail) {
      return '';
    }
    final reasons = violations.map((v) => v.message).join(' ');
    final override = allowLabel.isEmpty ? '' : ' Add the "$allowLabel" label to accept it.';
    return 'App size budget exceeded: $reasons$override';
  }

  Map<String, String> get outputs => {
        'status': status.name,
        'total-size': '${head.artifactBytes}',
        'diff-bytes': diffBytes == null ? '' : '$diffBytes',
        'base-size': base == null ? '' : '${base!.artifactBytes}',
        'baseline': baselineSource.name,
        'violations': '${violations.length}',
      };
}

/// Hidden marker that identifies our sticky comment. [id] lets several jobs
/// (apk + ios, flavors) keep separate comments on the same PR.
String commentMarker(String id) => '<!-- flutter-app-size-budget:$id -->';

String renderMarkdown(Report r) {
  final b = StringBuffer()..writeln(commentMarker(r.markerId));
  final head = r.head;
  final diff = r.diff;

  final icon = switch (r.status) {
    Status.pass => '✅',
    Status.approved => '🟡',
    Status.fail => '❌',
  };
  final verdict = switch (r.status) {
    Status.pass => r.budget.isEmpty ? 'no budget set' : 'within budget',
    Status.approved => 'over budget, approved with `${r.allowLabel}`',
    Status.fail => 'over budget',
  };
  b.writeln('### $icon App size · `${head.artifactName}` · $verdict');
  b.writeln();

  if (diff == null) {
    b.writeln('| | Size |');
    b.writeln('|---|---:|');
    b.writeln('| **Total (${head.platform})** | **${formatBytes(head.artifactBytes)}** |');
    for (final name in categoryOrder) {
      final v = head.category(name);
      if (v > 0) {
        b.writeln('| ${categoryLabels[name]} | ${formatBytes(v)} |');
      }
    }
    b.writeln();
    b.writeln(r.savedBaseline
        ? '> ✅ Saved as the baseline for `${_shortSha(head.sha)}`. Pull requests into this branch compare against it.'
        : '> ℹ️ No baseline found for the base branch, so there is nothing to compare against yet. '
            'Run this action on a push to the base branch (or set `build-base: true`) to get a diff.');
    b.writeln();
  } else {
    b.writeln('| | Base | PR | Change |');
    b.writeln('|---|---:|---:|---:|');
    b.writeln('| **Total (${head.platform})** | ${formatBytes(diff.total.base!)} | '
        '**${formatBytes(diff.total.head!)}** | **${_change(diff.total)}** |');
    for (final d in diff.categories) {
      if ((d.base ?? 0) == 0 && (d.head ?? 0) == 0) {
        continue;
      }
      b.writeln('| ${categoryLabels[d.name] ?? d.name} | ${formatBytes(d.base ?? 0)} | '
          '${formatBytes(d.head ?? 0)} | ${_change(d)} |');
    }
    b.writeln();

    final movers = diff.biggestMovers();
    if (movers.isNotEmpty) {
      b.writeln('**Biggest changes**');
      b.writeln();
      for (final m in movers) {
        b.writeln('- ${_arrow(m.delta.delta)} ${_moverName(m)} ${formatDelta(m.delta.delta)}'
            '${_moverNote(m.delta)}');
      }
      b.writeln();
    }

    final added = diff.addedPackages;
    final removed = diff.removedPackages;
    if (added.isNotEmpty) {
      b.writeln('**New Dart packages:** ${added.map((d) => '`${_pkg(d.name)}` (${formatBytes(d.head!)})').join(', ')}');
      b.writeln();
    }
    if (removed.isNotEmpty) {
      b.writeln(
          '**Removed Dart packages:** ${removed.map((d) => '`${_pkg(d.name)}` (${formatBytes(d.base!)})').join(', ')}');
      b.writeln();
    }

    final changed = diff.packages.where((d) => d.delta != 0).take(r.topPackages).toList();
    if (changed.isNotEmpty) {
      b.writeln(
          '<details><summary>Dart packages that changed (top ${changed.length}, decompressed AOT size)</summary>');
      b.writeln();
      b.writeln('| Package | Base | PR | Change |');
      b.writeln('|---|---:|---:|---:|');
      for (final d in changed) {
        b.writeln('| `${_pkg(d.name)}` | ${d.base == null ? '—' : formatBytes(d.base!)} | '
            '${d.head == null ? '—' : formatBytes(d.head!)} | ${_change(d)} |');
      }
      b.writeln();
      b.writeln('</details>');
      b.writeln();
    }
  }

  if (r.violations.isNotEmpty) {
    b.writeln(r.status == Status.fail ? '**Budget exceeded**' : '**Budget exceeded (approved)**');
    b.writeln();
    for (final v in r.violations) {
      b.writeln('- ${v.message}');
    }
    if (r.status == Status.fail && r.allowLabel.isNotEmpty) {
      b.writeln();
      b.writeln('If the increase is intended, add the `${r.allowLabel}` label to this PR.');
    }
    b.writeln();
  }

  final budgetLine = _budgetLine(r.budget);
  final baseLine = switch (r.baselineSource) {
    BaselineSource.exact => 'base `${_shortSha(r.base?.sha)}` (cached)',
    BaselineSource.fallback => 'base `${_shortSha(r.base?.sha)}` (latest cached baseline, not the exact merge base)',
    BaselineSource.built => 'base `${_shortSha(r.base?.sha)}` (built in this run)',
    BaselineSource.missing => r.savedBaseline ? 'baseline run' : 'no baseline',
  };
  b.writeln('<sub>$baseLine · head `${_shortSha(head.sha)}`'
      '${budgetLine.isEmpty ? '' : ' · budget: $budgetLine'}'
      ' · categories are compressed sizes inside the artifact; Dart packages are decompressed AOT sizes'
      ' · <a href="https://github.com/youssef336/flutter-app-size-budget">flutter-app-size-budget</a></sub>');
  return b.toString();
}

String _change(Delta d) {
  final delta = d.delta;
  if (delta == 0) {
    return '0 B';
  }
  final pct = d.base == null || d.base == 0 ? 'new' : formatPercent(d.percent);
  return '${_arrow(delta)} ${formatDelta(delta)} ($pct)';
}

String _arrow(int delta) => delta > 0 ? '▲' : (delta < 0 ? '▼' : '•');

String _moverName(Mover m) => switch (m.kind) {
      'package' => '`${_pkg(m.delta.name)}`',
      'native' => '`${m.delta.name}`',
      _ => categoryLabels[m.delta.name] ?? m.delta.name,
    };

String _moverNote(Delta d) {
  if (d.isNew) {
    return ' (new)';
  }
  if (d.isRemoved) {
    return ' (removed)';
  }
  return '';
}

String _pkg(String name) => name.startsWith('package:') ? name.substring('package:'.length) : name;

String _shortSha(String? sha) => sha == null || sha.isEmpty ? '?' : (sha.length > 7 ? sha.substring(0, 7) : sha);

String _budgetLine(Budget budget) {
  final parts = <String>[
    if (budget.total.maxSize != null) 'max ${formatBytes(budget.total.maxSize!)}',
    if (budget.total.maxIncrease != null) 'max +${budget.total.maxIncrease}',
    if (budget.categories.values.any((l) => !l.isEmpty) || budget.packages.values.any((l) => !l.isEmpty))
      'per-category/package limits from file',
  ];
  return parts.join(', ');
}
