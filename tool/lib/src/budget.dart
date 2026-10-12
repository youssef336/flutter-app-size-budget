/// Size budgets: action inputs plus an optional `size-budget.yaml`.
///
/// ```yaml
/// max-size: 25MB          # whole artifact
/// max-increase: 2%        # whole artifact vs baseline (bytes or %)
/// categories:             # dart, engine, native, assets, dex, resources, other
///   assets:
///     max-size: 5MB
///   dart:
///     max-increase: 300KB
/// packages:               # Dart library roots, decompressed AOT size
///   "*":                  # any single package
///     max-increase: 100KB
///   package:my_app:
///     max-size: 3MB
/// ```
library;

import 'package:yaml/yaml.dart';

import 'diff.dart';
import 'snapshot.dart';
import 'units.dart';

class Limit {
  const Limit({this.maxSize, this.maxIncrease});

  final int? maxSize;
  final Threshold? maxIncrease;

  bool get isEmpty => maxSize == null && maxIncrease == null;

  static Limit fromYaml(Object? node, String where) {
    if (node == null) {
      return const Limit();
    }
    if (node is! Map) {
      throw FormatException('$where must be a map with max-size / max-increase');
    }
    for (final key in node.keys) {
      if (key != 'max-size' && key != 'max-increase') {
        throw FormatException('Unknown key "$key" in $where (use max-size, max-increase)');
      }
    }
    final size = node['max-size'];
    final increase = node['max-increase'];
    return Limit(
      maxSize: size == null ? null : parseBytes('$size'),
      maxIncrease: increase == null ? null : Threshold.parse('$increase'),
    );
  }
}

class Budget {
  const Budget({
    this.total = const Limit(),
    this.categories = const {},
    this.packages = const {},
  });

  /// Parses the YAML text of a `size-budget.yaml`.
  factory Budget.parse(String yamlText) {
    final doc = loadYaml(yamlText);
    if (doc == null) {
      return const Budget();
    }
    if (doc is! Map) {
      throw const FormatException('size-budget.yaml must be a map');
    }
    const allowed = {'max-size', 'max-increase', 'categories', 'packages'};
    for (final key in doc.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unknown key "$key" in size-budget.yaml (allowed: ${allowed.join(', ')})');
      }
    }
    final categories = <String, Limit>{};
    final rawCategories = doc['categories'];
    if (rawCategories is Map) {
      for (final entry in rawCategories.entries) {
        final name = '${entry.key}';
        if (!categoryOrder.contains(name)) {
          throw FormatException('Unknown category "$name" (use ${categoryOrder.join(', ')})');
        }
        categories[name] = Limit.fromYaml(entry.value, 'categories.$name');
      }
    }
    final packages = <String, Limit>{};
    final rawPackages = doc['packages'];
    if (rawPackages is Map) {
      for (final entry in rawPackages.entries) {
        final name = '${entry.key}';
        packages[name] = Limit.fromYaml(entry.value, 'packages.$name');
      }
    }
    return Budget(
      total: Limit(
        maxSize: doc['max-size'] == null ? null : parseBytes('${doc['max-size']}'),
        maxIncrease: doc['max-increase'] == null ? null : Threshold.parse('${doc['max-increase']}'),
      ),
      categories: categories,
      packages: packages,
    );
  }

  final Limit total;
  final Map<String, Limit> categories;

  /// Keyed by `package:name` (or `name`, normalized), or `*` for every package.
  final Map<String, Limit> packages;

  /// Returns a copy where non-empty action inputs override the file's
  /// top-level limits.
  Budget withOverrides({String? maxSize, String? maxIncrease}) {
    final size = (maxSize ?? '').trim();
    final increase = (maxIncrease ?? '').trim();
    return Budget(
      total: Limit(
        maxSize: size.isEmpty ? total.maxSize : parseBytes(size),
        maxIncrease: increase.isEmpty ? total.maxIncrease : Threshold.parse(increase),
      ),
      categories: categories,
      packages: packages,
    );
  }

  bool get isEmpty =>
      total.isEmpty && categories.values.every((l) => l.isEmpty) && packages.values.every((l) => l.isEmpty);
}

class Violation {
  const Violation(this.scope, this.message);

  /// `total`, `category:<name>` or `library:<package:name>`.
  final String scope;
  final String message;

  @override
  String toString() => message;
}

/// Checks [head] (and, when given, its [diff] against the baseline) against
/// [budget]. Increase limits are skipped when there is no baseline.
List<Violation> evaluateBudget(Budget budget, SizeSnapshot head, {SizeDiff? diff}) {
  final violations = <Violation>[];

  void check(String scope, String label, Limit limit, int headBytes, int? baseBytes) {
    final maxSize = limit.maxSize;
    if (maxSize != null && headBytes > maxSize) {
      violations.add(Violation(
        scope,
        '$label is ${formatBytes(headBytes)}, over the ${formatBytes(maxSize)} limit '
        'by ${formatBytes(headBytes - maxSize)}.',
      ));
    }
    final increase = limit.maxIncrease;
    if (increase != null && baseBytes != null) {
      final grew = headBytes - baseBytes;
      final allowed = increase.allowedIncrease(baseBytes);
      if (grew > allowed) {
        violations.add(Violation(
          scope,
          '$label grew by ${formatDelta(grew)} (${formatPercent(percentChange(baseBytes, headBytes))}), '
          'more than the allowed $increase.',
        ));
      }
    }
  }

  check('total', 'The ${head.platform} (${head.artifactName})', budget.total, head.artifactBytes, diff?.total.base);

  for (final entry in budget.categories.entries) {
    final baseBytes = diff?.categories.where((d) => d.name == entry.key).firstOrNull?.base;
    check('category:${entry.key}', categoryLabels[entry.key] ?? entry.key, entry.value, head.category(entry.key),
        baseBytes);
  }

  if (budget.packages.isNotEmpty) {
    final wildcard = budget.packages['*'];
    final explicit = <String, Limit>{
      for (final e in budget.packages.entries)
        if (e.key != '*') _normalizePackage(e.key): e.value,
    };
    final names = {...head.packages.keys, ...explicit.keys};
    for (final name in names.toList()..sort()) {
      final limit = explicit[name] ?? wildcard;
      if (limit == null) {
        continue;
      }
      final headBytes = head.packages[name] ?? 0;
      final baseDelta = diff?.packages.where((d) => d.name == name).firstOrNull;
      // A package that is new in this PR grew from 0.
      final baseBytes = diff == null ? null : (baseDelta?.base ?? 0);
      check('library:$name', '`$name`', limit, headBytes, baseBytes);
    }
  }
  return violations;
}

String _normalizePackage(String name) {
  if (name.startsWith('package:') || name.startsWith('dart:') || name.startsWith('@')) {
    return name;
  }
  return 'package:$name';
}
