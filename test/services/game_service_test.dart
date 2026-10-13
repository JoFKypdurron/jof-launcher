import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/models/platform_arch.dart';
import 'package:joflauncher/services/client_release_service.dart';
import 'package:joflauncher/services/game_service.dart';
import 'package:joflauncher/services/system_arch_service.dart';
import 'package:joflauncher/models/asset_group.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Client naming', () {
    // The names the JoF_EJK release tarballs actually unpack to, verified
    // against the published macOS assets: `eternaljk.<arch>.app` at the root
    // of the archive, next to `base/` and `EternalJK/`.
    test('macOS bundle names match the published .app bundles', () {
      expect(GameService.macosBundleName(MacosSystemArch.arm),
          'eternaljk.arm64.app');
      expect(GameService.macosBundleName(MacosSystemArch.amd),
          'eternaljk.x86_64.app');
    });

    test('an unknown macOS architecture falls back to the Intel bundle', () {
      expect(GameService.macosBundleName(null), 'eternaljk.x86_64.app');
    });

    test('Linux binary names match the published tarball contents', () {
      expect(GameService.linuxBinaryName(LinuxSystemArch.bit32),
          'eternaljk.x86');
      expect(GameService.linuxBinaryName(LinuxSystemArch.bit64),
          'eternaljk.x86_64');
    });

    // The bug this guards against: downloading `JoF-macos-arm64.tar.gz` and
    // then launching `eternaljk.x86_64.app`, which the archive never wrote.
    test('the downloaded macOS asset and the launched bundle agree on arch',
        () {
      for (final arch in MacosSystemArch.values) {
        final assetArch = ClientReleaseService.macosAssetName(arch)
            .replaceAll('JoF-macos-', '')
            .replaceAll('.tar.gz', '');
        expect(GameService.macosBundleName(arch), 'eternaljk.$assetArch.app',
            reason: 'asset and bundle disagree for $arch');
      }
    });
  });

  group('macOS executable resolution', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('launches the bundle matching the detected architecture', () async {
      final service = GameService(
        platformOverride: 'macos',
        systemArchService:
            SystemArchService(unameOverride: () async => 'arm64'),
      );

      final info = await service.getExecutableInfo('/GameData');
      expect(info!.executablePath, '/GameData/eternaljk.arm64.app');
      expect(info.workingDirectory, '/GameData');
    });

    // Detection is never persisted by the Settings screen alone, so before
    // this was resolved centrally an Apple Silicon Mac installed the arm64
    // bundle and then looked for the Intel one.
    test('detection wins over a stale stored architecture', () async {
      SharedPreferences.setMockInitialValues({'macos_system_arch': 'amd'});

      final service = GameService(
        platformOverride: 'macos',
        systemArchService:
            SystemArchService(unameOverride: () async => 'arm64'),
      );

      expect((await service.getExecutableInfo('/GameData'))!.executablePath,
          '/GameData/eternaljk.arm64.app');
    });

    test('falls back to the stored architecture when detection fails',
        () async {
      SharedPreferences.setMockInitialValues({'macos_system_arch': 'arm'});

      final service = GameService(
        platformOverride: 'macos',
        systemArchService: SystemArchService(unameOverride: () async => null),
      );

      expect((await service.getExecutableInfo('/GameData'))!.executablePath,
          '/GameData/eternaljk.arm64.app');
    });
  });

  group('Linux process matching logic', () {
    const exePath =
        '/home/me/.local/share/Steam/steamapps/common/Jedi Academy/GameData/eternaljk.x86_64';

    test('matches exact unix path', () {
      expect(GameService.isProcessMatch(exePath, exePath), isTrue);
    });

    test('matches unix path with arguments', () {
      expect(GameService.isProcessMatch('$exePath +set fs_game mymod', exePath),
          isTrue);
    });

    test('matches when it is an argument', () {
      const line =
          'launcher /home/me/.local/share/Steam/steamapps/common/Jedi Academy/GameData/eternaljk.x86_64';
      expect(GameService.isProcessMatch(line, exePath), isTrue);
    });

    test('matches basename-only command line', () {
      const line = 'eternaljk.x86_64 +set fs_game mymod';
      expect(GameService.isProcessMatch(line, exePath), isTrue);
    });

    test('does not match unrelated paths', () {
      expect(GameService.isProcessMatch('/usr/bin/some_other_process', exePath),
          isFalse);
      expect(GameService.isProcessMatch('some_other_process --flag', exePath), isFalse);
    });
  });
}
