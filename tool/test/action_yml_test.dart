// Static checks on action.yml and the example workflows: they parse, every
// `inputs.x` / `steps.y.outputs.z` they reference exists, and every bash
// `run:` block is syntactically valid.
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final action = loadYaml(File('../action.yml').readAsStringSync()) as YamlMap;
  final inputs = (action['inputs'] as YamlMap).keys.cast<String>().toSet();
  final steps = ((action['runs'] as YamlMap)['steps'] as YamlList).cast<YamlMap>();
  final raw = File('../action.yml').readAsStringSync();

  test('is a composite action with the documented outputs', () {
    expect((action['runs'] as YamlMap)['using'], 'composite');
    expect((action['outputs'] as YamlMap).keys, containsAll(['status', 'total-size', 'diff-bytes']));
    expect(inputs, containsAll(['max-size', 'max-increase', 'allow-label', 'build-base', 'setup-flutter']));
  });

  test('every referenced input exists', () {
    final used = RegExp(r'inputs\.([a-z0-9-]+)').allMatches(raw).map((m) => m.group(1)!).toSet();
    expect(used.difference(inputs), isEmpty);
  });

  test('every referenced step output is produced', () {
    final ids = steps.map((s) => s['id']).whereType<String>().toSet();
    final refs = RegExp(r'steps\.([a-z0-9-]+)\.outputs\.([a-z0-9-]+)').allMatches(raw);
    for (final ref in refs) {
      expect(ids, contains(ref.group(1)), reason: ref.group(0));
    }
    // Outputs the prepare step writes.
    final prepare = steps.firstWhere((s) => s['id'] == 'prepare')['run'] as String;
    for (final ref in refs.where((r) => r.group(1) == 'prepare')) {
      expect(prepare, contains('echo "${ref.group(2)}='), reason: ref.group(0));
    }
    // Outputs the report step gets from the Dart tool.
    const reportOutputs = {
      'status',
      'total-size',
      'diff-bytes',
      'base-size',
      'baseline',
      'violations',
      'failure-message',
    };
    for (final ref in refs.where((r) => r.group(1) == 'report')) {
      expect(reportOutputs, contains(ref.group(2)), reason: ref.group(0));
    }
  });

  test('bash blocks parse', () async {
    for (final step in steps.where((s) => s['run'] != null)) {
      final script = (step['run'] as String).replaceAll(RegExp(r'\$\{\{[^}]*\}\}'), 'X');
      final r = await Process.run('bash', ['-n', '-c', script]);
      expect(r.exitCode, 0, reason: '${step['name']}: ${r.stderr}');
    }
    final build = await Process.run('bash', ['-n', '../scripts/build.sh']);
    expect(build.exitCode, 0, reason: '${build.stderr}');
  });

  test('example workflows parse and use the action', () {
    for (final file in Directory('../examples').listSync().whereType<File>()) {
      final doc = loadYaml(file.readAsStringSync());
      expect(doc, isA<YamlMap>(), reason: file.path);
      if (file.path.endsWith('size.yml')) {
        final text = file.readAsStringSync();
        expect(text, contains('youssef336/flutter-app-size-budget@v1'));
        expect(text, contains('pull-requests: write'));
      }
    }
    expect(loadYaml(File('../.github/workflows/test.yml').readAsStringSync()), isA<YamlMap>());
  });
}
