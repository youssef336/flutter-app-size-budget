// Runs bin/size_budget.dart the way action.yml does, on the real fixtures.
import 'dart:io';

import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('size_budget_cli'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> cli(List<String> args) =>
      Process.run(Platform.resolvedExecutable, ['run', 'bin/size_budget.dart', ...args]);

  File fakeApk(String name, int bytes) => File('${tmp.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));

  test('build output parsing on a real log', () {
    final log = File('test/fixtures/apk_build.log').readAsStringSync();
    expect(findAnalysisPath(log), '/home/runner/.flutter-devtools/apk-code-size-analysis_02.json');
    expect(findArtifactPath(log), 'build/app/outputs/flutter-apk/app-release.apk');
    expect(findArtifactPath('✓ Built build/ios/iphoneos/Runner.app (14.8MB)'), 'build/ios/iphoneos/Runner.app');
    expect(findArtifactPath('✓ Built build/app/outputs/bundle/prodRelease/app-prod-release.aab (20.1MB).'),
        'build/app/outputs/bundle/prodRelease/app-prod-release.aab');
    expect(findAnalysisPath('nothing here'), isNull);
  });

  test('snapshot -> report -> outputs, end to end', () async {
    final baseApk = fakeApk('base.apk', baseApkBytes);
    final headApk = fakeApk('head.apk', headApkBytes);
    for (final (name, apk, analysis) in [
      ('base', baseApk, 'apk_base_analysis.json'),
      ('head', headApk, 'apk_head_analysis.json'),
    ]) {
      final r = await cli([
        'snapshot',
        '--analysis',
        'test/fixtures/$analysis',
        '--artifact',
        apk.path,
        '--sha',
        '${name}0000000',
        '--out',
        '${tmp.path}/$name.json',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }

    File('${tmp.path}/size-budget.yaml').writeAsStringSync('categories:\n  assets:\n    max-increase: 10KB\n');
    final outputs = File('${tmp.path}/out.txt');
    final r = await cli([
      'report',
      '--head',
      '${tmp.path}/head.json',
      '--base',
      '${tmp.path}/base.json',
      '--baseline-source',
      'exact',
      '--max-size',
      '25MB',
      '--budget-file',
      '${tmp.path}/size-budget.yaml',
      '--labels',
      '["bug"]',
      '--marker-id',
      'apk',
      '--markdown-out',
      '${tmp.path}/comment.md',
      '--github-output',
      outputs.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('status=fail'));
    final out = outputs.readAsStringSync();
    expect(out, contains('status=fail\n'));
    expect(out, contains('total-size=$headApkBytes\n'));
    expect(out, contains('diff-bytes=323003\n'));
    expect(out, contains('failure-message=App size budget exceeded: Assets grew by'));
    expect(File('${tmp.path}/comment.md').readAsStringSync(), contains('<!-- flutter-app-size-budget:apk -->'));
  });

  test('missing base file degrades to no baseline', () async {
    final apk = fakeApk('head.apk', headApkBytes);
    await cli([
      'snapshot',
      '--analysis',
      'test/fixtures/apk_head_analysis.json',
      '--artifact',
      apk.path,
      '--out',
      '${tmp.path}/head.json',
    ]);
    final outputs = File('${tmp.path}/out.txt');
    final r = await cli([
      'report',
      '--head',
      '${tmp.path}/head.json',
      '--base',
      '${tmp.path}/does-not-exist.json',
      '--baseline-source',
      'exact',
      '--labels',
      'null',
      '--markdown-out',
      '${tmp.path}/comment.md',
      '--github-output',
      outputs.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(outputs.readAsStringSync(), contains('baseline=missing\n'));
    expect(outputs.readAsStringSync(), contains('diff-bytes=\n'));
  });

  test('bad budget input is a clear error', () async {
    final apk = fakeApk('head.apk', 10);
    await cli([
      'snapshot',
      '--analysis',
      'test/fixtures/apk_head_analysis.json',
      '--artifact',
      apk.path,
      '--out',
      '${tmp.path}/head.json',
    ]);
    final r = await cli([
      'report',
      '--head',
      '${tmp.path}/head.json',
      '--max-size',
      '25 parsecs',
      '--markdown-out',
      '${tmp.path}/c.md',
      '--github-output',
      '${tmp.path}/o.txt',
    ]);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('Unknown size unit "parsecs"'));
  });
}
