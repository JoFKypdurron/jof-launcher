import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/asset_group.dart';
import '../models/platform_arch.dart';
import 'settings_service.dart';
import 'system_arch_service.dart';

class ExecutableInfo {
  final String executablePath;
  final String workingDirectory;
  ExecutableInfo(this.executablePath, this.workingDirectory);
}

class GameService {
  final SettingsService _settingsService = SettingsService();
  final SystemArchService _systemArch;
  final String? _platformOverride;

  GameService({String? platformOverride, SystemArchService? systemArchService})
      : _platformOverride = platformOverride,
        _systemArch = systemArchService ?? SystemArchService();

  bool get _isWindows => _platformOverride == 'windows' || (_platformOverride == null && Platform.isWindows);
  bool get _isMacOS => _platformOverride == 'macos' || (_platformOverride == null && Platform.isMacOS);
  bool get _isLinux => _platformOverride == 'linux' || (_platformOverride == null && Platform.isLinux);

  /// Open-file limit requested before launching the game on macOS. Comfortably
  /// above the ~300 .pk3 files a fully populated GameData folder holds, each of
  /// which the engine keeps open.
  static const int _macOsOpenFileLimit = 4096;

  @visibleForTesting
  Future<ExecutableInfo?> getExecutableInfo(String gameDataPath) async {
    return _getExecutableInfo(gameDataPath);
  }

  /// The `.app` bundle the macOS client tarball unpacks to for [arch].
  ///
  /// Falls back to the Intel bundle when the architecture is unknown, matching
  /// the historical default; on such a machine the user is prompted to pick
  /// one in Settings.
  @visibleForTesting
  static String macosBundleName(MacosSystemArch? arch) {
    return switch (arch) {
      MacosSystemArch.arm => 'eternaljk.arm64.app',
      MacosSystemArch.amd || null => 'eternaljk.x86_64.app',
    };
  }

  /// The binary the Linux client tarball unpacks to for [arch].
  @visibleForTesting
  static String linuxBinaryName(LinuxSystemArch arch) {
    return switch (arch) {
      LinuxSystemArch.bit32 => 'eternaljk.x86',
      LinuxSystemArch.bit64 => 'eternaljk.x86_64',
    };
  }

  /// Resolves the actual binary inside a macOS `.app`, preferring the
  /// Info.plist `CFBundleExecutable` and falling back to the bundle name.
  @visibleForTesting
  Future<String?> bundleExecutable(String appPath) => _bundleExecutable(appPath);

  Future<String?> _bundleExecutable(String appPath) async {
    final macOsDir = p.join(appPath, 'Contents', 'MacOS');

    try {
      final result = await Process.run('plutil', [
        '-extract',
        'CFBundleExecutable',
        'raw',
        '-o',
        '-',
        p.join(appPath, 'Contents', 'Info.plist'),
      ]);
      final name = result.stdout.toString().trim();
      if (result.exitCode == 0 && name.isNotEmpty) {
        final candidate = p.join(macOsDir, name);
        if (await File(candidate).exists()) return candidate;
      }
    } catch (_) {
      // Fall through to the name-based guess below.
    }

    // Bundles built without a CFBundleExecutable still follow the convention
    // that the binary is named after the bundle, e.g. foo.app/Contents/MacOS/foo.
    final byName = p.join(macOsDir, p.basenameWithoutExtension(appPath));
    if (await File(byName).exists()) return byName;

    return null;
  }

  Future<ExecutableInfo?> _getExecutableInfo(String gameDataPath) async {
    String? executablePath;
    String workingDirectory = gameDataPath;

    if (_isWindows) {
      executablePath = p.join(gameDataPath, 'eternaljk.x86.exe');
    } else if (_isMacOS) {
      // Resolved the same way the download does, so the bundle we launch is
      // the one that was installed: `eternaljk.arm64.app` for Apple Silicon,
      // `eternaljk.x86_64.app` for Intel.
      final arch = await _systemArch.resolveMacos();
      executablePath = p.join(gameDataPath, macosBundleName(arch));
    } else if (_isLinux) {
      final arch = await _systemArch.resolveLinux();
      executablePath = p.join(gameDataPath, linuxBinaryName(arch));
    }

    if (executablePath == null) return null;
    return ExecutableInfo(executablePath, workingDirectory);
  }

  Future<bool> isGameRunning() async {
    final gameDataPath = await _settingsService.getGameDataPath();
    if (gameDataPath == null) return false;

    final info = await _getExecutableInfo(gameDataPath);
    if (info == null) return false;

    try {
      if (_isLinux || _isMacOS) {
        final result = await Process.run('ps', ['-Ao', 'args']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          return lines.any((line) => isProcessMatch(line, info.executablePath));
        }
      } else if (_isWindows) {
        final result = await Process.run('tasklist', ['/NH', '/FO', 'CSV']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          final exeName = p.basename(info.executablePath).toLowerCase();
          return lines.any((line) => line.toLowerCase().contains('"$exeName"'));
        }
      }
    } catch (e) {
      // ignore
    }

    return false;
  }

  static bool isProcessMatch(String line, String executablePath) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    // `ps -Ao args` may show either the full executable path or just the command
    // name (basename), depending on how the process was launched.
    final unixPath = executablePath;
    if (trimmed.contains(unixPath)) return true;

    final basename = p.basename(executablePath);
    if (basename.endsWith('.app')) {
      final appName = basename.substring(0, basename.length - 4);
      // On macOS, the process name for a .app is usually the app name without extension.
      // We check for both the full path and the app name.
      if (trimmed.contains(appName)) return true;
    }

    // Match whole token occurrences of the executable name.
    final basenameRegex = RegExp(r'(^|\s)' + RegExp.escape(basename) + r'(\s|$)');
    return basenameRegex.hasMatch(trimmed);
  }

  Future<void> launchGame(
      {AssetGroup? selectedMod, bool connectToPublic = false}) async {
    final gameDataPath = await _settingsService.getGameDataPath();

    if (gameDataPath == null) return;

    final info = await _getExecutableInfo(gameDataPath);
    if (info == null) return;

    final executablePath = info.executablePath;
    final workingDirectory = info.workingDirectory;

    final List<String> args = [];
    if (selectedMod != null && selectedMod.paramstring != null && selectedMod.paramstring!.isNotEmpty) {
      args.addAll(selectedMod.paramstring!.split(' '));
    }
    if (connectToPublic) {
      args.addAll(['+connect', 'jof.jka.io']);
    }

    if (_isWindows) {
      if (await File(executablePath).exists()) {
        await Process.start(
          executablePath,
          args,
          mode: ProcessStartMode.detached,
          workingDirectory: workingDirectory,
        );
      } else {
        throw Exception('Executable not found: $executablePath');
      }
    } else if (_isMacOS) {
      if (executablePath.endsWith('.app')) {
        if (await Directory(executablePath).exists()) {
          // Remove quarantine attribute for unsigned apps
          try {
            await Process.run('xattr', ['-rd', 'com.apple.quarantine', executablePath]);
          } catch (_) {
            // ignore errors if xattr fails or attribute doesn't exist
          }

          // Launch the bundle's binary directly instead of via `open`.
          //
          // `open` hands the bundle to LaunchServices, which brings two
          // problems the engine cannot survive:
          //
          //  * the process is reparented to launchd and inherits its 256 open
          //    file limit. The engine holds a descriptor per .pk3, and a full
          //    asset library runs past that, so dlopen of the renderer fails
          //    with EMFILE and the game exits with "Failed to load renderer".
          //  * a quarantined bundle gets App Translocation, running from a
          //    randomised temp path where the sibling GameData folder — and
          //    therefore the game assets — is no longer visible.
          final binary = await _bundleExecutable(executablePath);
          if (binary == null) {
            throw Exception('No executable found inside bundle: $executablePath');
          }

          await Process.start(
            '/bin/sh',
            [
              '-c',
              'ulimit -n $_macOsOpenFileLimit 2>/dev/null; exec "\$0" "\$@"',
              binary,
              ...args,
            ],
            mode: ProcessStartMode.detached,
            workingDirectory: workingDirectory,
          );
        } else {
          throw Exception('App not found: $executablePath');
        }
      } else {
        if (await File(executablePath).exists()) {
          await Process.start(
            executablePath,
            args,
            mode: ProcessStartMode.detached,
            workingDirectory: workingDirectory,
          );
        } else {
          throw Exception('Executable not found: $executablePath');
        }
      }
    } else if (_isLinux) {
      if (await File(executablePath).exists()) {
        // Ensure it's executable
        await Process.run('chmod', ['+x', executablePath]);
        await Process.start(
          executablePath,
          args,
          mode: ProcessStartMode.detached,
          workingDirectory: workingDirectory,
        );
      } else {
        throw Exception('Executable not found: $executablePath');
      }
    }
  }
}
