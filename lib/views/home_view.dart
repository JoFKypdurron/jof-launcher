import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../controllers/home_view_controller.dart';
import '../services/sync_status_service.dart';
import '../widgets/color_tokenized_text.dart';
import '../widgets/bottom_status_bar.dart';
import '../widgets/jof/jof_box.dart';
import '../widgets/jof/jof_primitives.dart';
import '../theme/jof_tokens.dart';
import 'assets_view.dart';
import 'settings_view.dart';
import 'info_view.dart';

class HomeView extends StatefulWidget {
  final HomeViewController? controller;
  final bool initializeOnStart;

  const HomeView({super.key, this.controller, this.initializeOnStart = true});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeViewController _controller;
  bool _dismissedBackupWarning = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
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
                          content: Text(
                            'Could not open the browser. Link copied.',
                          ),
                        ),
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

    final launchBlocked =
        _controller.isLaunching ||
        syncStatus.isActive ||
        _controller.isGameRunning;

    return Scaffold(
      appBar: JofTopBar(
        title: 'JoF Launcher',
        leading: Padding(
          padding: const EdgeInsets.only(left: JofSpace.sm),
          child: Image.asset(
            'assets/jof_logo.png',
            width: 36,
            height: 36,
            semanticLabel: 'JoF',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Manage assets',
            onPressed: _openAssets,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final playBox = _buildPlayBox(syncStatus, launchBlocked);
          final assetsBox = _buildAssetsBox();

          if (constraints.maxWidth < _twoColumnBreakpoint) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(JofSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  playBox,
                  const SizedBox(height: JofSpace.lg),
                  assetsBox,
                  const SizedBox(height: JofSpace.lg),
                  _buildServerBox(expand: false),
                ],
              ),
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Padding(
                padding: const EdgeInsets.all(JofSpace.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            playBox,
                            const SizedBox(height: JofSpace.lg),
                            assetsBox,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: JofSpace.lg),
                    Expanded(child: _buildServerBox(expand: true)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: bottomStatusBars.isEmpty
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: bottomStatusBars),
    );
  }

  static const double _twoColumnBreakpoint = 900;

  Future<void> _openAssets() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AssetsView()));
    _controller.checkAndSyncAssets();
  }

  Widget _buildPlayBox(SyncStatusService syncStatus, bool launchBlocked) {
    // Without a verification pass (auto-process off) nothing is known about
    // what is installed, so say so rather than claiming "Not installed".
    final checked = _controller.cloudData != null;
    final client =
        _controller.selectedClientGroup?.name ??
        (checked ? 'Not installed' : 'Not checked');
    final mod =
        _controller.selectedModGroup?.name ??
        (checked ? 'None' : 'Not checked');

    final String launchLabel;
    final IconData launchIcon;
    if (_controller.isGameRunning) {
      launchLabel = 'Game running';
      launchIcon = Icons.check;
    } else if (_controller.isLaunching) {
      launchLabel = 'Launching';
      launchIcon = Icons.play_arrow;
    } else {
      launchLabel = 'Launch game';
      launchIcon = Icons.play_arrow;
    }

    return JofBox(
      title: 'Play',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: JofSpace.lg,
            runSpacing: JofSpace.md,
            children: [
              _statSlot(JofStat.text(label: 'Client', value: client)),
              _statSlot(JofStat.text(label: 'Mod', value: mod)),
              _statSlot(
                JofStat.text(
                  label: 'Server',
                  value: _controller.connectToPublic
                      ? 'JoF public'
                      : 'Main menu',
                ),
              ),
            ],
          ),
          if (syncStatus.isActive) ...[
            const SizedBox(height: JofSpace.xl),
            const JofWell(
              child: Row(
                children: [
                  Icon(Icons.sync, color: JofColors.warning),
                  SizedBox(width: JofSpace.sm),
                  Expanded(
                    child: Text(
                      'Files are syncing. You can launch once it finishes.',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: JofSpace.xl),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _LabeledCheckbox(
                      label: 'Connect to public server',
                      value: _controller.connectToPublic,
                      onChanged: launchBlocked
                          ? null
                          : (value) => _controller.setConnectToPublic(value),
                    ),
                  ),
                  const SizedBox(height: JofSpace.md),
                  ElevatedButton.icon(
                    onPressed: launchBlocked
                        ? null
                        : () => _controller.launchGame(context),
                    icon: Icon(launchIcon, size: 28),
                    label: Text(launchLabel.toUpperCase()),
                    style: _heroButtonStyle,
                  ),
                  const SizedBox(height: JofSpace.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _heroButtonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(64)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(JofRadius.lg)),
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      JofText.boxHeader.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 27.2 * 0.04,
      ),
    ),
  );

  Widget _statSlot(Widget stat) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 160),
    child: stat,
  );

  Widget _buildAssetsBox() {
    final installed = [
      ..._controller.downloadedClientGroups,
      ..._controller.downloadedModGroups,
    ];

    final Widget list;
    if (_controller.cloudData == null) {
      list = Padding(
        padding: const EdgeInsets.symmetric(vertical: JofSpace.sm),
        child: Text(
          _controller.isCheckingAssets
              ? 'Checking files…'
              : 'Not checked yet. Open Manage assets to review your client '
                    'and mods.',
          style: const TextStyle(color: JofColors.textMuted),
        ),
      );
    } else if (installed.isEmpty) {
      list = const Padding(
        padding: EdgeInsets.symmetric(vertical: JofSpace.sm),
        child: Text(
          'No client or mods installed yet.',
          style: TextStyle(color: JofColors.textMuted),
        ),
      );
    } else {
      list = Column(
        children: [
          for (var i = 0; i < installed.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: JofSpace.sm),
              decoration: i == installed.length - 1
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
                children: [
                  Expanded(child: Text(installed[i].name)),
                  const JofStatus(
                    icon: Icons.check,
                    iconColor: JofColors.highlight,
                    label: 'Installed',
                    labelColor: JofColors.textMuted,
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return JofBox(
      title: 'Assets',
      padded: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          JofSpace.sm,
          0,
          JofSpace.sm,
          JofSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            list,
            const SizedBox(height: JofSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _openAssets,
                child: const Text('MANAGE ASSETS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerBox({required bool expand}) {
    final data = _controller.trackerData;

    final Widget status;
    if (data == null) {
      status = const Padding(
        padding: EdgeInsets.all(JofSpace.md),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      status = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: JofSpace.sm,
          vertical: JofSpace.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.online ? JofColors.success : JofColors.danger,
                    boxShadow: [
                      BoxShadow(
                        color: data.online
                            ? JofColors.successRing
                            : JofColors.dangerText,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: JofSpace.sm),
                Text(
                  data.online ? 'ONLINE' : 'OFFLINE',
                  style: JofText.headingStrong,
                ),
              ],
            ),
            if (data.online) ...[
              const SizedBox(height: JofSpace.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: JofStat.text(
                      label: 'Map',
                      value: data.map ?? 'Unknown',
                    ),
                  ),
                  const SizedBox(width: JofSpace.lg),
                  Expanded(
                    child: JofStat.text(
                      label: 'Players',
                      value: '${data.clients} / ${data.maxClients}',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final players = data?.players ?? const <String>[];

    Widget playerRow(int index) => Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: index == players.length - 1
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: JofColors.border,
                  width: JofSpace.xxs,
                ),
              ),
            ),
      child: ColorTokenizedText(
        text: players[index],
        style: JofText.bodyMedium.copyWith(color: JofColors.text),
      ),
    );

    final Widget playerList;
    if (data == null) {
      playerList = const SizedBox.shrink();
    } else if (players.isEmpty) {
      playerList = const Padding(
        padding: EdgeInsets.all(JofSpace.md),
        child: Text(
          'No players online',
          style: TextStyle(color: JofColors.textMuted),
        ),
      );
    } else if (expand) {
      playerList = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: JofSpace.sm),
        itemCount: players.length,
        itemBuilder: (context, index) => playerRow(index),
      );
    } else {
      playerList = Padding(
        padding: const EdgeInsets.symmetric(horizontal: JofSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (var i = 0; i < players.length; i++) playerRow(i)],
        ),
      );
    }

    return JofBox(
      title: 'Server',
      padded: false,
      expand: expand,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 22),
          tooltip: 'Refresh server status',
          onPressed: () => _controller.refreshTrackerData(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: JofSpace.sm,
              vertical: JofSpace.xs,
            ),
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: JofColors.border,
                  width: JofSpace.xxs,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text('PLAYERS', style: JofText.statLabel)),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: JofColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(JofRadius.xl),
                  ),
                  child: Text(
                    '${players.length}',
                    textAlign: TextAlign.center,
                    style: JofText.caption.copyWith(height: 22 / 12.8),
                  ),
                ),
              ],
            ),
          ),
          if (expand) Expanded(child: playerList) else playerList,
        ],
      ),
    );
  }
}

/// A checkbox with a clickable label, sized to the 44px touch target.
class _LabeledCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _LabeledCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(JofRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: JofSpace.touchTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
              ),
              Padding(
                padding: const EdgeInsets.only(right: JofSpace.sm),
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? JofColors.text : JofColors.textDisabled,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
