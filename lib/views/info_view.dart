import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/self_update_service.dart';
import '../services/url_opener_service.dart';

const Key checkForUpdatesButtonKey = Key('info_check_for_updates');

class InfoView extends StatefulWidget {
  final SelfUpdateService? selfUpdateService;
  final UrlOpenerService? urlOpener;

  /// Installs the pending update, returning false if it could not be applied.
  ///
  /// Supplied by the home screen so installing from here goes through the same
  /// controller as the banner, keeping the "not while a sync or the game is
  /// running" guards. Without it this screen can only link to the release page.
  final Future<bool> Function()? onInstallUpdate;

  const InfoView({
    super.key,
    this.selfUpdateService,
    this.urlOpener,
    this.onInstallUpdate,
  });

  @override
  State<InfoView> createState() => _InfoViewState();
}

class _InfoViewState extends State<InfoView> {
  String _appName = 'Unknown';
  String _version = 'Unknown';
  String _buildNumber = 'Unknown';
  String _platform = 'Unknown';
  String _platformVersion = 'Unknown';
  final String _dartVersion = Platform.version;

  late final SelfUpdateService _selfUpdateService =
      widget.selfUpdateService ?? SelfUpdateService();
  late final UrlOpenerService _urlOpener =
      widget.urlOpener ?? UrlOpenerService();

  bool _isCheckingForUpdate = false;
  String? _updateMessage;
  String? _updateDownloadUrl;

  /// Forced, so it bypasses both the 6h debounce and any skipped version —
  /// pressing the button should always actually ask.
  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingForUpdate = true;
      _updateMessage = null;
      _updateDownloadUrl = null;
    });

    final result = await _selfUpdateService.checkForUpdate(force: true);
    if (!mounted) return;

    final canInstallHere =
        result.selfUpdateEligible && widget.onInstallUpdate != null;

    setState(() {
      _isCheckingForUpdate = false;
      _updateDownloadUrl = result.downloadPageUrl;
      if (!result.updateAvailable) {
        _updateMessage = result.currentVersion == null
            ? 'This build cannot report its own version, so updates cannot be checked.'
            : 'You are up to date.';
      } else if (canInstallHere) {
        _updateMessage =
            'Version ${result.availableVersion} is available. Installing…';
      } else {
        _updateMessage = 'Version ${result.availableVersion} is available.'
            '${result.ineligibilityReason == null ? '' : '\n${result.ineligibilityReason}'}'
            '\nOpening the download page…';
      }
    });

    if (!result.updateAvailable) return;

    // Install in place when we can. Falling straight through to the browser
    // here is what made this button useless on installs that could have
    // updated themselves.
    if (canInstallHere) {
      final applied = await widget.onInstallUpdate!();
      if (applied) return; // The app is quitting; the helper takes over.
      if (mounted) {
        setState(() {
          _updateMessage = 'Could not install automatically. '
              'Opening the download page…';
        });
      }
    }

    final url = _updateDownloadUrl;
    if (url == null) return;
    final opened = await _urlOpener.open(url);
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open the browser. Link copied.')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();

    String platformVersion = 'Unknown';
    try {
      if (kDebugMode && Platform.environment.containsKey('FLUTTER_TEST')) {
        // Skip in tests to avoid hanging on missing platform services
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        platformVersion = 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        platformVersion = 'iOS ${iosInfo.systemVersion}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        platformVersion = linuxInfo.prettyName;
      } else if (Platform.isMacOS) {
        final macosInfo = await deviceInfo.macOsInfo;
        platformVersion = 'macOS ${macosInfo.osRelease}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        platformVersion = 'Windows ${windowsInfo.displayVersion} (Build ${windowsInfo.buildNumber})';
      }
    } catch (e) {
      // Ignore errors in getting device info
    }

    if (mounted) {
      setState(() {
        _appName = packageInfo.appName.isEmpty ? 'JoF Launcher' : packageInfo.appName;
        _version = packageInfo.version.isEmpty ? '1.0.2' : packageInfo.version;
        _buildNumber = packageInfo.buildNumber.isEmpty ? '1' : packageInfo.buildNumber;
        _platform = Platform.operatingSystem;
        _platformVersion = platformVersion;
      });
    }
  }

  String _getDebugInfo() {
    return '''
App Name: $_appName
Version: $_version
Build Number: $_buildNumber
Platform: $_platform
Platform Version: $_platformVersion
Dart Version: $_dartVersion
Local Time: ${DateTime.now()}
''';
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _getDebugInfo()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Debug info copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Information'),
        backgroundColor: const Color(0xFF03273C),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoItem('App Name', _appName),
            _buildInfoItem('Version', _version),
            _buildInfoItem('Build Number', _buildNumber),
            _buildInfoItem('Platform', _platform),
            _buildInfoItem('Platform Version', _platformVersion),
            _buildInfoItem('Dart Version', _dartVersion),
            _buildInfoItem('Local Time', DateTime.now().toString()),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Debug Info'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                key: checkForUpdatesButtonKey,
                onPressed: _isCheckingForUpdate ? null : _checkForUpdate,
                icon: _isCheckingForUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt),
                label: Text(_isCheckingForUpdate
                    ? 'Checking…'
                    : 'Check for Updates'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            if (_updateMessage != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _updateMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
