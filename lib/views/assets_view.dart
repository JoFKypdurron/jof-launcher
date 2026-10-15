import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/asset.dart';
import '../models/asset_group.dart';
import '../controllers/assets_view_controller.dart';
import '../services/sync_status_service.dart';
import '../widgets/asset_group_tile.dart';
import '../widgets/bottom_status_bar.dart';
import '../theme/jof_tokens.dart';
import '../widgets/jof/jof_box.dart';
import '../widgets/jof/jof_primitives.dart';
import 'settings_view.dart';

class AssetsView extends StatefulWidget {
  const AssetsView({super.key});

  @override
  State<AssetsView> createState() => _AssetsViewState();
}

class _AssetsViewState extends State<AssetsView> {
  late final AssetsViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AssetsViewController(
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    SyncStatusService.instance.addListener(_onSyncStatusChanged);
    _controller.fetchData();
  }

  void _onSyncStatusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SyncStatusService.instance.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  Future<void> _startSync() async {
    final result = await _controller.startSync();

    if (!mounted) return;

    switch (result.type) {
      case SyncResultType.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully')),
        );
        break;
      case SyncResultType.settingsMissing:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set GameData location in Settings first'),
          ),
        );
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const SettingsView()));
        break;
      case SyncResultType.alreadyInSync:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Everything is already in sync')),
        );
        break;
      case SyncResultType.cancelled:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync cancelled')));
        break;
      case SyncResultType.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: ${result.errorMessage}')),
        );
        break;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsView()));
    _controller.fetchData();
  }

  static const _tabTitles = ['Clients', 'Mods', 'Assets', 'Others'];

  List<List<AssetGroup>> get _tabGroups => [
    _controller.data?.clientGroups ?? [],
    _controller.data?.modGroups ?? [],
    _controller.data?.assetGroups ?? [],
    _controller.data?.otherGroups ?? [],
  ];

  @override
  Widget build(BuildContext context) {
    final syncActive = SyncStatusService.instance.isActive;

    final topBar = JofTopBar(
      title: 'Manage assets',
      actions: [
        IconButton(
          icon: const Icon(Icons.tune),
          tooltip: 'Settings',
          onPressed: syncActive ? null : _openSettings,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Check for changes',
          onPressed: (_controller.isLoading || syncActive)
              ? null
              : () => _controller.fetchData(forceVerify: true),
        ),
      ],
    );

    final showTabs =
        !_controller.isLoading &&
        _controller.errorMessage == null &&
        !_controller.isSettingsMissing;

    if (!showTabs) {
      return Scaffold(appBar: topBar, body: _buildBody());
    }

    final selection = _controller.selectionManager;
    final labels = [
      for (var i = 0; i < _tabTitles.length; i++)
        _tabLabel(_tabTitles[i], _tabGroups[i], selection.selectedAssets),
    ];

    return DefaultTabController(
      length: _tabTitles.length,
      child: Scaffold(
        appBar: topBar,
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: JofSpace.contentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                JofSpace.lg,
                JofSpace.lg,
                JofSpace.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JofTabBar(labels: labels),
                  const SizedBox(height: JofSpace.lg),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (var i = 0; i < _tabTitles.length; i++)
                          _buildGroupList(_tabTitles[i], _tabGroups[i]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: syncActive
            ? BottomStatusBar(
                icon: Icons.sync,
                message: SyncStatusService.instance.message,
                progress: SyncStatusService.instance.progress,
                overallProgress: SyncStatusService.instance.overallProgress,
                counterText: SyncStatusService.instance.queueLabel,
              )
            : _buildSyncFooter(),
      ),
    );
  }

  /// Tab title, with the number of groups that have unsynced changes.
  String _tabLabel(
    String title,
    List<AssetGroup> groups,
    Set<Asset> selectedAssets,
  ) {
    final changed = groups
        .where(
          (g) =>
              AssetGroupTile.unsyncedChangeCount(
                g,
                selectedAssets,
                _controller.assetStatuses,
              ) >
              0,
        )
        .length;
    return changed == 0 ? title : '$title · $changed';
  }

  Widget _buildSyncFooter() {
    final changes = _controller.pendingChanges;
    final hasChanges = changes.downloads + changes.removals > 0;

    String files(int n) => n == 0 ? 'None' : (n == 1 ? '1 file' : '$n files');

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: JofColors.surface,
        border: Border(
          top: BorderSide(color: JofColors.border, width: JofSpace.xxs),
        ),
        boxShadow: JofShadows.outset,
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: JofSpace.contentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JofSpace.lg,
                vertical: JofSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: JofSpace.lg,
                      runSpacing: JofSpace.sm,
                      children: [
                        JofStat.text(
                          label: 'To download',
                          value: files(changes.downloads),
                        ),
                        JofStat.text(
                          label: 'To remove',
                          value: files(changes.removals),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: JofSpace.lg),
                  ElevatedButton.icon(
                    onPressed: (kIsWeb || !hasChanges) ? null : _startSync,
                    icon: const Icon(Icons.sync),
                    label: Text(kIsWeb ? 'NOT SUPPORTED ON WEB' : 'SYNC'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: JofSpace.xl,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: JofSpace.md),
            if (_controller.verificationProgress > 0) ...[
              Text(
                'Verifying files: ${(_controller.verificationProgress * 100).toInt()}%',
              ),
              const SizedBox(height: JofSpace.sm),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _controller.verificationProgress,
                ),
              ),
            ] else
              const Text('Loading cloud data...'),
          ],
        ),
      );
    }

    if (_controller.errorMessage != null) {
      return _buildNotice(
        icon: Icons.error_outline,
        iconColor: JofColors.dangerText,
        title: 'Could not load assets',
        message: _controller.errorMessage!,
        actionLabel: 'RETRY',
        onAction: () => _controller.fetchData(forceVerify: true),
      );
    }

    return _buildNotice(
      icon: Icons.folder_open,
      iconColor: JofColors.highlight,
      title: 'GameData location not set',
      message: 'You must set a GameData location before selecting assets.',
      actionLabel: 'GO TO SETTINGS',
      onAction: _openSettings,
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return SingleChildScrollView(
      child: JofContent(
        maxWidth: 560,
        child: JofBox(
          title: title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: iconColor),
                  const SizedBox(width: JofSpace.sm),
                  Expanded(child: Text(message)),
                ],
              ),
              const SizedBox(height: JofSpace.lg),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupList(String title, List<AssetGroup> groups) {
    final selection = _controller.selectionManager;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: JofSpace.lg),
      child: JofBox(
        title: title,
        padded: false,
        child: groups.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(JofSpace.md),
                child: Text(
                  'Nothing to show here yet.',
                  style: TextStyle(color: JofColors.textMuted),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) const Divider(),
                    AssetGroupTile(
                      group: groups[i],
                      isRequired: selection.effectiveRequiredGroups.contains(
                        groups[i],
                      ),
                      selectedAssets: selection.selectedAssets,
                      assetStatuses: _controller.assetStatuses,
                      isDownloading: _controller.isDownloading,
                      onGroupToggle: (group, select) =>
                          _controller.toggleGroupSelection(group, select),
                      onAssetToggle: (asset) =>
                          _controller.toggleAssetSelection(asset),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
