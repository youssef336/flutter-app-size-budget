/// Finds the analyze-size JSON and the built artifact from the output of
/// `flutter build ... --analyze-size`.
library;

import 'dart:io';

/// flutter_tools prints (android/gradle.dart, commands/build_ios.dart):
///   "A summary of your APK analysis can be found at: /home/.../apk-code-size-analysis_01.json"
final _analysisLine = RegExp(r'A summary of your .*? analysis can be found at: (\S+\.json)');

/// "✓ Built build/app/outputs/flutter-apk/app-release.apk (15.5MB)"
/// "✓ Built build/app/outputs/bundle/release/app-release.aab (20.1MB)"
/// "✓ Built build/ios/iphoneos/Runner.app (40.2MB)"
final _builtLine = RegExp(r'Built (\S+?\.(?:apk|aab|app))(?=\s|$)', multiLine: true);

String? findAnalysisPath(String log) {
  final matches = _analysisLine.allMatches(log).toList();
  return matches.isEmpty ? null : matches.last.group(1);
}

String? findArtifactPath(String log) {
  final matches = _builtLine.allMatches(log).toList();
  return matches.isEmpty ? null : matches.last.group(1);
}

/// Size of a file, or the recursive size of a directory (`Runner.app`).
int artifactSize(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) {
    return File(path).lengthSync();
  }
  if (type == FileSystemEntityType.directory) {
    var total = 0;
    for (final entity in Directory(path).listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += entity.lengthSync();
      }
    }
    return total;
  }
  throw FileSystemException('Artifact not found', path);
}
