import 'dart:convert';

import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('snapshotFromAnalysis (real apk analysis)', () {
    final base = baseSnapshot();
    final head = headSnapshot();

    test('reads the type and the artifact size', () {
      expect(base.platform, 'apk');
      expect(base.artifactBytes, baseApkBytes);
    });

    test('splits the zip entries into categories', () {
      // Values straight from the analysis tree: "libapp.so (Dart AOT)" and
      // "libflutter.so (Flutter Engine)" under lib/arm64-v8a, classes.dex,
      // assets/, res/ + resources.arsc.
      expect(base.categories, {
        'dart': 3212168,
        'engine': 11747864,
        'native': 0,
        'assets': 222267,
        'dex': 238028,
        'resources': 11101,
        'other': 15691,
      });
      // The compressed entries add up to the apk minus zip headers.
      final sum = base.categories.values.fold<int>(0, (a, b) => a + b);
      expect(sum, lessThan(base.artifactBytes));
      expect(base.artifactBytes - sum, lessThan(64 * 1024));
    });

    test('groups the AOT treemap by library root', () {
      expect(base.packages.keys, containsAll(['package:flutter', 'dart:core', '@stubs', '@vm']));
      // "package:vector_math/package:vector_math/vector_math_64.dart" -> package:vector_math
      expect(base.packages.keys, contains('package:vector_math'));
      expect(base.packages.keys.where((k) => k.contains('/')), isEmpty);
      expect(base.packages, isNot(contains('package:http')));
      expect(head.packages['package:http'], 12723);
      expect(head.packages['package:flutter'], greaterThan(1000000));
    });

    test('round-trips through JSON', () {
      final decoded = SizeSnapshot.fromJson(jsonDecode(head.encode()) as Map<String, Object?>);
      expect(decoded.categories, head.categories);
      expect(decoded.packages, head.packages);
      expect(decoded.sha, head.sha);
      expect(decoded.artifactBytes, headApkBytes);
    });

    test('rejects an unknown schema', () {
      expect(
        () => SizeSnapshot.fromJson({'schema': 99}),
        throwsFormatException,
      );
    });
  });

  group('categories for other layouts', () {
    Map<String, Object?> node(String n, int value, [List<Map<String, Object?>>? children]) => {
          'n': n,
          'value': value,
          if (children != null) 'children': children,
        };

    test('aab: base/ prefix, resources.pb, extra native libs', () {
      final analysis = node('Root', 0, [
        node('base', 0, [
          node('lib', 0, [
            node('arm64-v8a', 0, [
              node('libapp.so (Dart AOT)', 500, [
                node('package:foo', 0, [node('A', 300)])
              ]),
              node('libflutter.so (Flutter Engine)', 1000),
              node('libsqlite3.so', 200),
            ]),
          ]),
          node('dex', 0, [node('classes.dex', 50), node('classes2.dex', 20)]),
          node('res', 0, [node('a.png', 5)]),
          node('resources.pb', 7),
          node('assets', 0, [
            node('flutter_assets', 0, [node('img.png', 40)])
          ]),
        ]),
        node('BUNDLE-METADATA', 0, [node('x', 3)]),
      ])
        ..['type'] = 'aab';
      final s = snapshotFromAnalysis(analysis, artifactName: 'app.aab', artifactBytes: 2000);
      expect(s.categories, {
        'dart': 500,
        'engine': 1000,
        'native': 200,
        'assets': 40,
        'dex': 70,
        'resources': 12,
        'other': 3,
      });
      expect(s.nativeLibs, {'libsqlite3.so': 200});
      expect(s.packages, {'package:foo': 300});
    });

    test('ios: frameworks, Assets.car, App (Dart AOT)', () {
      final analysis = node('Root', 0, [
        node('Runner.app', 0, [
          node('Frameworks', 0, [
            node('App.framework', 0, [
              node('App (Dart AOT)', 900, [
                node('dart:core', 0, [node('X', 100)])
              ]),
              node('flutter_assets', 0, [node('NOTICES.Z', 30)]),
            ]),
            node('Flutter.framework', 0, [node('Flutter', 2000)]),
            node('FirebaseCore.framework', 0, [node('FirebaseCore', 150), node('Info.plist', 1)]),
          ]),
          node('Assets.car', 60),
          node('Runner', 80),
        ]),
      ])
        ..['type'] = 'ios';
      final s = snapshotFromAnalysis(analysis, artifactName: 'Runner.app', artifactBytes: 3300);
      expect(s.category('dart'), 900);
      expect(s.category('engine'), 2000);
      expect(s.category('native'), 151);
      expect(s.category('assets'), 30);
      expect(s.category('resources'), 60);
      expect(s.category('other'), 80);
      expect(s.nativeLibs, {'FirebaseCore.framework': 151});
    });
  });

  test('real ios analysis (flutter build ios --analyze-size --no-codesign)', () {
    final s = snapshotFromAnalysis(
      loadAnalysis('ios_analysis.json'),
      artifactName: 'Runner.app',
      artifactBytes: 14802489,
    );
    expect(s.platform, 'ios');
    expect(s.category('dart'), 3798016); // App.framework/App (Dart AOT)
    expect(s.category('engine'), 10400039); // Flutter.framework
    expect(s.category('assets'), 427571); // App.framework/flutter_assets
    expect(s.category('native'), 0); // no third-party frameworks in the template
    expect(s.categories.values.fold<int>(0, (a, b) => a + b), 14802489);
    expect(s.packages.keys, containsAll(['package:flutter', 'package:http', 'dart:ui']));
  });

  test('packageKey', () {
    expect(packageKey('package:http/package:http/src'), 'package:http');
    expect(packageKey('package:flutter'), 'package:flutter');
    expect(packageKey('dart:core'), 'dart:core');
    expect(packageKey('@stubs'), '@stubs');
    expect(packageKey('ObjectPool'), '@vm');
  });
}
