import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Appends diagnostic lines to `launcher.log` in the app support directory.
///
/// Release builds on Windows have no console, so `debugPrint` alone is
/// invisible to support. Lines are still echoed through `debugPrint` for
/// development. Logging never throws: if the directory cannot be resolved
/// (web, tests without a platform channel) lines only go to `debugPrint`.
///
/// The file rotates once it passes [maxBytes]: the current log becomes
/// `launcher.log.1`, replacing any older one, so disk use stays bounded at
/// roughly twice [maxBytes].
class LogService {
  static LogService instance = LogService();

  static const String fileName = 'launcher.log';
  static const int maxBytes = 1 << 20;

  /// Lines kept in memory, newest last. Lets tests (and a future in-app view)
  /// read recent entries without touching the file.
  static const int _recentCapacity = 200;

  final Future<io.Directory?> Function() _resolveDirectory;
  final List<String> _recent = [];

  Future<io.File?>? _file;
  Future<void> _pending = Future.value();

  LogService({Future<io.Directory?> Function()? resolveDirectory})
      : _resolveDirectory = resolveDirectory ?? _defaultDirectory;

  static Future<io.Directory?> _defaultDirectory() async {
    if (kIsWeb) return null;
    final support = await getApplicationSupportDirectory();
    return io.Directory(p.join(support.path, 'logs'));
  }

  List<String> get recentLines => List.unmodifiable(_recent);

  /// Absolute path of the log file, or null when there is none.
  Future<String?> logFilePath() async => (await _logFile())?.path;

  void log(String tag, String message) {
    final line = '${DateTime.now().toIso8601String()} [$tag] $message';
    debugPrint(line);
    _recent.add(line);
    if (_recent.length > _recentCapacity) _recent.removeAt(0);
    _pending = _pending.then((_) => _append(line)).catchError((Object _) {});
  }

  /// Completes once every line logged so far has been written.
  @visibleForTesting
  Future<void> flush() => _pending;

  Future<io.File?> _logFile() {
    return _file ??= () async {
      try {
        final dir = await _resolveDirectory();
        if (dir == null) return null;
        await dir.create(recursive: true);
        return io.File(p.join(dir.path, fileName));
      } catch (_) {
        return null;
      }
    }();
  }

  Future<void> _append(String line) async {
    final file = await _logFile();
    if (file == null) return;
    if (await file.exists() && await file.length() >= maxBytes) {
      final previous = io.File('${file.path}.1');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }
    await file.writeAsString('$line\n', mode: io.FileMode.append, flush: true);
  }
}
