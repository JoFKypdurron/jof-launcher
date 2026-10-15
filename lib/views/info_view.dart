import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../services/log_service.dart';
import '../services/self_update_service.dart';
import '../theme/jof_tokens.dart';
import '../widgets/jof/jof_box.dart';
import '../widgets/jof/jof_primitives.dart';
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
  String? _logFilePath;
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
        _updateMessage =
            'Version ${result.availableVersion} is available.'
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
          _updateMessage =
              'Could not install automatically. '
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
            content: Text('Could not open the browser. Link copied.'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadLogFilePath();
  }

  // Separate from _loadInfo: resolving the log directory touches the file
  // system and must not hold up the rest of the screen.
  Future<void> _loadLogFilePath() async {
    final path = await LogService.instance.logFilePath();
    if (mounted && path != null) setState(() => _logFilePath = path);
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
        platformVersion =
            'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
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
        platformVersion =
            'Windows ${windowsInfo.displayVersion} (Build ${windowsInfo.buildNumber})';
      }
    } catch (e) {
      // Ignore errors in getting device info
    }

    if (mounted) {
      setState(() {
        _appName = packageInfo.appName.isEmpty
            ? 'JoF Launcher'
            : packageInfo.appName;
        _version = packageInfo.version.isEmpty ? '1.0.2' : packageInfo.version;
        _buildNumber = packageInfo.buildNumber.isEmpty
            ? '1'
            : packageInfo.buildNumber;
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
Log File: ${_logFilePath ?? 'Unavailable'}
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
    final about = JofBox(
      title: 'About',
      padded: false,
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: JofSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoItem('App Name', _appName),
              _buildInfoItem('Version', _version),
              _buildInfoItem('Build Number', _buildNumber),
              _buildInfoItem('Platform', _platform),
              _buildInfoItem('Platform Version', _platformVersion),
              _buildInfoItem('Dart Version', _dartVersion),
              _buildInfoItem(
                'Local Time',
                DateTime.now().toString(),
                last: true,
              ),
            ],
          ),
        ),
      ),
    );

    final updates = JofBox(
      title: 'Updates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_updateMessage != null) ...[
            Text(
              _updateMessage!,
              style: const TextStyle(color: JofColors.textMuted),
            ),
            const SizedBox(height: JofSpace.md),
          ],
          ElevatedButton.icon(
            key: checkForUpdatesButtonKey,
            onPressed: _isCheckingForUpdate ? null : _checkForUpdate,
            icon: _isCheckingForUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            label: Text(
              _isCheckingForUpdate ? 'CHECKING…' : 'CHECK FOR UPDATES',
            ),
          ),
        ],
      ),
    );

    final support = JofBox(
      title: 'Support',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_logFilePath != null) ...[
            const Text(
              'Log file',
              style: TextStyle(color: JofColors.textMuted),
            ),
            const SizedBox(height: JofSpace.xs),
            JofWell(
              child: SelectableText(
                _logFilePath!,
                style: JofText.caption.copyWith(color: JofColors.text),
              ),
            ),
            const SizedBox(height: JofSpace.sm),
          ],
          ElevatedButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy),
            label: const Text('COPY DEBUG INFO'),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: const JofTopBar(title: 'Information'),
      body: SingleChildScrollView(
        child: JofContent(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 800) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    about,
                    const SizedBox(height: JofSpace.lg),
                    updates,
                    const SizedBox(height: JofSpace.lg),
                    support,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: about),
                  const SizedBox(width: JofSpace.lg),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        updates,
                        const SizedBox(height: JofSpace.lg),
                        support,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: JofSpace.sm),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: JofColors.border,
                  width: JofSpace.xxs,
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label.toUpperCase(),
              style: JofText.buttonLabel.copyWith(color: JofColors.textMuted),
            ),
          ),
          const SizedBox(width: JofSpace.md),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
