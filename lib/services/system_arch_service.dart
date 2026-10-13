import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/platform_arch.dart';
import 'settings_service.dart';

/// Resolves which CPU architecture's client build belongs on this machine.
///
/// Everything that touches an architecture-specific client filename goes
/// through here, because the download side and the launch side must never
/// disagree: the macOS tarballs unpack to `eternaljk.arm64.app` or
/// `eternaljk.x86_64.app`, so resolving `arm` while installing and `amd` while
/// launching leaves the launcher opening a bundle that was never written.
///
/// The two platforms weigh the stored setting differently, because the
/// Settings screen offers the choice differently. On Linux the dropdown is
/// always available, so a stored value is a deliberate override (a 32-bit
/// client on a 64-bit machine is a legitimate choice) and wins. On macOS the
/// dropdown only appears when detection fails, so there is no override to
/// respect: `uname -m` is the authority and a stored value is the fallback,
/// which also keeps a value carried over from another Mac — or from before an
/// Intel-to-Apple Silicon upgrade — from outliving the hardware it described.
class SystemArchService {
  final SettingsService _settingsService;
  final Future<String?> Function()? _unameOverride;

  /// `uname -m` cannot change while the process lives, so the first answer is
  /// reused. The launch path re-resolves on every five-second game-status
  /// poll, and spawning a process that often for a constant is wasteful.
  Future<String?>? _unameResult;

  /// [unameOverride] stands in for `uname -m` in tests, which run on the host
  /// platform rather than the one being exercised.
  SystemArchService({
    SettingsService? settingsService,
    Future<String?> Function()? unameOverride,
  })  : _settingsService = settingsService ?? SettingsService(),
        _unameOverride = unameOverride;

  /// Maps a `uname -m` value to a macOS architecture, or null when it names
  /// something we have no client build for.
  static MacosSystemArch? parseMacosUname(String value) {
    return switch (value.trim().toLowerCase()) {
      'arm64' || 'aarch64' => MacosSystemArch.arm,
      'x86_64' || 'amd64' => MacosSystemArch.amd,
      _ => null,
    };
  }

  /// Maps a `uname -m` value to a Linux architecture. Anything reporting 64 is
  /// taken as 64-bit; everything else falls back to the 32-bit build.
  static LinuxSystemArch parseLinuxUname(String value) {
    return value.trim().toLowerCase().contains('64')
        ? LinuxSystemArch.bit64
        : LinuxSystemArch.bit32;
  }

  Future<String?> _uname() => _unameResult ??= _runUname();

  Future<String?> _runUname() async {
    final override = _unameOverride;
    if (override != null) return override();
    if (kIsWeb) return null;
    try {
      final result = await io.Process.run('uname', ['-m']);
      if (result.exitCode != 0) return null;
      return result.stdout.toString();
    } catch (_) {
      return null;
    }
  }

  bool _isPlatform(bool Function() test) =>
      _unameOverride != null || (!kIsWeb && test());

  /// The architecture this Mac reports, or null when `uname` is unavailable or
  /// reports something unrecognised.
  Future<MacosSystemArch?> detectMacos() async {
    if (!_isPlatform(() => io.Platform.isMacOS)) return null;
    final output = await _uname();
    return output == null ? null : parseMacosUname(output);
  }

  Future<LinuxSystemArch?> detectLinux() async {
    if (!_isPlatform(() => io.Platform.isLinux)) return null;
    final output = await _uname();
    return output == null ? null : parseLinuxUname(output);
  }

  /// The macOS architecture to install and launch for, or null when neither
  /// detection nor an earlier manual choice supplies one — the only case in
  /// which Settings asks the user to pick.
  ///
  /// A successful detection is written back so that Settings, a later launch
  /// and the installed bundle all describe the same machine.
  Future<MacosSystemArch?> resolveMacos() async {
    final detected = await detectMacos();
    if (detected != null) {
      final stored = await _settingsService.getMacosSystemArch();
      if (stored != detected.persistedValue) {
        await _settingsService.setMacosSystemArch(detected.persistedValue);
      }
      return detected;
    }
    return MacosSystemArchCodec.tryParse(
        await _settingsService.getMacosSystemArch());
  }

  /// The Linux architecture to install and launch for. Unlike macOS there is a
  /// safe default: 64-bit covers every machine the client still ships for.
  Future<LinuxSystemArch> resolveLinux() async {
    final persisted = LinuxSystemArchCodec.tryParse(
        await _settingsService.getLinuxSystemArch());
    return persisted ?? await detectLinux() ?? LinuxSystemArch.bit64;
  }
}
