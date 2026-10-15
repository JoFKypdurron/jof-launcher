import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/platform_arch.dart';
import 'package:joflauncher/services/settings_service.dart';
import 'package:joflauncher/services/system_arch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a service whose `uname -m` answers [uname] (null to simulate a
/// failed or unavailable detection).
SystemArchService serviceFor(String? uname) {
  return SystemArchService(unameOverride: () async => uname);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SystemArchService.parseMacosUname', () {
    test('recognises both Apple Silicon spellings', () {
      expect(SystemArchService.parseMacosUname('arm64'), MacosSystemArch.arm);
      expect(SystemArchService.parseMacosUname('aarch64'), MacosSystemArch.arm);
    });

    test('recognises both Intel spellings', () {
      expect(SystemArchService.parseMacosUname('x86_64'), MacosSystemArch.amd);
      expect(SystemArchService.parseMacosUname('amd64'), MacosSystemArch.amd);
    });

    test('tolerates the trailing newline uname prints', () {
      expect(SystemArchService.parseMacosUname('arm64\n'), MacosSystemArch.arm);
    });

    test('returns null for an architecture with no client build', () {
      expect(SystemArchService.parseMacosUname('ppc'), isNull);
      expect(SystemArchService.parseMacosUname(''), isNull);
    });
  });

  group('SystemArchService.parseLinuxUname', () {
    test('treats anything reporting 64 as 64-bit', () {
      expect(SystemArchService.parseLinuxUname('x86_64'), LinuxSystemArch.bit64);
      expect(SystemArchService.parseLinuxUname('aarch64\n'), LinuxSystemArch.bit64);
    });

    test('falls back to 32-bit otherwise', () {
      expect(SystemArchService.parseLinuxUname('i686'), LinuxSystemArch.bit32);
    });
  });

  group('SystemArchService.resolveMacos', () {
    test('uses the detected architecture', () async {
      expect(await serviceFor('arm64').resolveMacos(), MacosSystemArch.arm);
      expect(await serviceFor('x86_64').resolveMacos(), MacosSystemArch.amd);
    });

    test('persists the detection so later reads agree with it', () async {
      await serviceFor('arm64').resolveMacos();

      expect(await SettingsService().getMacosSystemArch(),
          MacosSystemArch.arm.persistedValue);
    });

    // A stored value is only ever a detection that has since gone stale — the
    // Settings dropdown is hidden whenever detection works — so it must not
    // outlive the machine it described.
    test('overrides a stored value that disagrees with the hardware', () async {
      SharedPreferences.setMockInitialValues(
          {'macos_system_arch': MacosSystemArch.amd.persistedValue});

      expect(await serviceFor('arm64').resolveMacos(), MacosSystemArch.arm);
      expect(await SettingsService().getMacosSystemArch(),
          MacosSystemArch.arm.persistedValue);
    });

    test('falls back to the stored value when detection fails', () async {
      SharedPreferences.setMockInitialValues(
          {'macos_system_arch': MacosSystemArch.arm.persistedValue});

      expect(await serviceFor(null).resolveMacos(), MacosSystemArch.arm);
      expect(await serviceFor('ppc').resolveMacos(), MacosSystemArch.arm);
    });

    test('returns null when nothing can supply an architecture', () async {
      expect(await serviceFor(null).resolveMacos(), isNull);
    });
  });

  test('detection runs once and is reused across resolves', () async {
    var calls = 0;
    final service = SystemArchService(unameOverride: () async {
      calls++;
      return 'arm64';
    });

    // The launch path re-resolves on every game-status poll.
    await service.resolveMacos();
    await service.resolveMacos();
    await service.resolveMacos();

    expect(calls, 1);
  });

  group('SystemArchService Windows detection', () {
    WindowsSystemArch? detect(Map<String, String> env) =>
        SystemArchService(environmentOverride: env).detectWindows();

    test('maps PROCESSOR_ARCHITECTURE values to a client build', () {
      expect(detect({'PROCESSOR_ARCHITECTURE': 'AMD64'}),
          WindowsSystemArch.bit64);
      expect(detect({'PROCESSOR_ARCHITECTURE': 'x86'}), WindowsSystemArch.bit32);
    });

    // There is no ARM64 client; Windows on ARM runs the x86_64 build emulated.
    test('runs the 64-bit build on ARM64', () {
      expect(detect({'PROCESSOR_ARCHITECTURE': 'ARM64'}),
          WindowsSystemArch.bit64);
    });

    // A 32-bit process on 64-bit Windows sees PROCESSOR_ARCHITECTURE=x86.
    test('prefers PROCESSOR_ARCHITEW6432, which describes the machine', () {
      expect(
        detect({
          'PROCESSOR_ARCHITECTURE': 'x86',
          'PROCESSOR_ARCHITEW6432': 'AMD64',
        }),
        WindowsSystemArch.bit64,
      );
    });

    test('defaults to 64-bit when the environment says nothing', () {
      expect(detect(const {}), isNull);
      expect(SystemArchService(environmentOverride: const {}).resolveWindows(),
          WindowsSystemArch.bit64);
    });
  });

  group('SystemArchService.resolveLinux', () {
    // Unlike macOS, the Linux dropdown is always offered, so a stored value is
    // a deliberate choice: running the 32-bit client on a 64-bit machine.
    test('prefers a stored choice over detection', () async {
      SharedPreferences.setMockInitialValues(
          {'linux_system_arch': LinuxSystemArch.bit32.persistedValue});

      expect(await serviceFor('x86_64').resolveLinux(), LinuxSystemArch.bit32);
    });

    test('detects when nothing is stored', () async {
      expect(await serviceFor('i686').resolveLinux(), LinuxSystemArch.bit32);
      expect(await serviceFor('x86_64').resolveLinux(), LinuxSystemArch.bit64);
    });

    test('defaults to 64-bit when detection fails', () async {
      expect(await serviceFor(null).resolveLinux(), LinuxSystemArch.bit64);
    });
  });
}
