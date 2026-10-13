import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/cloud_service.dart';

void main() {
  group('CloudService.resolveExtractTargetPath', () {
    const gameDataPath = '/game/GameData';

    test('maps EternalJK/ entries under EternalJK', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'EternalJK/uix86_64.so',
        baseFolderName: 'base',
      );
      expect(path, '/game/GameData/EternalJK/uix86_64.so');
    });

    test('maps GameData/ entries to gameDataPath root', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'GameData/eternaljk.x86_64',
        baseFolderName: 'base',
      );
      expect(path, '/game/GameData/eternaljk.x86_64');
    });

    test('maps base/ entries into the configured base folder name', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'base/jof.pk3',
        baseFolderName: 'Base',
      );
      expect(path, '/game/GameData/Base/jof.pk3');
    });

    test('maps Base/ entries into the configured base folder name', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'Base/jof.pk3',
        baseFolderName: 'base',
      );
      expect(path, '/game/GameData/base/jof.pk3');
    });

    test('does not special-case root base* filenames', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'base_assets.pk3',
        baseFolderName: 'base',
      );
      expect(path, '/game/GameData/base_assets.pk3');
    });

    test('leaves other root filenames at gameDataPath root', () {
      final path = CloudService.resolveExtractTargetPath(
        gameDataPath: gameDataPath,
        filename: 'eternaljk.x86_64',
        baseFolderName: 'base',
      );
      expect(path, '/game/GameData/eternaljk.x86_64');
    });

    test('rejects a root-level traversal entry', () {
      expect(
        () => CloudService.resolveExtractTargetPath(
          gameDataPath: gameDataPath,
          filename: '../evil.txt',
          baseFolderName: 'base',
        ),
        throwsFormatException,
      );
    });

    test('rejects a base/ entry that traverses above gameDataPath', () {
      expect(
        () => CloudService.resolveExtractTargetPath(
          gameDataPath: gameDataPath,
          filename: 'base/../../evil.txt',
          baseFolderName: 'base',
        ),
        throwsFormatException,
      );
    });

    test('rejects an EternalJK/ entry that traverses above gameDataPath', () {
      expect(
        () => CloudService.resolveExtractTargetPath(
          gameDataPath: gameDataPath,
          filename: 'EternalJK/../../evil',
          baseFolderName: 'base',
        ),
        throwsFormatException,
      );
    });
  });
}
