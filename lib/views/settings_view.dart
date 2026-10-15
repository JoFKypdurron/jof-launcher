import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'dart:io' as io;
import '../controllers/settings_view_controller.dart';
import '../models/client_channel.dart';
import '../models/platform_arch.dart';
import '../models/repository_source.dart';
import '../services/backup_service.dart';
import 'backup_restore_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  static const Key gameDataChangeButtonKey = Key('settings.gameData.change');
  static const Key cloudBackupChangeButtonKey = Key('settings.cloudBackup.change');
  static const Key cloudBackupGenerateButtonKey = Key('settings.cloudBackup.generate');

  @visibleForTesting
  static const Key clientChannelDropdownKey = Key('client_channel_dropdown');

  @visibleForTesting
  static const Key repositorySourceDropdownKey = Key('repository_source_dropdown');

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final SettingsViewController _controller;
  final TextEditingController _gameDataPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = SettingsViewController(
      onStateChanged: () {
        if (mounted) {
          setState(() {
            _gameDataPathController.text = _controller.gameDataPath ?? '';
          });
        }
      },
    );
    _controller.loadSettings();
  }

  @override
  void dispose() {
    _gameDataPathController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final result = await _controller.pickDirectory();
    if (mounted) {
      if (result.isSuccess) {
        // Success handled by controller
      } else if (!result.isCancelled && result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showChangeBackupIdDialog() async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Backup ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a new Backup Key. This will be hashed to create your unique Backup ID.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Backup ID',
                  hintText: 'e.g. my-secret-id',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  await _controller.changeCloudBackupId(controller.text);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showGenerateBackupIdDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Generate new Backup ID?'),
          content: const Text(
            'This will rotate your Backup ID. You will not be able to restore old backups unless you saved the previous ID.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _controller.generateNewCloudBackupId();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('GENERATE'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!kIsWeb && (io.Platform.isLinux || io.Platform.isMacOS || io.Platform.isWindows)) ...[
                const Text(
                  'Platform',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (io.Platform.isLinux) ...[
                  DropdownButtonFormField<LinuxSystemArch>(
                    initialValue: _controller.linuxSystemArch,
                    decoration: const InputDecoration(
                      labelText: 'Linux system type',
                      helperText: 'Select the correct architecture to download the right client files.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LinuxSystemArch.bit64,
                        child: Text('64-bit'),
                      ),
                      DropdownMenuItem(
                        value: LinuxSystemArch.bit32,
                        child: Text('32-bit'),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      await _controller.setLinuxSystemArch(value);
                    },
                  ),
                ],
                if (io.Platform.isMacOS && _controller.macosSystemArchNeedsSelection) ...[
                  DropdownButtonFormField<MacosSystemArch>(
                    initialValue: _controller.macosSystemArch,
                    decoration: const InputDecoration(
                      labelText: 'macOS system type',
                      helperText: 'We could not auto-detect your CPU architecture. Please choose one.',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: MacosSystemArch.arm,
                        child: Text('Apple Silicon (ARM)'),
                      ),
                      DropdownMenuItem(
                        value: MacosSystemArch.amd,
                        child: Text('Intel (AMD/x86_64)'),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      await _controller.setMacosSystemArch(value);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<ClientChannel>(
                  key: SettingsView.clientChannelDropdownKey,
                  initialValue: _controller.clientChannel,
                  decoration: const InputDecoration(
                    labelText: 'EternalJK client version',
                    helperText: 'Alpha and beta are unreleased test builds and may be unstable. '
                        'Changing this re-downloads the client on the next sync.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ClientChannel.stable,
                      child: Text('Latest stable'),
                    ),
                    DropdownMenuItem(
                      value: ClientChannel.beta,
                      child: Text('Beta (test build)'),
                    ),
                    DropdownMenuItem(
                      value: ClientChannel.alpha,
                      child: Text('Alpha (test build)'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await _controller.setClientChannel(value);
                  },
                ),
                const SizedBox(height: 24),
              ],
              const Text(
                'GameData Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _gameDataPathController,
                      decoration: InputDecoration(
                        hintText: 'No location selected',
                        errorText: _controller.getGameDataPathError(_controller.gameDataPath),
                      ),
                      onChanged: (value) async {
                        final path = value.isEmpty ? null : value;
                        await _controller.setGameDataPath(path);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: SettingsView.gameDataChangeButtonKey,
                    onPressed: kIsWeb ? null : _pickDirectory,
                    child: Text(kIsWeb ? 'NOT SUPPORTED ON WEB' : 'CHANGE'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Downloads',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RepositorySource>(
                key: SettingsView.repositorySourceDropdownKey,
                initialValue: _controller.repositorySource,
                decoration: const InputDecoration(
                  labelText: 'Download source',
                  helperText: 'Where game assets are downloaded from. '
                      'Auto uses the JoF Cloud mirror and falls back to jofhub.eu.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: RepositorySource.auto,
                    child: Text('Auto (JoF Cloud, fall back to jofhub.eu)'),
                  ),
                  DropdownMenuItem(
                    value: RepositorySource.mirror,
                    child: Text('JoF Cloud mirror only'),
                  ),
                  DropdownMenuItem(
                    value: RepositorySource.origin,
                    child: Text('jofhub.eu only'),
                  ),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  await _controller.setRepositorySource(value);
                },
              ),
              if (_controller.logFilePath != null) ...[
                const SizedBox(height: 12),
                const Text('Log file (for support):', style: TextStyle(fontSize: 14, color: Colors.grey)),
                SelectableText(
                  _controller.logFilePath!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Automation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Automatically process assets on start'),
                subtitle: const Text('Sync files and verify only when the application is opened'),
                value: _controller.autoProcess,
                onChanged: (value) async {
                  await _controller.setAutoProcess(value);
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Close launcher when game launches'),
                subtitle: const Text('Automatically close this launcher after starting the game'),
                value: _controller.autoCloseOnGameLaunch,
                onChanged: (value) async {
                  await _controller.setAutoCloseOnGameLaunch(value);
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Check for launcher updates on start'),
                subtitle: const Text('Show a notice when a newer launcher version is released'),
                value: _controller.updateCheckEnabled,
                onChanged: (value) async {
                  await _controller.setUpdateCheckEnabled(value);
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (BackupService.featureEnabled) ...[
                const SizedBox(height: 24),
                const Text(
                  'Cloud Backup',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable encrypted cloud backup'),
                  subtitle: const Text('Backup .cfg files to Cloud, end to end encrypted'),
                  value: _controller.enableCloudBackup,
                  onChanged: (value) async {
                    await _controller.setEnableCloudBackup(value);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (_controller.enableCloudBackup) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current Backup ID:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                            Text(_controller.cloudBackupId ?? 'Not generated', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            Text('DO NOT SHARE BACKUP ID WITH ANYONE, ITS YOUR PASSWORD TO BACKUPS', style: TextStyle(fontSize: 16, color: Colors.amber))
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: SettingsView.cloudBackupGenerateButtonKey,
                        onPressed: _showGenerateBackupIdDialog,
                        child: const Text('GENERATE'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: SettingsView.cloudBackupChangeButtonKey,
                        onPressed: _showChangeBackupIdDialog,
                        child: const Text('CHANGE'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: kIsWeb
                            ? null
                            : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const BackupRestoreView()),
                          );
                        },
                        child: Text(kIsWeb ? 'RESTORE' : 'RESTORE'),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
