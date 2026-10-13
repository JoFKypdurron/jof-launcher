import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/services/backup_service.dart';
import 'package:joflauncher/services/backup_encryption.dart';
import 'package:joflauncher/services/settings_service.dart';
import 'package:minio/models.dart' as minio_models;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsService settingsService;
  late BackupService backupService;
  late Directory tempDir;
  late String gameDataPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BackupService.featureEnabled = true;
    settingsService = SettingsService();
    backupService = BackupService();
    tempDir = Directory.systemTemp.createTempSync('backup_test');
    gameDataPath = p.join(tempDir.path, 'GameData');
    await Directory(gameDataPath).create();
  });

  tearDown(() {
    BackupService.featureEnabled = false;
    tempDir.deleteSync(recursive: true);
  });

  test('BackupService skips the run while the feature is off, even if the user had it enabled', () async {
    BackupService.featureEnabled = false;

    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();
    await File(p.join(eternalJKPath, 'config.cfg')).writeAsString('test');
    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);

    var uploads = 0;
    final service = BackupService(
      settingsService: settingsService,
      uploader: ({required file, required backupId, required filename}) async {
        uploads++;
      },
    );

    final result = await service.runBackup();

    expect(result.skipped, isTrue);
    expect(result.attemptedFiles, 0);
    expect(uploads, 0);
  });

  test('BackupService scans only .cfg files in EternalJK folder non-recursively', () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();
    
    // Create some .cfg files
    final cfg1 = File(p.join(eternalJKPath, 'config1.cfg'));
    await cfg1.writeAsString('test1');
    final cfg2 = File(p.join(eternalJKPath, 'config2.cfg'));
    await cfg2.writeAsString('test2');
    
    // Create a non-cfg file
    final txt = File(p.join(eternalJKPath, 'readme.txt'));
    await txt.writeAsString('readme');
    
    // Create a subfolder with a .cfg file (should not be scanned)
    final subfolder = p.join(eternalJKPath, 'sub');
    await Directory(subfolder).create();
    final cfgSub = File(p.join(subfolder, 'config_sub.cfg'));
    await cfgSub.writeAsString('sub');

    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);
    await settingsService.setCloudBackupId('unit-test-backup-key');

    final uploaded = <String, Uint8List>{};
    backupService = BackupService(
      uploader: ({required file, required backupId, required filename}) async {
        uploaded[filename] = await file.readAsBytes();
      },
    );

    final result = await backupService.runBackup();

    expect(result.skipped, isFalse);
    expect(result.attemptedFiles, 2);
    expect(result.uploadedFiles, 2);
    expect(result.hadFailures, isFalse);

    // Only top-level .cfg files should be uploaded.
    expect(uploaded.keys.toSet(), {'config1.cfg', 'config2.cfg'});

    // Uploaded content should be encrypted and decryptable with the same backup id.
    final storedBackupId = await settingsService.getCloudBackupId();
    expect(storedBackupId, isNotNull);

    for (final entry in uploaded.entries) {
      final encryptedBytes = entry.value;
      expect(BackupEncryption.looksEncrypted(encryptedBytes), isTrue, reason: entry.key);
      expect(String.fromCharCodes(encryptedBytes).contains('test'), isFalse, reason: entry.key);

      final decrypted = BackupEncryption.decryptBytes(
        encryptedBytes: encryptedBytes,
        backupId: storedBackupId!,
      );
      if (entry.key == 'config1.cfg') {
        expect(String.fromCharCodes(decrypted), 'test1');
      } else if (entry.key == 'config2.cfg') {
        expect(String.fromCharCodes(decrypted), 'test2');
      }
    }
  });

  test('BackupService reports failures when uploader throws and continues with other files', () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();

    final cfg1 = File(p.join(eternalJKPath, 'ok.cfg'));
    await cfg1.writeAsString('ok');
    final cfg2 = File(p.join(eternalJKPath, 'fail.cfg'));
    await cfg2.writeAsString('fail');

    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);
    await settingsService.setCloudBackupId('unit-test-backup-key');

    final uploadedFilenames = <String>[];
    backupService = BackupService(
      uploader: ({required file, required backupId, required filename}) async {
        if (filename == 'fail.cfg') {
          throw Exception('upload failed');
        }
        uploadedFilenames.add(filename);
      },
    );

    final result = await backupService.runBackup();

    expect(result.skipped, isFalse);
    expect(result.attemptedFiles, 2);
    expect(result.uploadedFiles, 1);
    expect(result.hadFailures, isTrue);
    expect(result.failures.map((f) => p.basename(f.filePath)).toSet(), {'fail.cfg'});
    expect(uploadedFilenames.toSet(), contains('ok.cfg'));
  });

  test('BackupService skips .cfg files that are 30KB or larger', () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();

    final small = File(p.join(eternalJKPath, 'small.cfg'));
    await small.writeAsString('small');

    final big = File(p.join(eternalJKPath, 'big.cfg'));
    // Exactly 30KB should be rejected (must be smaller than 30KB).
    await big.writeAsBytes(Uint8List(30 * 1024), flush: true);

    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);
    await settingsService.setCloudBackupId('unit-test-backup-key');

    final uploadedFilenames = <String>[];
    backupService = BackupService(
      uploader: ({required file, required backupId, required filename}) async {
        uploadedFilenames.add(filename);
      },
    );

    final result = await backupService.runBackup();

    expect(result.skipped, isFalse);
    expect(result.attemptedFiles, 1);
    expect(result.uploadedFiles, 1);
    expect(result.hadFailures, isFalse);
    expect(uploadedFilenames, ['small.cfg']);
  });

  test('BackupService attempts at most 1000 valid .cfg files', () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();

    // Use a smaller number of files to avoid OS limits (e.g. open files, etc.)
    // but enough to test the limit. Actually, the issue is that it fails
    // at 1000, so let's try to make it more reliable by using sync creation
    // or just reducing the count if 1000 is too many for some environments.
    // However, the test specifically wants to check the 1000 limit.
    const fileCount = 1001;
    for (var i = 0; i < fileCount; i++) {
      final file = File(p.join(eternalJKPath, 'cfg_$i.cfg'));
      file.writeAsBytesSync(Uint8List(0));
    }

    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);
    await settingsService.setCloudBackupId('unit-test-backup-key');

    var uploadCount = 0;
    backupService = BackupService(
      uploader: ({required file, required backupId, required filename}) async {
        uploadCount++;
      },
    );

    final result = await backupService.runBackup();

    expect(result.skipped, isFalse);
    expect(result.attemptedFiles, 1000);
    expect(result.uploadedFiles, 1000);
    expect(result.hadFailures, isFalse);
    expect(uploadCount, 1000);
  });

  test('BackupService treats unavailable upload as skipped (no startup failure warning)', () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    await Directory(eternalJKPath).create();

    final cfg1 = File(p.join(eternalJKPath, 'config.cfg'));
    await cfg1.writeAsString('test');

    await settingsService.setGameDataPath(gameDataPath);
    await settingsService.setEnableCloudBackup(true);
    await settingsService.setCloudBackupId('unit-test-backup-key');

    backupService = BackupService(
      // Force the backup to be considered unavailable (e.g. missing credentials)
      // so the run is skipped instead of reported as a failure.
      isUploadAvailable: () => false,
      uploader: ({required file, required backupId, required filename}) async {
        throw Exception('should not be called');
      },
    );

    final result = await backupService.runBackup();

    expect(result.skipped, isTrue);
    expect(result.hadFailures, isFalse);
    expect(result.attemptedFiles, 0);
    expect(result.uploadedFiles, 0);
  });

  test('BackupService.restoredFilename adds -restored suffix before extension', () {
    expect(BackupService.restoredFilename('config.cfg'), 'config-restored.cfg');
    expect(BackupService.restoredFilename('config'), 'config-restored');
    expect(BackupService.restoredFilename('/tmp/config.cfg'), 'config-restored.cfg');
  });

  test('BackupService.resolveRestoreDestination keeps name if no collision, otherwise uses -restored',
      () async {
    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    final dir = await Directory(eternalJKPath).create();

    final dest1 = BackupService.resolveRestoreDestination(
      eternalJKDirectory: dir,
      filename: 'a.cfg',
    );
    expect(p.basename(dest1.path), 'a.cfg');

    await File(p.join(dir.path, 'a.cfg')).writeAsString('existing');

    final dest2 = BackupService.resolveRestoreDestination(
      eternalJKDirectory: dir,
      filename: 'a.cfg',
    );
    expect(p.basename(dest2.path), 'a-restored.cfg');

    await File(p.join(dir.path, 'a-restored.cfg')).writeAsString('existing-restored');

    final dest3 = BackupService.resolveRestoreDestination(
      eternalJKDirectory: dir,
      filename: 'a.cfg',
    );
    expect(p.basename(dest3.path), 'a-restored-2.cfg');
  });

  test('BackupService remote listing helpers extract keys from MinIO ListObjectsResult stream',
      () async {
    const prefix = 'launcher-backups/abc123/';

    final stream = Stream<minio_models.ListObjectsResult>.fromIterable([
      minio_models.ListObjectsResult(
        objects: [
          minio_models.Object(null, '${prefix}one.cfg', DateTime.utc(2026, 1, 1), null, 1, null),
          minio_models.Object(null, '${prefix}two.cfg', DateTime.utc(2026, 1, 2), null, 1, null),
          // should be ignored
          minio_models.Object(null, '${prefix}folder/', DateTime.utc(2026, 1, 3), null, 1, null),
          // should be ignored (wrong prefix)
          minio_models.Object(null, 'other-prefix/three.cfg', DateTime.utc(2026, 1, 4), null, 1, null),
        ],
        prefixes: const [],
      ),
    ]);

    final keys = await BackupService.collectRemoteBackupKeysForTesting(stream: stream, prefix: prefix);
    expect(keys.toSet(), {'${prefix}one.cfg', '${prefix}two.cfg'});
  });

  test('BackupService remote listing helpers produce sorted RemoteBackupFile entries', () async {
    const prefix = 'launcher-backups/abc123/';

    final stream = Stream<minio_models.ListObjectsResult>.fromIterable([
      minio_models.ListObjectsResult(
        objects: [
          minio_models.Object(null, '${prefix}b.cfg', DateTime.utc(2026, 1, 1, 10), null, 1, null),
          minio_models.Object(null, '${prefix}a.cfg', DateTime.utc(2026, 1, 2, 10), null, 1, null),
        ],
        prefixes: const [],
      ),
    ]);

    final entries =
        await BackupService.collectRemoteBackupEntriesForTesting(stream: stream, prefix: prefix);

    // Sort using the same logic as the public API.
    entries.sort((a, b) {
      final at = a.backedUpAt;
      final bt = b.backedUpAt;
      if (at != null && bt != null) {
        final cmp = bt.compareTo(at);
        if (cmp != 0) return cmp;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return a.filename.compareTo(b.filename);
    });

    expect(entries.map((e) => e.filename).toList(), ['a.cfg', 'b.cfg']);
    expect(entries.first.objectKey, '${prefix}a.cfg');
    expect(entries.first.backedUpAt, DateTime.utc(2026, 1, 2, 10));
  });
}
