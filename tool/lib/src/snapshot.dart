/// Turns the JSON written by `flutter build <apk|appbundle|ios> --analyze-size`
/// into a small, stable [SizeSnapshot] that can be cached as a baseline.
///
/// The input format comes from flutter_tools `lib/src/base/analyze_size.dart`:
///
/// * Every node is `{"n": name, "value": bytes, "children": [...]}`; the root
///   is named `Root` and carries `"type"` (apk, aab, ios, macos, ...) and
///   `"precompiler-trace"`.
/// * For apk / aab the tree mirrors the zip entries and `value` is the
///   compressed size of each entry. For ios / macos it mirrors the `.app`
///   directory with on-disk sizes.
/// * The Dart snapshot file is renamed `libapp.so (Dart AOT)` (Android) or
///   `App (Dart AOT)` (Apple). Its `value` is its size in the archive, but its
///   `children` are replaced by the AOT treemap: decompressed symbol sizes
///   grouped by library (`package:flutter`, `dart:core`, `@stubs`, ...).
/// * The engine is renamed `libflutter.so (Flutter Engine)` on Android.
library;

import 'dart:convert';

/// Size buckets every snapshot is split into. Order is the display order.
const categoryOrder = <String>[
  'dart',
  'engine',
  'native',
  'assets',
  'dex',
  'resources',
  'other',
];

const categoryLabels = <String, String>{
  'dart': 'Dart code (AOT)',
  'engine': 'Flutter engine',
  'native': 'Other native libs',
  'assets': 'Assets',
  'dex': 'Java/Kotlin (dex)',
  'resources': 'Android/iOS resources',
  'other': 'Other',
};

const _dartAotSuffix = ' (Dart AOT)';
const _engineSuffix = ' (Flutter Engine)';

/// One measured build.
class SizeSnapshot {
  SizeSnapshot({
    required this.platform,
    required this.artifactName,
    required this.artifactBytes,
    required this.categories,
    required this.packages,
    required this.nativeLibs,
    this.sha,
    this.ref,
    this.createdAt,
  });

  factory SizeSnapshot.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema != schemaVersion) {
      throw FormatException('Unsupported snapshot schema $schema (expected $schemaVersion)');
    }
    return SizeSnapshot(
      platform: json['platform']! as String,
      artifactName: json['artifact']! as String,
      artifactBytes: json['artifactBytes']! as int,
      categories: _intMap(json['categories']),
      packages: _intMap(json['packages']),
      nativeLibs: _intMap(json['nativeLibs']),
      sha: json['sha'] as String?,
      ref: json['ref'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  static const schemaVersion = 1;

  /// apk, aab, ios, macos ...
  final String platform;

  /// File name of the measured artifact (app-release.apk, Runner.app ...).
  final String artifactName;

  /// Size of the artifact on disk: the .apk / .aab file, or the whole .app
  /// directory for Apple builds. This is the number budgets apply to.
  final int artifactBytes;

  /// Bytes per category (see [categoryOrder]). For zips these are compressed
  /// entry sizes, so they add up to roughly [artifactBytes].
  final Map<String, int> categories;

  /// Decompressed AOT size per Dart library root (`package:http`,
  /// `dart:core`, `@stubs` ...).
  final Map<String, int> packages;

  /// Native libraries (apk/aab `lib/**.so`, Apple frameworks) by file name.
  final Map<String, int> nativeLibs;

  final String? sha;
  final String? ref;
  final String? createdAt;

  int category(String name) => categories[name] ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schemaVersion,
        'tool': 'flutter-app-size-budget',
        'platform': platform,
        'artifact': artifactName,
        'artifactBytes': artifactBytes,
        if (sha != null) 'sha': sha,
        if (ref != null) 'ref': ref,
        if (createdAt != null) 'createdAt': createdAt,
        'categories': categories,
        'packages': packages,
        'nativeLibs': nativeLibs,
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static Map<String, int> _intMap(Object? raw) => <String, int>{
        for (final entry in (raw as Map<String, Object?>? ?? const {}).entries) entry.key: entry.value! as int,
      };
}

/// Builds a [SizeSnapshot] from a decoded `*-code-size-analysis_NN.json`.
SizeSnapshot snapshotFromAnalysis(
  Map<String, Object?> analysis, {
  required String artifactName,
  required int artifactBytes,
  String? sha,
  String? ref,
  String? createdAt,
}) {
  final type = analysis['type'] as String? ?? 'unknown';
  final categories = <String, int>{for (final c in categoryOrder) c: 0};
  final packages = <String, int>{};
  final nativeLibs = <String, int>{};

  void visit(Map<String, Object?> node, List<String> path) {
    final name = node['n'] as String? ?? '';
    final value = (node['value'] as num?)?.toInt() ?? 0;
    final here = [...path, name];

    if (name.endsWith(_dartAotSuffix)) {
      categories['dart'] = categories['dart']! + value;
      for (final child in _children(node)) {
        _addPackage(packages, child);
      }
      return;
    }
    final children = _children(node);
    if (children.isEmpty) {
      final category = _categorize(here, type);
      categories[category] = categories[category]! + value;
      if (category == 'native') {
        final key = _nativeName(here);
        nativeLibs[key] = (nativeLibs[key] ?? 0) + value;
      }
      return;
    }
    for (final child in children) {
      visit(child, here);
    }
  }

  // The root itself is named "Root" and is not part of any path.
  for (final child in _children(analysis)) {
    visit(child, const []);
  }

  return SizeSnapshot(
    platform: type,
    artifactName: artifactName,
    artifactBytes: artifactBytes,
    categories: categories,
    packages: packages,
    nativeLibs: nativeLibs,
    sha: sha,
    ref: ref,
    createdAt: createdAt,
  );
}

List<Map<String, Object?>> _children(Map<String, Object?> node) {
  final raw = node['children'];
  if (raw is! List) {
    return const [];
  }
  return [
    for (final child in raw)
      if (child is Map<String, Object?>) child,
  ];
}

/// Sums one AOT treemap child into its library root. Names look like
/// `package:flutter`, `package:flutter/src/...`, `dart:core`, `@stubs`.
void _addPackage(Map<String, int> packages, Map<String, Object?> node) {
  final size = _treeSize(node);
  if (size == 0) {
    return;
  }
  final key = packageKey(node['n'] as String? ?? '@unknown');
  packages[key] = (packages[key] ?? 0) + size;
}

/// Normalizes a treemap name to its library root.
///
/// Real names look like `package:flutter`, `package:http/package:http/src`,
/// `dart:core`, `@stubs`, `@shared`, `@unknown`, plus a long tail of VM object
/// kinds (`Code`, `ICData`, `ObjectPool`, ...) that are folded into `@vm`.
String packageKey(String name) {
  if (name.startsWith('package:') || name.startsWith('dart:')) {
    return name.split('/').first;
  }
  if (name.startsWith('@')) {
    return name;
  }
  return '@vm';
}

/// Size of an AOT treemap node. Leaves carry `value`; inner nodes sometimes do
/// not, so fall back to the sum of the children.
int _treeSize(Map<String, Object?> node) {
  final value = (node['value'] as num?)?.toInt();
  final children = _children(node);
  if (children.isEmpty) {
    return value ?? 0;
  }
  final sum = children.fold<int>(0, (total, child) => total + _treeSize(child));
  return value != null && value > sum ? value : sum;
}

String _categorize(List<String> path, String type) {
  final leaf = path.last;
  final lower = path.map((s) => s.toLowerCase()).toList();
  final leafLower = lower.last;

  if (leaf.endsWith(_engineSuffix) ||
      lower.any((s) => s == 'flutter.framework' || s == 'flutter.xcframework' || s == 'flutteremacos.framework')) {
    return 'engine';
  }
  if (lower.contains('flutter_assets')) {
    return 'assets';
  }
  if (lower.contains('app.framework')) {
    // Signature and Info.plist next to the Dart snapshot; not a native lib.
    return 'other';
  }
  if (leafLower.endsWith('.so') || leafLower.endsWith('.dylib')) {
    return 'native';
  }
  if (lower.any((s) => s.endsWith('.framework'))) {
    return 'native';
  }
  if (leafLower.endsWith('.dex')) {
    return 'dex';
  }
  final isZip = type == 'apk' || type == 'aab';
  if (isZip) {
    // apk: res/..., resources.arsc. aab: base/res/..., base/resources.pb.
    if (lower.contains('res') || leafLower == 'resources.arsc' || leafLower == 'resources.pb') {
      return 'resources';
    }
    if (lower.contains('assets')) {
      return 'assets';
    }
    return 'other';
  }
  // Apple bundles.
  if (leafLower == 'assets.car' ||
      lower.any((s) => s.endsWith('.lproj') || s.endsWith('.storyboardc') || s.endsWith('.nib')) ||
      leafLower.endsWith('.png')) {
    return 'resources';
  }
  return 'other';
}

String _nativeName(List<String> path) {
  for (final segment in path) {
    if (segment.toLowerCase().endsWith('.framework')) {
      return segment;
    }
  }
  return path.last;
}
