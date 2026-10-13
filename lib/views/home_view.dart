import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../controllers/home_view_controller.dart';
import '../services/sync_status_service.dart';
import '../widgets/color_tokenized_text.dart';
import '../widgets/bottom_status_bar.dart';
import 'assets_view.dart';
import 'settings_view.dart';
import 'info_view.dart';

class HomeView extends StatefulWidget {
  final HomeViewController? controller;
  final bool initializeOnStart;

  const HomeView({
    super.key,
    this.controller,
    this.initializeOnStart = true,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeViewController _controller;
  bool _dismissedBackupWarning = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        HomeViewController(
          onStateChanged: () {
            if (mounted) setState(() {});
          },
        );
    SyncStatusService.instance.addListener(_onSyncStatusChanged);
    if (widget.initializeOnStart) {
      _controller.initialize();
    }
  }

  void _onSyncStatusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SyncStatusService.instance.removeListener(_onSyncStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = screenWidth < 600 ? 250.0 : 300.0;

    final isVertical = screenWidth < 800;

    final showBackupWarning =
        (_controller.lastBackupResult?.hadFailures ?? false) &&
        !(_controller.lastBackupResult?.skipped ?? true) &&
        !_dismissedBackupWarning;

    final showAccessWarning = !_controller.isGameDataPathAccessible;

    final syncStatus = SyncStatusService.instance;

    final bottomStatusBars = <Widget>[];
    if (syncStatus.isActive) {
      bottomStatusBars.add(
        BottomStatusBar(
          icon: Icons.sync,
          message: syncStatus.message,
          progress: syncStatus.progress,
          overallProgress: syncStatus.overallProgress,
          counterText: syncStatus.queueLabel,
          severity: BottomStatusSeverity.info,
        ),
      );
    }
    if (showAccessWarning) {
      bottomStatusBars.add(
        BottomStatusBar(
          icon: Icons.folder_off,
          message: 'GameData directory is not accessible. Click to re-select.',
          severity: BottomStatusSeverity.error,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SettingsView()),
            );
            _controller.checkAndSyncAssets();
          },
        ),
      );
    }
    if (showBackupWarning) {
      bottomStatusBars.add(
        BottomStatusBar(
          icon: Icons.cloud_off,
          message:
              'Cloud backup failed for ${_controller.lastBackupResult!.failures.length} file(s).',
          severity: BottomStatusSeverity.warning,
          onClose: () {
            setState(() {
              _dismissedBackupWarning = true;
            });
          },
        ),
      );
    }
    if (_controller.hasUpdateNotice) {
      final update = _controller.updateCheckResult!;
      final applying = _controller.isApplyingUpdate;
      final error = _controller.updateError;

      final String message;
      if (error != null) {
        message = error;
      } else if (applying) {
        message = _controller.updateStatus;
      } else if (update.selfUpdateEligible) {
        message =
            'Launcher ${update.availableVersion} is available. Click to install and restart.';
      } else {
        message =
            'Launcher ${update.availableVersion} is available. Click to open the download page.';
      }

      bottomStatusBars.add(
        BottomStatusBar(
          icon: Icons.system_update_alt,
          message: message,
          severity: error != null
              ? BottomStatusSeverity.warning
              : BottomStatusSeverity.info,
          progress: applying ? _controller.updateProgress : null,
          onTap: applying
              ? null
              : () async {
                  if (update.selfUpdateEligible && error == null) {
                    final applied = await _controller.applyLauncherUpdate();
                    // On success the app is quitting; only fall back to the
                    // browser if the install refused or failed.
                    if (applied) return;
                  }
                  final opened = await _controller.openUpdateDownloadPage();
                  if (!opened && context.mounted) {
                    final url = update.downloadPageUrl;
                    if (url != null) {
                      await Clipboard.setData(ClipboardData(text: url));
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Could not open the browser. Link copied.')),
                      );
                    }
                  }
                },
          onClose: applying
              ? null
              : () {
                  setState(_controller.dismissUpdateNotice);
                },
        ),
      );
    }

    Widget launchControls = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Connect to public server checkbox and Launch button in different rows
        SizedBox(
          width: buttonWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CheckboxListTile(
                title: const Text('Connect to public server'),
                value: _controller.connectToPublic,
                onChanged: (_controller.isLaunching ||
                        syncStatus.isActive ||
                        _controller.isGameRunning)
                    ? null
                    : (bool? value) async {
                        if (value != null) {
                          await _controller.setConnectToPublic(value);
                        }
                      },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: (_controller.isLaunching ||
                        syncStatus.isActive ||
                        _controller.isGameRunning)
                    ? null
                    : () => _controller.launchGame(context),
                icon: Icon(
                    _controller.isGameRunning
                        ? Icons.check_circle
                        : Icons.play_arrow,
                    size: 32),
                label: Text(_controller.isLaunching
                    ? 'Launching'
                    : _controller.isGameRunning
                        ? 'Game running'
                        : 'Launch Game'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    textStyle: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                    fixedSize: Size(buttonWidth, 60)),
              ),
            ],
          ),
        ),
      ],
    );

    Widget playerList = _controller.trackerData == null
        ? const Center(
            child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ))
        : _controller.trackerData!.players.isEmpty
            ? const Center(
                child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No players online'),
              ))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _controller.trackerData!.players.length,
                shrinkWrap: isVertical,
                physics:
                    isVertical ? const NeverScrollableScrollPhysics() : null,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 2.0,
                    ),
                    child: ColorTokenizedText(
                      text: _controller.trackerData!.players[index],
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                },
              );

    Widget serverStatusCard = Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF03273C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: isVertical ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // Server status section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Stack(
              children: [
                Column(
                  children: [
                    if (_controller.trackerData != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _controller.trackerData!.online
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _controller.trackerData!.online
                                ? 'ONLINE'
                                : 'OFFLINE',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_controller.trackerData!.online) ...[
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            Text(
                                'Map: ${_controller.trackerData!.map ?? 'Unknown'}'),
                            Text(
                                'Players: ${_controller.trackerData!.clients} / ${_controller.trackerData!.maxClients}'),
                          ],
                        ),
                      ],
                    ] else
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => _controller.refreshTrackerData(),
                    tooltip: 'Refresh status',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Players section
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'PLAYERS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          isVertical ? playerList : Expanded(child: playerList),
        ],
      ),
    );

    Widget content = Flex(
      direction: isVertical ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment:
          isVertical ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      children: [
        // Left side: Launch controls
        isVertical
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: launchControls,
              )
            : Flexible(
                flex: 2,
                fit: FlexFit.tight,
                child: Center(
                  child: SingleChildScrollView(
                    child: launchControls,
                  ),
                ),
              ),
        // Right side: Server status and Player list
        isVertical
            ? serverStatusCard
            : Expanded(
                flex: 1,
                child: serverStatusCard,
              ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF03273C),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/jof_logo.png'),
        ),
        title: const Text('JoF Launcher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory), // Icon for Assets
            tooltip: 'Manage Assets',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AssetsView()),
              );
              _controller.checkAndSyncAssets();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsView()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Information',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => InfoView(
                    onInstallUpdate: _controller.applyLauncherUpdate,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: isVertical ? SingleChildScrollView(child: content) : content,
      bottomNavigationBar: bottomStatusBars.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: bottomStatusBars,
            ),
    );
  }
}
