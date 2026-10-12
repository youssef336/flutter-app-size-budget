// Shrinks a real `*-code-size-analysis_NN.json` into a test fixture without
// changing its shape or totals:
//
// * the archive tree (zip entries / bundle files) is kept as is;
// * inside the Dart AOT node, every library root keeps its direct children,
//   and anything deeper is collapsed into a leaf whose `value` is the sum of
//   the subtree (exactly what the parser computes anyway);
// * `precompiler-trace` is emptied (the action never reads it).
//
//   dart run test/fixtures/trim_fixture.dart in.json out.json
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>;
  input['precompiler-trace'] = <String, Object?>{};
  _walk(input);
  File(args[1]).writeAsStringSync(jsonEncode(input));
}

void _walk(Map<String, Object?> node) {
  final children = (node['children'] as List<Object?>?)?.cast<Map<String, Object?>>();
  if (children == null) {
    return;
  }
  if ((node['n'] as String).endsWith(' (Dart AOT)')) {
    for (final library in children) {
      final libChildren = (library['children'] as List<Object?>?)?.cast<Map<String, Object?>>();
      if (libChildren == null) {
        continue;
      }
      library['children'] = [
        for (final child in libChildren)
          if (_size(child) > 0) {'n': child['n'], 'value': _size(child)},
      ];
    }
    return;
  }
  children.forEach(_walk);
}

int _size(Map<String, Object?> node) {
  final children = (node['children'] as List<Object?>?)?.cast<Map<String, Object?>>();
  if (children == null || children.isEmpty) {
    return (node['value'] as num?)?.toInt() ?? 0;
  }
  return children.fold<int>(0, (sum, c) => sum + _size(c));
}
