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

  /// Test seam, so every platform's command can be checked from one host.
  final String? _operatingSystemOverride;

  UrlOpenerService({
    Future<ProcessResult> Function(String executable, List<String> args)?
        runProcess,
    String? operatingSystemOverride,
  })  : _runProcess = runProcess ?? Process.run,
        _operatingSystemOverride = operatingSystemOverride;

  /// Returns false if the URL could not be opened, so the caller can fall back
  /// to putting it on the clipboard.
  Future<bool> open(String url) async {
    if (kIsWeb) return false;
    if (!_isSafeUrl(url)) return false;

    final command = switch (_operatingSystemOverride ?? Platform.operatingSystem) {
      'macos' => ('open', [url]),
      'linux' => ('xdg-open', [url]),
      // Not `explorer <url>`, which exits with 1 even when the browser opened,
      // so every success would read as a failure. Nor `cmd /c start`, which
      // would hand the URL to cmd's parser, where `&` splits commands.
      'windows' => ('rundll32', ['url.dll,FileProtocolHandler', url]),
      _ => null,
    };
    if (command == null) return false;

    try {
      final result = await _runProcess(command.$1, command.$2);
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
