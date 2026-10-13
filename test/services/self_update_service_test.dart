import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:joflauncher/models/update_manifest.dart';
import 'package:joflauncher/services/install_location_service.dart';
import 'package:joflauncher/services/self_update_service.dart';
import 'package:joflauncher/services/settings_service.dart';
import 'package:joflauncher/services/update_feed_service.dart';

class FakeFeed extends UpdateFeedService {
  final UpdateManifest? manifest;
  int calls = 0;
  FakeFeed(this.manifest);

  @override
  Future<UpdateManifest?> fetchLatest() async {
    calls++;
    return manifest;
  }
}

UpdateManifest manifestFor(String version, {int schema = 1}) => UpdateManifest(
      schema: schema,
      version: version,
      notesUrl: 'https://example.invalid/notes',
      downloadPageUrl: 'https://example.invalid/download',
      artifacts: {
        UpdateArtifactKind.macos:
            UpdateArtifact(url: 'https://x.invalid/a.dmg', sha256: 'a' * 64, size: 1),
        UpdateArtifactKind.linuxTar:
            UpdateArtifact(url: 'https://x.invalid/a.tgz', sha256: 'b' * 64, size: 1),
        UpdateArtifactKind.linuxDeb:
            UpdateArtifact(url: 'https://x.invalid/a.deb', sha256: 'c' * 64, size: 1),
      },
    );

PackageInfo packageInfo(String version) => PackageInfo(
      appName: 'JoF Launcher',
      packageName: 'eu.jofhub.launcher',
      version: version,
      buildNumber: version,
    );

const _macApp = '/Applications/JoF Launcher.app/Contents/MacOS/JoF Launcher';
const _linuxDeb = '/opt/jof-launcher/jof-launcher';

SelfUpdateService buildService({
  required String currentVersion,
  UpdateManifest? manifest,
  String executable = _macApp,
  String os = 'macos',
  bool writable = true,
  UpdateFeedService? feed,
}) {
  return SelfUpdateService(
    feed: feed ?? FakeFeed(manifest),
    installLocation: InstallLocationService(
      resolvedExecutableOverride: executable,
      environmentOverride: const {},
      writabilityProbe: (_) async => writable,
      isReleaseModeOverride: true,
      osOverride: os,
    ),
    settings: SettingsService(),
    packageInfoLoader: () async => packageInfo(currentVersion),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offers an update when the published version is newer', () async {
    final result = await buildService(
      currentVersion: '1.1.8',
      manifest: manifestFor('1.1.9'),
    ).checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.availableVersion, '1.1.9');
    expect(result.currentVersion, '1.1.8');
    expect(result.selfUpdateEligible, isTrue);
    expect(result.downloadPageUrl, 'https://example.invalid/download');
  });

  test('offers nothing when already current or ahead', () async {
    expect(
      (await buildService(currentVersion: '1.1.9', manifest: manifestFor('1.1.9'))
              .checkForUpdate())
          .updateAvailable,
      isFalse,
    );
    expect(
      (await buildService(currentVersion: '1.2.0', manifest: manifestFor('1.1.9'))
              .checkForUpdate())
          .updateAvailable,
      isFalse,
    );
  });

  // The load-bearing safety property. On Linux package_info_plus returns an
  // empty version when version.json is missing — exactly the state a
  // half-applied update leaves behind. Treating that as "very old" would offer
  // an update forever.
  test('refuses to decide when the running version is unknown', () async {
    final feed = FakeFeed(manifestFor('9.9.9'));
    final result = await buildService(
      currentVersion: '',
      feed: feed,
    ).checkForUpdate();

    expect(result.updateAvailable, isFalse);
    expect(result.currentVersion, isNull);
    expect(feed.calls, 0, reason: 'should bail before even asking the feed');
  });

  test('a .deb install is told about updates but cannot self-update', () async {
    final result = await buildService(
      currentVersion: '1.1.8',
      manifest: manifestFor('1.1.9'),
      executable: _linuxDeb,
      os: 'linux',
    ).checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.selfUpdateEligible, isFalse);
    expect(result.ineligibilityReason, contains('.deb'));
  });

  test('an unwritable install is told about updates but cannot self-update',
      () async {
    final result = await buildService(
      currentVersion: '1.1.8',
      manifest: manifestFor('1.1.9'),
      writable: false,
    ).checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.selfUpdateEligible, isFalse);
  });

  test('a newer manifest schema notifies but never drives an install', () async {
    final result = await buildService(
      currentVersion: '1.1.8',
      manifest: manifestFor('1.1.9', schema: 99),
    ).checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.selfUpdateEligible, isFalse);
  });

  test('no update is offered when the feed is unreachable', () async {
    final result =
        await buildService(currentVersion: '1.1.8', manifest: null).checkForUpdate();
    expect(result.updateAvailable, isFalse);
  });

  test('the disabled setting suppresses automatic checks but not forced ones',
      () async {
    SharedPreferences.setMockInitialValues({'update_check_enabled': false});
    final feed = FakeFeed(manifestFor('1.1.9'));
    final svc = buildService(currentVersion: '1.1.8', feed: feed);

    expect((await svc.checkForUpdate()).updateAvailable, isFalse);
    expect(feed.calls, 0);

    expect((await svc.checkForUpdate(force: true)).updateAvailable, isTrue);
  });

  test('a skipped version is suppressed', () async {
    SharedPreferences.setMockInitialValues({'update_skipped_version': '1.1.9'});
    expect(
      (await buildService(currentVersion: '1.1.8', manifest: manifestFor('1.1.9'))
              .checkForUpdate())
          .updateAvailable,
      isFalse,
    );
  });

  test('skipping one version does not hide the next', () async {
    // Reset rather than reusing the previous case: a completed check writes the
    // debounce timestamp, which would suppress the second call for 6h.
    SharedPreferences.setMockInitialValues({'update_skipped_version': '1.1.9'});
    expect(
      (await buildService(currentVersion: '1.1.8', manifest: manifestFor('1.2.0'))
              .checkForUpdate())
          .updateAvailable,
      isTrue,
    );
  });

  test('checks are debounced, and force overrides the debounce', () async {
    final justNow = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'update_last_check_ms': justNow});

    final feed = FakeFeed(manifestFor('1.1.9'));
    final svc = buildService(currentVersion: '1.1.8', feed: feed);

    expect((await svc.checkForUpdate()).updateAvailable, isFalse);
    expect(feed.calls, 0);

    expect((await svc.checkForUpdate(force: true)).updateAvailable, isTrue);
    expect(feed.calls, 1);
  });
}
