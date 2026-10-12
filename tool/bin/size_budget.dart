/// Command line entry point used by action.yml.
///
///   dart run size_budget snapshot --build-log build.log --out head.json
///   dart run size_budget report --head head.json [--base base.json] --markdown-out comment.md
///   dart run size_budget comment --repo owner/name --pr 12 --marker-id apk --body-file comment.md
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:size_budget/size_budget.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand('snapshot', _snapshotParser())
    ..addCommand('report', _reportParser())
    ..addCommand('comment', _commentParser());

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _die('${e.message}\n\nCommands: snapshot, report, comment\n${parser.usage}');
  }
  final command = args.command;
  try {
    switch (command?.name) {
      case 'snapshot':
        await _snapshot(command!);
      case 'report':
        await _report(command!);
      case 'comment':
        exitCode = await _comment(command!);
      default:
        _die('Usage: size_budget <snapshot|report|comment> [options]');
    }
  } on FormatException catch (e) {
    _die(e.message);
  } on FileSystemException catch (e) {
    _die('${e.message}: ${e.path}');
  }
}

ArgParser _snapshotParser() => ArgParser()
  ..addOption('build-log', help: 'Captured output of `flutter build ... --analyze-size`.')
  ..addOption('analysis', help: 'Path of the *-code-size-analysis_NN.json (overrides --build-log).')
  ..addOption('artifact', help: 'Path of the .apk / .aab / .app (overrides --build-log).')
  ..addOption('working-directory', defaultsTo: '.', help: 'Where `flutter build` ran.')
  ..addOption('sha')
  ..addOption('ref')
  ..addOption('out', mandatory: true);

ArgParser _reportParser() => ArgParser()
  ..addOption('head', mandatory: true)
  ..addOption('base')
  ..addOption('baseline-source', defaultsTo: 'missing', allowed: BaselineSource.values.map((s) => s.name))
  ..addOption('max-size', defaultsTo: '')
  ..addOption('max-increase', defaultsTo: '')
  ..addOption('budget-file', defaultsTo: '')
  ..addOption('labels', defaultsTo: '[]', help: 'JSON array of PR label names.')
  ..addOption('allow-label', defaultsTo: 'size-increase-approved')
  ..addOption('marker-id', defaultsTo: 'default')
  ..addOption('top', defaultsTo: '10', help: 'Dart packages listed in the details table.')
  ..addFlag('saved-baseline', negatable: false, help: 'This run is saving the baseline (push to the default branch).')
  ..addOption('markdown-out', mandatory: true)
  ..addOption('github-output', help: 'File to append step outputs to (defaults to \$GITHUB_OUTPUT).');

ArgParser _commentParser() => ArgParser()
  ..addOption('repo', mandatory: true)
  ..addOption('pr', mandatory: true)
  ..addOption('marker-id', defaultsTo: 'default')
  ..addOption('body-file', mandatory: true);

Future<void> _snapshot(ArgResults a) async {
  final workDir = a['working-directory'] as String;
  final logPath = a['build-log'] as String?;
  final log = logPath == null ? '' : File(logPath).readAsStringSync();

  final analysisPath = (a['analysis'] as String?) ?? findAnalysisPath(log);
  if (analysisPath == null) {
    _die('Could not find the analyze-size JSON in the build output. '
        'Was the build run with --analyze-size? Pass --analysis to point at it.');
  }
  var artifactPath = (a['artifact'] as String?) ?? findArtifactPath(log);
  if (artifactPath == null) {
    _die('Could not find the built artifact in the build output. Pass --artifact.');
  }
  if (!File(artifactPath).isAbsolute && !Directory(artifactPath).isAbsolute) {
    artifactPath = '$workDir/$artifactPath';
  }

  final analysis = jsonDecode(File(analysisPath).readAsStringSync()) as Map<String, Object?>;
  final snapshot = snapshotFromAnalysis(
    analysis,
    artifactName: artifactPath.split('/').where((s) => s.isNotEmpty).last,
    artifactBytes: artifactSize(artifactPath),
    sha: _blankToNull(a['sha'] as String?),
    ref: _blankToNull(a['ref'] as String?),
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
  File(a['out'] as String)
    ..createSync(recursive: true)
    ..writeAsStringSync(snapshot.encode());
  stdout.writeln('${snapshot.artifactName}: ${formatBytes(snapshot.artifactBytes)} '
      '(${snapshot.artifactBytes} bytes, ${snapshot.packages.length} Dart library roots)');
}

Future<void> _report(ArgResults a) async {
  SizeSnapshot read(String path) =>
      SizeSnapshot.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>);

  final head = read(a['head'] as String);
  final basePath = _blankToNull(a['base'] as String?);
  final base = basePath != null && File(basePath).existsSync() ? read(basePath) : null;
  var source = BaselineSource.parse(a['baseline-source'] as String);
  if (base == null) {
    source = BaselineSource.missing;
  }

  var budget = const Budget();
  final budgetFile = (a['budget-file'] as String).trim();
  if (budgetFile.isNotEmpty && File(budgetFile).existsSync()) {
    budget = Budget.parse(File(budgetFile).readAsStringSync());
  }
  budget = budget.withOverrides(
    maxSize: a['max-size'] as String,
    maxIncrease: a['max-increase'] as String,
  );

  final rawLabels = (a['labels'] as String).trim();
  final labels = rawLabels.isEmpty || rawLabels == 'null'
      ? <String>[]
      : (jsonDecode(rawLabels) as List<Object?>).whereType<String>().toList();

  final report = Report(
    head: head,
    base: base,
    baselineSource: source,
    budget: budget,
    labels: labels,
    allowLabel: (a['allow-label'] as String).trim(),
    markerId: a['marker-id'] as String,
    topPackages: int.parse(a['top'] as String),
    savedBaseline: a['saved-baseline'] as bool,
  );

  File(a['markdown-out'] as String)
    ..createSync(recursive: true)
    ..writeAsStringSync(renderMarkdown(report));

  final outputs = {...report.outputs, 'failure-message': report.failureMessage};
  final outPath = (a['github-output'] as String?) ?? Platform.environment['GITHUB_OUTPUT'];
  if (outPath != null && outPath.isNotEmpty) {
    File(outPath).writeAsStringSync(
      outputs.entries.map((e) => '${e.key}=${e.value.replaceAll('\n', ' ')}\n').join(),
      mode: FileMode.append,
    );
  }
  final diff = report.diffBytes;
  stdout.writeln('status=${report.status.name} total=${formatBytes(head.artifactBytes)}'
      '${diff == null ? ' (no baseline)' : ' diff=${formatDelta(diff)}'}');
  for (final v in report.violations) {
    stdout.writeln('  - ${v.message}');
  }
}

Future<int> _comment(ArgResults a) async {
  final marker = commentMarker(a['marker-id'] as String);
  final body = File(a['body-file'] as String).readAsStringSync();
  try {
    final action = await upsertStickyComment(
      repo: a['repo'] as String,
      pr: int.parse(a['pr'] as String),
      marker: marker,
      body: body,
    );
    stdout.writeln('PR comment ${action.name}.');
    return 0;
  } on GhException catch (e) {
    // Forks get a read-only token: not worth failing the size check over.
    stdout.writeln('::warning::Could not post the size comment: $e');
    return 0;
  }
}

String? _blankToNull(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

Never _die(String message) {
  stderr.writeln('size_budget: $message');
  exit(2);
}
