import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final diff = SizeDiff.compare(baseSnapshot(), headSnapshot());

  test('total is the artifact file size difference', () {
    expect(diff.total.base, baseApkBytes);
    expect(diff.total.head, headApkBytes);
    expect(diff.total.delta, headApkBytes - baseApkBytes); // 323003
    expect(diff.total.percent, closeTo(2.086, 0.001));
  });

  test('per category', () {
    Delta cat(String name) => diff.categories.firstWhere((d) => d.name == name);
    expect(diff.categories.map((d) => d.name), categoryOrder);
    expect(cat('dart').delta, 3474312 - 3212168);
    // The 60,000-byte blob is stored compressed-ish in the apk plus manifest bytes.
    expect(cat('assets').delta, 282977 - 222267);
    expect(cat('engine').delta, 0);
    expect(cat('dex').delta, 0);
  });

  test('new and removed packages', () {
    expect(diff.addedPackages.map((d) => d.name), ['package:http']);
    expect(diff.addedPackages.single.isNew, isTrue);
    expect(diff.addedPackages.single.percent, isNull);
    expect(diff.removedPackages, isEmpty);
  });

  test('packages are sorted by absolute change', () {
    // http pulls in dart:_http and grows dart:io; those dwarf http itself.
    expect(diff.packages.first.name, 'dart:_http');
    expect(diff.packages.first.delta, 107505);
    expect(diff.packages[1].name, 'dart:io');
    final deltas = diff.packages.map((d) => d.delta.abs()).toList();
    expect(deltas, orderedEquals(<int>[...deltas]..sort((a, b) => b.compareTo(a))));
  });

  test('biggest movers skip the dart/native categories and tiny changes', () {
    final movers = diff.biggestMovers(limit: 4);
    expect(movers.map((m) => m.delta.name), ['dart:_http', 'dart:io', 'assets', '@unknown']);
    expect(movers[2].kind, 'category');
    expect(movers.every((m) => m.delta.name != 'dart'), isTrue);
    expect(diff.biggestMovers(minBytes: 1 << 30), isEmpty);
  });

  test('removed package shows up on the other side', () {
    final reverse = SizeDiff.compare(headSnapshot(), baseSnapshot());
    expect(reverse.removedPackages.map((d) => d.name), ['package:http']);
    expect(reverse.total.delta, -(headApkBytes - baseApkBytes));
  });
}
