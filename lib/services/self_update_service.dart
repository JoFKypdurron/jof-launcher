import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_manifest.dart';
import '../utils/version.dart';
import 'install_location_service.dart';
import 'self_update_installer.dart';
import 'settings_service.dart';
import 'update_feed_service.dart';

/// The outcome of an update check. Always safe to render; never an error.
class UpdateCheckResult {
  final bool updateAvailable;

  /// The running version, or null when this build cannot state its own version.
  final String? currentVersion;
  final String? availableVersion;

  /// Whether this install could replace itself in place. False means the user
  /// has to download manually — a .deb install, a translocated bundle, a
  /// read-only location.
  final bool selfUpdateEligible;

  /// Why self-update is unavailable, suitable for showing to the user.
  final String? ineligibilityReason;

  final String? downloadPageUrl;
  final UpdateArtifact? artifact;

  const UpdateCheckResult({
    this.updateAvailable = false,
    this.currentVersion,
    this.availableVersion,
    this.selfUpdateEligible = false,
    this.ineligibilityReason,
    this.downloadPageUrl,
    this.artifact,
  });

  static const UpdateCheckResult none = UpdateCheckResult();
}

/// Decides whether a newer launcher exists and whether this install could
/// apply it.
///
/// This phase only reports; nothing is downloaded or replaced.
class SelfUpdateService {
  /// Minimum gap between automatic checks.
  ///
  /// Short on purpose: the manifest is a few hundred bytes and edge-cached, so
  /// the only thing this guards against is a restart loop hammering the CDN.
  /// A long interval instead suppresses the *notice*, leaving someone who
  /// launches the day a release lands with no idea it exists.
  static const Duration checkInterval = Duration(minutes: 15);

  final UpdateFeedService _feed;
  final InstallLocationService _installLocation;
  final SettingsService _settings;
  final SelfUpdateInstaller _installer;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final DateTime Function() _now;

  SelfUpdateService({
    UpdateFeedService? feed,
    InstallLocationService? installLocation,
    SettingsService? settings,
    SelfUpdateInstaller? installer,
    Future<PackageInfo> Function()? packageInfoLoader,
    DateTime Function()? now,
  })  : _feed = feed ?? UpdateFeedService(),
        _installLocation = installLocation ?? InstallLocationService(),
        _settings = settings ?? SettingsService(),
        _installer = installer ?? SelfUpdateInstaller(),
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _now = now ?? DateTime.now;

  /// Checks for a newer release.
  ///
  /// Returns [UpdateCheckResult.none] for every failure mode — disabled by the
  /// user, checked too recently, offline, unparseable manifest, unknown local
  /// version. Update checking is background work and must never be able to
  /// break startup or surface an error.
  Future<UpdateCheckResult> checkForUpdate({bool force = false}) async {
    try {
      if (!force && !await _settings.getUpdateCheckEnabled()) {
        return UpdateCheckResult.none;
      }

      if (!force) {
        final last = await _settings.getUpdateLastCheckMs();
        final elapsed = _now().millisecondsSinceEpoch - last;
        if (last > 0 && elapsed < checkInterval.inMilliseconds) {
          return UpdateCheckResult.none;
        }
      }

      final info = await _packageInfoLoader();
      final current = info.version;

      // A build that cannot state its own version must not decide it is out of
      // date. Substituting a default here would make every release look like an
      // upgrade and update forever. This is not hypothetical: on Linux
      // package_info_plus returns an empty version when
      // data/flutter_assets/version.json is missing.
      if (tryParseVersion(current) == null) {
        return UpdateCheckResult.none;
      }

      final manifest = await _feed.fetchLatest();
      await _settings.setUpdateLastCheckMs(_now().millisecondsSinceEpoch);
      if (manifest == null) return UpdateCheckResult.none;

      if (!isNewerVersion(manifest.version, current)) {
        return UpdateCheckResult(currentVersion: current);
      }

      if (!force) {
        final skipped = await _settings.getUpdateSkippedVersion();
        if (skipped != null && compareVersions(skipped, manifest.version) == 0) {
          return UpdateCheckResult(currentVersion: current);
        }
      }

      final location = await _installLocation.detect();
      final artifact = location.artifactKind == null
          ? null
          : manifest.artifactFor(location.artifactKind!);

      // A manifest from a newer release process can still say "an update
      // exists", but must not be trusted to drive an install.
      final eligible = location.canSelfUpdate &&
          artifact != null &&
          manifest.isSupportedSchema;

      return UpdateCheckResult(
        updateAvailable: true,
        currentVersion: current,
        availableVersion: manifest.version,
        selfUpdateEligible: eligible,
        ineligibilityReason: eligible ? null : location.reason,
        downloadPageUrl: manifest.downloadPageUrl ?? manifest.notesUrl,
        artifact: artifact,
      );
    } catch (_) {
      return UpdateCheckResult.none;
    }
  }

  Future<void> skipVersion(String version) =>
      _settings.setUpdateSkippedVersion(version);

  /// Downloads and stages [result], then hands off to the swap helper.
  ///
  /// On success the caller must quit immediately: the helper is already
  /// waiting for this process to exit before it replaces the install.
  Future<InstallOutcome> applyUpdate(
    UpdateCheckResult result, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final artifact = result.artifact;
    final version = result.availableVersion;
    if (!result.selfUpdateEligible || artifact == null || version == null) {
      return InstallOutcome.failed(
          result.ineligibilityReason ?? 'This install cannot update itself.');
    }

    // Re-detected rather than reused from the check: the check may have run
    // minutes ago, and permissions or the install location can have changed.
    final location = await _installLocation.detect();
    if (!location.canSelfUpdate) {
      return InstallOutcome.failed(
          location.reason ?? 'This install cannot update itself.');
    }

    return _installer.install(
      artifact: artifact,
      expectedVersion: version,
      location: location,
      onProgress: onProgress,
      onStatus: onStatus,
      isCancelled: isCancelled,
    );
  }
}
