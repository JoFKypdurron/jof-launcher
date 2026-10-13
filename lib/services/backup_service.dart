import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:minio/minio.dart';
import 'package:minio/models.dart' as minio_models;
import 'backup_encryption.dart';
import 'settings_service.dart';

class BackupFailure {
  final String filePath;
  final Object error;

  const BackupFailure({
    required this.filePath,
    required this.error,
  });
}

class BackupRunResult {
  final int attemptedFiles;
  final int uploadedFiles;
  final bool skipped;
  final List<BackupFailure> failures;

  const BackupRunResult({
    required this.attemptedFiles,
    required this.uploadedFiles,
    required this.skipped,
    required this.failures,
  });

  bool get hadFailures => failures.isNotEmpty;
}

class RemoteBackupFile {
  final String objectKey;
  final String filename;
  final DateTime? backedUpAt;

  const RemoteBackupFile({
    required this.objectKey,
    required this.filename,
    required this.backedUpAt,
  });
}

typedef BackupUploader = Future<void> Function({
  required File file,
  required String backupId,
  required String filename,
});

class BackupService {
  final SettingsService _settingsService;
  final BackupUploader _uploader;
  final bool Function() _isUploadAvailable;

  static const int _maxCfgFilesPerBackup = 1000;
  static const int _maxCfgFileSizeBytes = 30 * 1024; // 30 KB

  static const String _defaultBucket = 'jof-cloud';
  static const String _defaultRegion = 'eu-central-1';
  static const String _defaultEndpoint = 's3.eu-central-1.amazonaws.com';
  static const bool _defaultUseSSL = true;
  static const bool _defaultPathStyle = false;

  /// Whether cloud backup is offered at all.
  ///
  /// Off for now: the current implementation needs S3 credentials compiled into
  /// the binary, which is not something a public build can ship. The settings
  /// section is hidden and [runBackup] is a no-op until backups go through a
  /// server-side API instead. Stored settings and existing backups are left
  /// untouched. Tests flip this on to keep covering the feature.
  static bool featureEnabled = false;

  BackupService({
    SettingsService? settingsService,
    BackupUploader? uploader,
    bool Function()? isUploadAvailable,
  })  : _settingsService = settingsService ?? SettingsService(),
        _uploader = uploader ?? _defaultUploader,
        _isUploadAvailable =
            isUploadAvailable ?? (uploader == null ? _defaultIsUploadAvailable : _alwaysAvailable);

  Future<BackupRunResult> runBackup() async {
    final enabled = featureEnabled && await _settingsService.getEnableCloudBackup();
    if (!enabled) {
      return const BackupRunResult(
        attemptedFiles: 0,
        uploadedFiles: 0,
        skipped: true,
        failures: [],
      );
    }

    final gameDataPath = await _settingsService.getGameDataPath();
    if (gameDataPath == null) {
      return const BackupRunResult(
        attemptedFiles: 0,
        uploadedFiles: 0,
        skipped: true,
        failures: [],
      );
    }

    final backupId = await _settingsService.getCloudBackupId();
    if (backupId == null) {
      return const BackupRunResult(
        attemptedFiles: 0,
        uploadedFiles: 0,
        skipped: true,
        failures: [],
      );
    }

    // If backups are enabled but uploading is not currently possible (e.g. missing
    // credentials in the default uploader), treat the run as skipped to avoid
    // showing a persistent startup warning.
    if (!_isUploadAvailable()) {
      return const BackupRunResult(
        attemptedFiles: 0,
        uploadedFiles: 0,
        skipped: true,
        failures: [],
      );
    }

    final eternalJKPath = p.join(gameDataPath, 'EternalJK');
    final dir = Directory(eternalJKPath);
    if (!await dir.exists()) {
      return const BackupRunResult(
        attemptedFiles: 0,
        uploadedFiles: 0,
        skipped: true,
        failures: [],
      );
    }

    // Scan only .cfg files, not recursive
    final entities = await dir.list(recursive: false).toList();
    final cfgCandidates = entities
        .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.cfg'))
        .cast<File>()
        .toList();

    // Allow only max 1000 cfg files that are smaller than 30kb each.
    final cfgFiles = <File>[];
    for (final file in cfgCandidates) {
      if (cfgFiles.length >= _maxCfgFilesPerBackup) {
        break;
      }
      try {
        final size = await file.length();
        if (size < _maxCfgFileSizeBytes) {
          cfgFiles.add(file);
        }
      } catch (_) {
        // If we can't read the file size, skip it.
      }
    }

    var uploadedFiles = 0;
    final failures = <BackupFailure>[];

    for (final file in cfgFiles) {
      File? encryptedTemp;
      try {
        final plaintext = await file.readAsBytes();
        final encrypted = BackupEncryption.encryptBytes(
          plaintext: plaintext,
          backupId: backupId,
        );

        encryptedTemp = await _writeTempEncryptedFile(
          originalFile: file,
          encryptedBytes: encrypted,
        );

        await _uploader(
          file: encryptedTemp,
          backupId: backupId,
          filename: p.basename(file.path),
        );

        uploadedFiles++;
      } catch (e) {
        stderr.writeln('Failed to backup ${file.path}: $e');
        failures.add(BackupFailure(filePath: file.path, error: e));
      } finally {
        if (encryptedTemp != null) {
          try {
            await encryptedTemp.delete();
            final parentDir = encryptedTemp.parent;
            if (await parentDir.exists()) {
              await parentDir.delete(recursive: true);
            }
          } catch (_) {
            // ignore cleanup errors
          }
        }
      }
    }

    return BackupRunResult(
      attemptedFiles: cfgFiles.length,
      uploadedFiles: uploadedFiles,
      skipped: false,
      failures: failures,
    );
  }

  static Future<void> _defaultUploader({
    required File file,
    required String backupId,
    required String filename,
  }) async {
    final config = _readS3Config();
    final minio = _createMinio(config);

    final objectKey = _backupObjectKey(backupId: backupId, filename: filename);
    final size = await file.length();

    await minio.putObject(
      config.bucket,
      objectKey,
      file.openRead().map((chunk) => Uint8List.fromList(chunk)),
      size: size,
    );
  }

  static bool _defaultIsUploadAvailable() {
    try {
      _readS3Config();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _alwaysAvailable() => true;

  /// Lists uploaded backup files for the current `cloudBackupId`.
  ///
  /// Uses S3-compatible configuration from --dart-define or environment variables.
  Future<List<String>> listRemoteBackupFiles({required String backupId}) async {
    final config = _readS3Config();
    final minio = _createMinio(config);
    final prefix = _backupPrefix(backupId);

    final keys = <String>[];

    final stream = minio.listObjects(config.bucket, prefix: prefix, recursive: true);
    keys.addAll(await _collectRemoteBackupKeysFromListObjects(stream: stream, prefix: prefix));

    keys.sort();
    return keys;
  }

  /// Lists uploaded backup files along with their remote timestamps (when available).
  ///
  /// Uses S3-compatible configuration from --dart-define or environment variables.
  Future<List<RemoteBackupFile>> listRemoteBackupFileEntries({required String backupId}) async {
    final config = _readS3Config();
    final minio = _createMinio(config);
    final prefix = _backupPrefix(backupId);

    final stream = minio.listObjects(config.bucket, prefix: prefix, recursive: true);
    final items = await _collectRemoteBackupEntriesFromListObjects(stream: stream, prefix: prefix);

    items.sort((a, b) {
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
    return items;
  }

  @visibleForTesting
  static Future<List<String>> collectRemoteBackupKeysForTesting({
    required Stream<minio_models.ListObjectsResult> stream,
    required String prefix,
  }) =>
      _collectRemoteBackupKeysFromListObjects(stream: stream, prefix: prefix);

  @visibleForTesting
  static Future<List<RemoteBackupFile>> collectRemoteBackupEntriesForTesting({
    required Stream<minio_models.ListObjectsResult> stream,
    required String prefix,
  }) =>
      _collectRemoteBackupEntriesFromListObjects(stream: stream, prefix: prefix);

  static Future<List<String>> _collectRemoteBackupKeysFromListObjects({
    required Stream<minio_models.ListObjectsResult> stream,
    required String prefix,
  }) async {
    final keys = <String>[];
    await for (final chunk in stream) {
      for (final obj in chunk.objects) {
        final key = obj.key;
        if (key == null || key.isEmpty) continue;
        if (key.endsWith('/')) continue;
        if (!key.startsWith(prefix)) continue;
        keys.add(key);
      }
    }
    return keys;
  }

  static Future<List<RemoteBackupFile>> _collectRemoteBackupEntriesFromListObjects({
    required Stream<minio_models.ListObjectsResult> stream,
    required String prefix,
  }) async {
    final items = <RemoteBackupFile>[];
    await for (final chunk in stream) {
      for (final obj in chunk.objects) {
        final key = obj.key;
        if (key == null || key.isEmpty) continue;
        if (key.endsWith('/')) continue;
        if (!key.startsWith(prefix)) continue;

        final filename = key.substring(prefix.length);
        if (filename.isEmpty) continue;

        items.add(
          RemoteBackupFile(
            objectKey: key,
            filename: filename,
            backedUpAt: obj.lastModified,
          ),
        );
      }
    }
    return items;
  }

  /// Downloads a single remote backup file to `destinationFile`.
  ///
  /// Returns the downloaded file.
  Future<File> downloadRemoteBackupFile({
    required String backupId,
    required String filename,
    required File destinationFile,
  }) async {
    final config = _readS3Config();
    final minio = _createMinio(config);
    final objectKey = _backupObjectKey(backupId: backupId, filename: filename);

    final dynamic result = minio.getObject(config.bucket, objectKey);
    final Stream<List<int>> byteStream =
        result is Future ? await result as Stream<List<int>> : result as Stream<List<int>>;

    await destinationFile.parent.create(recursive: true);
    final sink = destinationFile.openWrite();
    await sink.addStream(byteStream);
    await sink.close();
    return destinationFile;
  }

  /// Restores a single remote backup file to `destinationFile` by downloading and decrypting it.
  ///
  /// Returns the written plaintext file.
  Future<File> restoreRemoteBackupFile({
    required String backupId,
    required String filename,
    required File destinationFile,
  }) async {
    final config = _readS3Config();
    final minio = _createMinio(config);
    final objectKey = _backupObjectKey(backupId: backupId, filename: filename);

    final dynamic result = minio.getObject(config.bucket, objectKey);
    final Stream<List<int>> byteStream =
        result is Future ? await result as Stream<List<int>> : result as Stream<List<int>>;

    final encryptedBytes = await _readAllBytes(byteStream);
    final plaintext = BackupEncryption.decryptBytes(
      encryptedBytes: encryptedBytes,
      backupId: backupId,
    );

    await destinationFile.parent.create(recursive: true);
    await destinationFile.writeAsBytes(plaintext, flush: true);
    return destinationFile;
  }

  static String restoredFilename(String filename) {
    final base = p.basename(filename);
    final ext = p.extension(base);
    final stem = p.basenameWithoutExtension(base);
    if (ext.isEmpty) {
      return '$stem-restored';
    }
    return '$stem-restored$ext';
  }

  static File resolveRestoreDestination({
    required Directory eternalJKDirectory,
    required String filename,
  }) {
    final safeName = p.basename(filename);
    var candidate = File(p.join(eternalJKDirectory.path, safeName));
    if (!candidate.existsSync()) return candidate;

    final base = restoredFilename(safeName);
    candidate = File(p.join(eternalJKDirectory.path, base));
    if (!candidate.existsSync()) return candidate;

    // Avoid overwriting an existing restored file.
    final ext = p.extension(base);
    final stem = p.basenameWithoutExtension(base);
    var i = 2;
    while (candidate.existsSync()) {
      final next = ext.isEmpty ? '$stem-$i' : '$stem-$i$ext';
      candidate = File(p.join(eternalJKDirectory.path, next));
      i++;
    }
    return candidate;
  }

  static _S3Config _readS3Config() {
    const defineAccessKey = String.fromEnvironment('AWS_ACCESS_KEY_ID');
    const defineSecretKey = String.fromEnvironment('AWS_SECRET_ACCESS_KEY');

    final accessKey = defineAccessKey.isNotEmpty ? defineAccessKey : Platform.environment['AWS_ACCESS_KEY_ID'];
    final secretKey = defineSecretKey.isNotEmpty ? defineSecretKey : Platform.environment['AWS_SECRET_ACCESS_KEY'];

    if (accessKey == null || accessKey.isEmpty || secretKey == null || secretKey.isEmpty) {
      throw Exception(
        'Backup cloud credentials not found. '
      );
    }

    const defineEndpoint = String.fromEnvironment('S3_ENDPOINT');
    const defineRegion = String.fromEnvironment('S3_REGION');
    const defineBucket = String.fromEnvironment('S3_BUCKET');

    final endpoint = (defineEndpoint.isNotEmpty ? defineEndpoint : (Platform.environment['S3_ENDPOINT'] ?? _defaultEndpoint)).trim();
    final region = (defineRegion.isNotEmpty ? defineRegion : (Platform.environment['S3_REGION'] ?? _defaultRegion)).trim();
    final bucket = (defineBucket.isNotEmpty ? defineBucket : (Platform.environment['S3_BUCKET'] ?? _defaultBucket)).trim();

    final useSSL = _readBoolConfig('S3_USE_SSL', defaultValue: _defaultUseSSL);
    final pathStyle = _readBoolConfig('S3_PATH_STYLE', defaultValue: _defaultPathStyle);

    if (endpoint.isEmpty) {
      throw Exception('S3 endpoint is empty. Set S3_ENDPOINT.');
    }
    if (bucket.isEmpty) {
      throw Exception('S3 bucket is empty. Set S3_BUCKET.');
    }

    return _S3Config(
      endPoint: endpoint,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      bucket: bucket,
      useSSL: useSSL,
      pathStyle: pathStyle,
    );
  }

  static bool _readBoolConfig(String key, {required bool defaultValue}) {
    final defineValue = String.fromEnvironment(key);
    if (defineValue.isNotEmpty) {
      return _parseBool(defineValue) ?? defaultValue;
    }

    final envValue = Platform.environment[key];
    if (envValue != null) {
      return _parseBool(envValue) ?? defaultValue;
    }

    return defaultValue;
  }

  static bool? _parseBool(String value) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'y':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'n':
      case 'off':
        return false;
      default:
        return null;
    }
  }

  static Minio _createMinio(_S3Config config) {
    return Minio(
      endPoint: config.endPoint,
      accessKey: config.accessKey,
      secretKey: config.secretKey,
      region: config.region,
      useSSL: config.useSSL,
      pathStyle: config.pathStyle,
    );
  }

  static String _backupPrefix(String backupId) => 'launcher-backups/$backupId/';

  static String _backupObjectKey({required String backupId, required String filename}) =>
      '${_backupPrefix(backupId)}$filename';

  static Future<Uint8List> _readAllBytes(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final c in stream) {
      chunks.addAll(c);
    }
    return Uint8List.fromList(chunks);
  }

  Future<File> _writeTempEncryptedFile({
    required File originalFile,
    required Uint8List encryptedBytes,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('jof_launcher_backup_');
    final tempFile = File(p.join(tempDir.path, '${p.basename(originalFile.path)}.enc'));
    await tempFile.writeAsBytes(encryptedBytes, flush: true);
    return tempFile;
  }
}

class _S3Config {
  final String endPoint;
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final bool useSSL;
  final bool pathStyle;

  const _S3Config({
    required this.endPoint,
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    required this.useSSL,
    required this.pathStyle,
  });
}
