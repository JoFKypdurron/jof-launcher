import 'package:flutter_test/flutter_test.dart';

import 'package:joflauncher/models/update_manifest.dart';
import 'package:joflauncher/services/install_location_service.dart';

const _macApp = '/Applications/JoF Launcher.app/Contents/MacOS/JoF Launcher';
const _macTranslocated =
    '/private/var/folders/0_/xyz/T/AppTranslocation/ABC-123/d/JoF Launcher.app/Contents/MacOS/JoF Launcher';
const _macVolume =
    '/Volumes/JoF Launcher/JoF Launcher.app/Contents/MacOS/JoF Launcher';
const _macDev =
    '/Users/me/Sites/jof/launcher/build/macos/Build/Products/Release/JoF Launcher.app/Contents/MacOS/JoF Launcher';
const _linuxDeb = '/opt/jof-launcher/jof-launcher';
const _linuxTar = '/home/me/apps/jof-launcher/jof-launcher';
const _windowsInstalled =
    r'C:\Users\me\AppData\Local\Programs\JoF Launcher\jof-launcher.exe';

InstallKind classifyMac(String exe, {bool release = true}) =>
    InstallLocationService.classify(
      resolvedExecutable: exe,
      os: 'macos',
      env: const {},
      isReleaseMode: release,
    );

InstallKind classifyLinux(String exe,
        {Map<String, String> env = const {}, bool release = true}) =>
    InstallLocationService.classify(
      resolvedExecutable: exe,
      os: 'linux',
      env: env,
      isReleaseMode: release,
    );

void main() {
  group('classify - macOS', () {
    test('a normal .app install is eligible', () {
      expect(classifyMac(_macApp), InstallKind.macosAppBundle);
    });

    test('translocation is detected before anything else', () {
      // The path also lives under /private/var/folders, but translocation is
      // the actionable diagnosis, so it must win.
      expect(classifyMac(_macTranslocated), InstallKind.macosTranslocated);
    });

    test('running from a mounted DMG is detected', () {
      expect(classifyMac(_macVolume), InstallKind.macosOnVolume);
    });

    test('a build tree is never self-updated', () {
      expect(classifyMac(_macDev), InstallKind.macosDevBuild);
      // Debug mode alone is enough, wherever it runs from.
      expect(classifyMac(_macApp, release: false), InstallKind.macosDevBuild);
    });

    test('a binary with no .app ancestor is unknown', () {
      expect(classifyMac('/usr/local/bin/jof'), InstallKind.unknown);
    });

    test('~/Applications counts as a normal install', () {
      expect(
        classifyMac('/Users/me/Applications/JoF Launcher.app/Contents/MacOS/JoF Launcher'),
        InstallKind.macosAppBundle,
      );
    });
  });

  group('classify - Linux', () {
    test('the tarball layout is eligible', () {
      expect(classifyLinux(_linuxTar), InstallKind.linuxTarball);
    });

    test('the .deb location is never self-updated', () {
      expect(classifyLinux(_linuxDeb), InstallKind.linuxDeb);
      // Non-normalised paths must reach the same verdict.
      expect(classifyLinux('/opt/jof-launcher/./jof-launcher'),
          InstallKind.linuxDeb);
    });

    test('AppImage and Snap defer to their own updaters', () {
      expect(classifyLinux(_linuxTar, env: {'APPIMAGE': '/x.AppImage'}),
          InstallKind.linuxPackagedOther);
      expect(classifyLinux(_linuxTar, env: {'SNAP': '/snap/x'}),
          InstallKind.linuxPackagedOther);
    });
  });

  group('classify - Windows', () {
    InstallKind classifyWindows({
      required bool hasUninstaller,
      bool isReleaseMode = true,
    }) {
      return InstallLocationService.classify(
        resolvedExecutable: _windowsInstalled,
        os: 'windows',
        env: const {},
        isReleaseMode: isReleaseMode,
        hasWindowsUninstaller: hasUninstaller,
      );
    }

    test('the installer leaves an uninstaller beside the exe', () {
      expect(classifyWindows(hasUninstaller: true),
          InstallKind.windowsInstalled);
    });

    test('without one it is the portable zip', () {
      expect(classifyWindows(hasUninstaller: false),
          InstallKind.windowsPortable);
    });

    test('a debug build is never treated as an install', () {
      expect(classifyWindows(hasUninstaller: true, isReleaseMode: false),
          InstallKind.unknown);
    });
  });

  group('bundlePathFor', () {
    test('walks up to the .app root on macOS', () {
      expect(
        InstallLocationService.bundlePathFor(
            resolvedExecutable: _macApp, os: 'macos'),
        '/Applications/JoF Launcher.app',
      );
    });

    test('is the containing directory on Linux', () {
      expect(
        InstallLocationService.bundlePathFor(
            resolvedExecutable: _linuxTar, os: 'linux'),
        '/home/me/apps/jof-launcher',
      );
    });

    test('is the containing directory on Windows', () {
      expect(
        InstallLocationService.bundlePathFor(
            resolvedExecutable: _windowsInstalled, os: 'windows'),
        r'C:\Users\me\AppData\Local\Programs\JoF Launcher',
      );
    });

    test('is null when there is no .app ancestor', () {
      expect(
        InstallLocationService.bundlePathFor(
            resolvedExecutable: '/usr/local/bin/jof', os: 'macos'),
        isNull,
      );
    });
  });

  group('eligibility', () {
    Future<InstallLocation> detect(
      String exe, {
      required bool writable,
      bool hasUninstaller = true,
    }) {
      return InstallLocationService(
        resolvedExecutableOverride: exe,
        environmentOverride: const {},
        writabilityProbe: (_) async => writable,
        fileExistsProbe: (path) async {
          expect(path, endsWith(r'\JoF Launcher\unins000.exe'));
          return hasUninstaller;
        },
        isReleaseModeOverride: true,
        osOverride: exe.endsWith('.exe') ? 'windows' : (exe.contains('.app/') ? 'macos' : 'linux'),
      ).detect();
    }

    test('an unwritable parent blocks self-update even for a good install',
        () async {
      final loc = await detect(_macApp, writable: false);
      expect(loc.kind, InstallKind.macosAppBundle);
      expect(loc.canSelfUpdate, isFalse);
      expect(loc.reason, contains('write access'));
    });

    test('a writable .deb location is still never self-updated', () async {
      final loc = await detect(_linuxDeb, writable: true);
      expect(loc.kind, InstallKind.linuxDeb);
      expect(loc.canSelfUpdate, isFalse);
    });

    test('maps install kind to the right release artifact', () async {
      expect((await detect(_linuxDeb, writable: true)).artifactKind,
          UpdateArtifactKind.linuxDeb);
      expect((await detect(_linuxTar, writable: true)).artifactKind,
          UpdateArtifactKind.linuxTar);
      expect((await detect(_macApp, writable: true)).artifactKind,
          UpdateArtifactKind.macos);
      expect((await detect(_windowsInstalled, writable: true)).artifactKind,
          UpdateArtifactKind.windows);
    });

    test('an installer install updates itself', () async {
      final loc = await detect(_windowsInstalled, writable: true);
      expect(loc.kind, InstallKind.windowsInstalled);
      expect(loc.canSelfUpdate, isTrue);
      expect(loc.reason, isNull);
    });

    test('the portable zip points the user at the installer', () async {
      final loc = await detect(_windowsInstalled,
          writable: true, hasUninstaller: false);
      expect(loc.kind, InstallKind.windowsPortable);
      expect(loc.canSelfUpdate, isFalse);
      expect(loc.artifactKind, isNull);
      expect(loc.reason, contains('installer'));
    });
  });
}
