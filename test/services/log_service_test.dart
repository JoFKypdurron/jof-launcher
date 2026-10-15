import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/log_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jof_log_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('appends tagged lines to the log file', () async {
    final log = LogService(resolveDirectory: () async => tempDir);

    log.log('repo', 'first');
    log.log('repo', 'second');
    await log.flush();

    final path = p.join(tempDir.path, LogService.fileName);
    final lines = await File(path).readAsLines();
    expect(lines, hasLength(2));
    expect(lines[0], endsWith('[repo] first'));
    expect(lines[1], endsWith('[repo] second'));
    expect(await log.logFilePath(), path);
  });

  test('rotates a full log to .1, replacing the older one', () async {
    final file = File(p.join(tempDir.path, LogService.fileName));
    await file.writeAsString('x' * LogService.maxBytes);
    await File('${file.path}.1').writeAsString('oldest');
    final log = LogService(resolveDirectory: () async => tempDir);

    log.log('repo', 'after rotation');
    await log.flush();

    expect(await File('${file.path}.1').length(), LogService.maxBytes);
    final lines = await file.readAsLines();
    expect(lines.single, endsWith('[repo] after rotation'));
  });

  test('keeps working without a log directory', () async {
    final log = LogService(resolveDirectory: () async => throw StateError('no dir'));

    log.log('repo', 'only in memory');
    await log.flush();

    expect(await log.logFilePath(), isNull);
    expect(log.recentLines.single, endsWith('[repo] only in memory'));
  });
}
