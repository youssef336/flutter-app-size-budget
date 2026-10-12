// Real fixtures produced by Flutter 3.47.6 on a fresh `flutter create` app:
//
//   flutter build apk --release --analyze-size --target-platform android-arm64
//
// base: the template app. head: the same app + `package:http` (used from
// main.dart) + a 60,000-byte asset. The analysis JSONs were shrunk with
// fixtures/trim_fixture.dart (same shape and totals). The two APK sizes below
// are the real `app-release.apk` file sizes of those builds.
import 'dart:convert';
import 'dart:io';

import 'package:size_budget/size_budget.dart';

const baseApkBytes = 15487478;
const headApkBytes = 15810481;

Map<String, Object?> loadAnalysis(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, Object?>;

SizeSnapshot baseSnapshot() => snapshotFromAnalysis(
      loadAnalysis('apk_base_analysis.json'),
      artifactName: 'app-release.apk',
      artifactBytes: baseApkBytes,
      sha: '1111111aaaaaaa',
    );

SizeSnapshot headSnapshot() => snapshotFromAnalysis(
      loadAnalysis('apk_head_analysis.json'),
      artifactName: 'app-release.apk',
      artifactBytes: headApkBytes,
      sha: '2222222bbbbbbb',
    );
