import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Opens a URL in the user's browser.
///
/// Shells out rather than adding `url_launcher`: this is the only call site,
/// and the codebase already invokes `xattr`, `plutil`, `chmod` and `ps`
/// directly for platform work.
class UrlOpenerService {
  final Future<ProcessResult> Function(String executable, List<String> args)
      _runProcess;

  UrlOpenerService({
    Future<ProcessResult> Function(String executable, List<String> args)?
        runProcess,
  }) : _runProcess = runProcess ?? Process.run;

  /// Returns false if the URL could not be opened, so the caller can fall back
  /// to putting it on the clipboard.
  Future<bool> open(String url) async {
    if (kIsWeb) return false;
    if (!_isSafeUrl(url)) return false;

    final executable = switch (Platform.operatingSystem) {
      'macos' => 'open',
      'linux' => 'xdg-open',
      'windows' => 'explorer',
      _ => null,
    };
    if (executable == null) return false;

    try {
      final result = await _runProcess(executable, [url]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Only http(s) is handed to the shell. The URL arrives from a remote
  /// manifest, so anything else (`file:`, a leading `-` that could be read as a
  /// flag) is refused rather than passed along.
  static bool _isSafeUrl(String url) {
    if (url.startsWith('-')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }
}
