import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/asset_group.dart';
import '../controllers/assets_view_controller.dart';
import '../services/sync_status_service.dart';
import '../widgets/asset_group_tile.dart';
import '../widgets/bottom_status_bar.dart';
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
          const SnackBar(content: Text('Please set GameData location in Settings first')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const SettingsView()),
        );
        break;
      case SyncResultType.alreadyInSync:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Everything is already in sync')),
        );
        break;
      case SyncResultType.cancelled:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync cancelled')),
        );
        break;
      case SyncResultType.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: ${result.errorMessage}')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isSettingsMissing && !_controller.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Assets'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SettingsView()),
                );
                _controller.fetchData();
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller.fetchData(forceVerify: true),
            ),
          ],
        ),
        body: _buildBody(),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Assets'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'CLIENTS'),
              Tab(text: 'MODS'),
              Tab(text: 'ASSETS'),
              Tab(text: 'OTHERS'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: SyncStatusService.instance.isActive ? null : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SettingsView()),
                );
                _controller.fetchData();
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: (_controller.isLoading || SyncStatusService.instance.isActive) ? null : () => _controller.fetchData(forceVerify: true),
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: SyncStatusService.instance.isActive
            ? BottomStatusBar(
                icon: Icons.sync,
                message: SyncStatusService.instance.message,
                progress: SyncStatusService.instance.progress,
                overallProgress: SyncStatusService.instance.overallProgress,
                counterText: SyncStatusService.instance.queueLabel,
              )
            : null,
        floatingActionButton: _controller.pendingChangesCount > 0 &&
                !SyncStatusService.instance.isActive
            ? FloatingActionButton.extended(
                onPressed: kIsWeb ? null : _startSync,
                label: Text(kIsWeb ? 'NOT SUPPORTED ON WEB' : 'SYNC (${_controller.pendingChangesText})'),
                icon: const Icon(Icons.sync),
              )
            : null,
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
            const SizedBox(height: 16),
            if (_controller.verificationProgress > 0) ...[
              Text('Verifying files: ${(_controller.verificationProgress * 100).toInt()}%'),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: _controller.verificationProgress),
              ),
            ] else
              const Text('Loading cloud data...'),
          ],
        ),
      );
    }

    if (_controller.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: ${_controller.errorMessage}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => _controller.fetchData(forceVerify: true), child: const Text('RETRY')),
          ],
        ),
      );
    }
    
    if (_controller.isSettingsMissing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings, size: 64, color: Color(0xFFA5D8FF)),
              const SizedBox(height: 16),
              const Text(
                'GameData location not set',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You must set a GameData location before selecting assets.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SettingsView()),
                  );
                  _controller.fetchData();
                },
                child: const Text('GO TO SETTINGS'),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      children: [
        _buildGroupList(_controller.data?.clientGroups ?? []),
        _buildGroupList(_controller.data?.modGroups ?? []),
        _buildGroupList(_controller.data?.assetGroups ?? []),
        _buildGroupList(_controller.data?.otherGroups ?? []),
      ],
    );
  }

  Widget _buildGroupList(List<AssetGroup> groups) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final isEffectivelyRequired = _controller.selectionManager.effectiveRequiredGroups.contains(group);

        return AssetGroupTile(
          group: group,
          isRequired: isEffectivelyRequired,
          selectedAssets: _controller.selectionManager.selectedAssets,
          assetStatuses: _controller.assetStatuses,
          isDownloading: _controller.isDownloading,
          onGroupToggle: (group, select) => _controller.toggleGroupSelection(group, select),
          onAssetToggle: (asset) => _controller.toggleAssetSelection(asset),
        );
      },
    );
  }
}
