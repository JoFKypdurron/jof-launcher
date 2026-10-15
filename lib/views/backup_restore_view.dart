import 'package:flutter/material.dart';

import '../controllers/backup_restore_view_controller.dart';
import '../theme/jof_tokens.dart';
import '../widgets/jof/jof_primitives.dart';

class BackupRestoreView extends StatefulWidget {
  const BackupRestoreView({super.key});

  @override
  State<BackupRestoreView> createState() => _BackupRestoreViewState();
}

class _BackupRestoreViewState extends State<BackupRestoreView> {
  late final BackupRestoreViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BackupRestoreViewController(
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    _controller.load();
  }

  String _formatBackedUpAt(BuildContext context, DateTime? dt) {
    if (dt == null) return 'Unknown date';
    final local = dt.toLocal();
    final date = MaterialLocalizations.of(context).formatFullDate(local);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    return '$date $time';
  }

  Future<void> _restoreSelected() async {
    final result = await _controller.restoreSelected();
    if (!mounted) return;

    if (!result.isOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Restore failed'),
          backgroundColor: JofColors.danger,
        ),
      );
      return;
    }

    final restoredCount = result.restored.length;
    final failedCount = result.failures.length;

    final message = failedCount == 0
        ? 'Restored $restoredCount file(s).'
        : 'Restored $restoredCount file(s), failed $failedCount.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: failedCount == 0
            ? JofColors.successSurface
            : JofColors.warningSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: JofTopBar(
        title: 'Recover backup',
        actions: [
          IconButton(
            onPressed: _controller.isLoading ? null : _controller.load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(JofSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_controller.errorMessage != null) ...[
              Text(
                _controller.errorMessage!,
                style: const TextStyle(color: JofColors.dangerText),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const Text(
                'Select backup files to restore into your local EternalJK folder.',
                style: TextStyle(color: JofColors.textMuted),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                TextButton(
                  onPressed: _controller.isLoading
                      ? null
                      : _controller.selectAll,
                  child: const Text('SELECT ALL'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _controller.isLoading
                      ? null
                      : _controller.selectNone,
                  child: const Text('SELECT NONE'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed:
                      (_controller.isLoading ||
                          _controller.selectedFilenames.isEmpty)
                      ? null
                      : _restoreSelected,
                  icon: const Icon(Icons.download),
                  label: Text(
                    'RESTORE (${_controller.selectedFilenames.length})',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _controller.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _controller.remoteFiles.isEmpty
                  ? const Center(child: Text('No remote backup files found.'))
                  : ListView.separated(
                      itemCount: _controller.remoteFiles.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final entry = _controller.remoteFiles[index];
                        final selected = _controller.selectedFilenames.contains(
                          entry.filename,
                        );
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (value) {
                            _controller.toggleSelected(
                              entry.filename,
                              value ?? false,
                            );
                          },
                          title: Text(entry.filename),
                          subtitle: Text(
                            'Backed up: ${_formatBackedUpAt(context, entry.backedUpAt)}',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
