import 'dart:convert';

import 'package:size_budget/size_budget.dart';
import 'package:test/test.dart';

/// Records every `gh` call and answers from a script.
class FakeGh {
  FakeGh(this.listOutput, {this.failOn});

  final String listOutput;
  final String? failOn;
  final calls = <List<String>>[];
  final stdins = <String?>[];

  Future<GhResult> call(List<String> args, {String? stdinText}) async {
    calls.add(args);
    stdins.add(stdinText);
    if (failOn != null && args.contains(failOn)) {
      return const GhResult(1, '', 'HTTP 403: Resource not accessible by integration');
    }
    if (args.contains('--paginate')) {
      return GhResult(0, listOutput, '');
    }
    return const GhResult(0, '{}', '');
  }
}

String line(int id, String body) => jsonEncode({'id': id, 'body': body});

void main() {
  final marker = commentMarker('apk');

  test('creates a comment when none carries the marker', () async {
    final gh = FakeGh([line(1, 'LGTM'), line(2, '<!-- flutter-app-size-budget:ios -->\nold')].join('\n'));
    final action = await upsertStickyComment(
      repo: 'me/app',
      pr: 7,
      marker: marker,
      body: '$marker\nhello',
      gh: gh.call,
    );
    expect(action, CommentAction.created);
    expect(gh.calls, hasLength(2));
    expect(gh.calls[0], containsAllInOrder(['api', '--paginate', 'repos/me/app/issues/7/comments?per_page=100']));
    expect(gh.calls[1], ['api', '--method', 'POST', 'repos/me/app/issues/7/comments', '--input', '-']);
    expect(jsonDecode(gh.stdins[1]!), {'body': '$marker\nhello'});
  });

  test('updates the marked comment, even on a later page', () async {
    // --paginate concatenates pages; each comment is one JSON line.
    final pages = [
      for (var i = 1; i <= 100; i++) line(i, 'comment $i'),
      line(4242, 'header\n$marker\nprevious report'),
      line(4243, '$marker duplicate'),
    ].join('\n');
    final gh = FakeGh('$pages\n');
    final action = await upsertStickyComment(
      repo: 'me/app',
      pr: 7,
      marker: marker,
      body: 'new body',
      gh: gh.call,
    );
    expect(action, CommentAction.updated);
    expect(gh.calls[1], ['api', '--method', 'PATCH', 'repos/me/app/issues/comments/4242', '--input', '-']);
    expect(jsonDecode(gh.stdins[1]!), {'body': 'new body'});
  });

  test('bodies with newlines, quotes and unicode survive', () {
    final out = line(9, '$marker\n| a | "b" | ▲ +1 KB |');
    expect(findMarkedCommentId(out, marker), 9);
    expect(findMarkedCommentId(out, commentMarker('ios')), isNull);
    expect(findMarkedCommentId('', marker), isNull);
  });

  test('gh failures become GhException', () async {
    final listFails = FakeGh('', failOn: '--paginate');
    expect(
      () => upsertStickyComment(repo: 'me/app', pr: 1, marker: marker, body: 'x', gh: listFails.call),
      throwsA(isA<GhException>().having((e) => e.toString(), 'message', contains('HTTP 403'))),
    );
    final postFails = FakeGh('', failOn: 'POST');
    expect(
      () => upsertStickyComment(repo: 'me/app', pr: 1, marker: marker, body: 'x', gh: postFails.call),
      throwsA(isA<GhException>()),
    );
  });
}
