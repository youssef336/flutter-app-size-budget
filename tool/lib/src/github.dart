/// Sticky PR comment through the `gh` CLI (preinstalled on GitHub runners,
/// authenticated with `GH_TOKEN`).
library;

import 'dart:convert';
import 'dart:io';

/// Runs `gh` with [args]; [stdinText] is piped to stdin when given.
typedef GhRunner = Future<GhResult> Function(List<String> args, {String? stdinText});

class GhResult {
  const GhResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<GhResult> runGh(List<String> args, {String? stdinText}) async {
  final process = await Process.start('gh', args);
  if (stdinText != null) {
    process.stdin.write(stdinText);
  }
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  return GhResult(code, await out, await err);
}

enum CommentAction { created, updated }

/// Creates the comment, or updates the first existing comment on the PR whose
/// body contains [marker].
Future<CommentAction> upsertStickyComment({
  required String repo,
  required int pr,
  required String marker,
  required String body,
  GhRunner gh = runGh,
}) async {
  final list = await gh([
    'api',
    '--paginate',
    'repos/$repo/issues/$pr/comments?per_page=100',
    '--jq',
    '.[] | {id: .id, body: .body} | @json',
  ]);
  if (list.exitCode != 0) {
    throw GhException('Could not list PR comments', list);
  }
  final existingId = findMarkedCommentId(list.stdout, marker);
  final payload = jsonEncode({'body': body});
  if (existingId != null) {
    final res = await gh([
      'api',
      '--method',
      'PATCH',
      'repos/$repo/issues/comments/$existingId',
      '--input',
      '-',
    ], stdinText: payload);
    if (res.exitCode != 0) {
      throw GhException('Could not update comment $existingId', res);
    }
    return CommentAction.updated;
  }
  final res = await gh([
    'api',
    '--method',
    'POST',
    'repos/$repo/issues/$pr/comments',
    '--input',
    '-',
  ], stdinText: payload);
  if (res.exitCode != 0) {
    throw GhException('Could not create comment', res);
  }
  return CommentAction.created;
}

/// [jsonLines] is one `{"id":..,"body":..}` object per line (the `--jq` output
/// above, across all pages). Returns the first id whose body has [marker].
int? findMarkedCommentId(String jsonLines, String marker) {
  for (final line in const LineSplitter().convert(jsonLines)) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line) as Map<String, Object?>;
    final body = decoded['body'] as String? ?? '';
    if (body.contains(marker)) {
      return (decoded['id']! as num).toInt();
    }
  }
  return null;
}

class GhException implements Exception {
  GhException(this.message, this.result);

  final String message;
  final GhResult result;

  @override
  String toString() => '$message (gh exit ${result.exitCode}): ${result.stderr.trim()}';
}
