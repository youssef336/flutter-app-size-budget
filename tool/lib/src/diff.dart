/// Base vs head comparison of two [SizeSnapshot]s.
library;

import 'snapshot.dart';
import 'units.dart';

/// One compared value. [base] or [head] is null when the entry only exists
/// on one side (a new or removed package).
class Delta {
  const Delta(this.name, {required this.base, required this.head});

  final String name;
  final int? base;
  final int? head;

  int get delta => (head ?? 0) - (base ?? 0);
  bool get isNew => base == null && head != null;
  bool get isRemoved => head == null && base != null;
  double? get percent => base == null ? null : percentChange(base!, head ?? 0);
}

/// A row in the "biggest changes" list.
class Mover {
  const Mover(this.kind, this.delta);

  /// `category`, `package` or `native`.
  final String kind;
  final Delta delta;
}

class SizeDiff {
  SizeDiff._({
    required this.total,
    required this.categories,
    required this.packages,
    required this.nativeLibs,
  });

  /// Compares [head] against [base].
  factory SizeDiff.compare(SizeSnapshot base, SizeSnapshot head) {
    return SizeDiff._(
      total: Delta('total', base: base.artifactBytes, head: head.artifactBytes),
      categories: [
        for (final name in _orderedCategories(base, head))
          Delta(name, base: base.categories[name] ?? 0, head: head.categories[name] ?? 0),
      ],
      packages: _compareMaps(base.packages, head.packages),
      nativeLibs: _compareMaps(base.nativeLibs, head.nativeLibs),
    );
  }

  final Delta total;
  final List<Delta> categories;

  /// Every Dart library root on either side, biggest absolute change first.
  final List<Delta> packages;

  /// Every native lib on either side, biggest absolute change first.
  final List<Delta> nativeLibs;

  List<Delta> get addedPackages => packages.where((d) => d.isNew).toList();
  List<Delta> get removedPackages => packages.where((d) => d.isRemoved).toList();

  /// The [limit] largest absolute changes across packages, native libs and
  /// the non-Dart categories, ignoring anything smaller than [minBytes].
  ///
  /// The `dart` and `native` categories are skipped because their contents are
  /// already listed per package / per lib; listing both would double count.
  List<Mover> biggestMovers({int limit = 5, int minBytes = 1024}) {
    final all = <Mover>[
      for (final d in packages) Mover('package', d),
      for (final d in nativeLibs) Mover('native', d),
      for (final d in categories)
        if (d.name != 'dart' && d.name != 'native') Mover('category', d),
    ]..removeWhere((m) => m.delta.delta.abs() < minBytes);
    all.sort((a, b) => b.delta.delta.abs().compareTo(a.delta.delta.abs()));
    return all.take(limit).toList();
  }

  static Iterable<String> _orderedCategories(SizeSnapshot base, SizeSnapshot head) {
    final extra = {...base.categories.keys, ...head.categories.keys}..removeAll(categoryOrder);
    return [...categoryOrder, ...extra.toList()..sort()];
  }

  static List<Delta> _compareMaps(Map<String, int> base, Map<String, int> head) {
    final names = {...base.keys, ...head.keys};
    final list = [for (final n in names) Delta(n, base: base[n], head: head[n])];
    list.sort((a, b) {
      final byDelta = b.delta.abs().compareTo(a.delta.abs());
      if (byDelta != 0) {
        return byDelta;
      }
      return a.name.compareTo(b.name);
    });
    return list;
  }
}
