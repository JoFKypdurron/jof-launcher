import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'dart:io' as io;
import '../controllers/settings_view_controller.dart';
import '../models/client_channel.dart';
import '../models/platform_arch.dart';
import '../models/repository_source.dart';
import '../services/backup_service.dart';
import '../theme/jof_tokens.dart';
import '../widgets/jof/jof_box.dart';
import '../widgets/jof/jof_primitives.dart';
import 'backup_restore_view.dart';
import 'info_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  static const Key gameDataChangeButtonKey = Key('settings.gameData.change');
  static const Key cloudBackupChangeButtonKey = Key(
    'settings.cloudBackup.change',
  );
  static const Key cloudBackupGenerateButtonKey = Key(
    'settings.cloudBackup.generate',
  );

  @visibleForTesting
  static const Key clientChannelDropdownKey = Key('client_channel_dropdown');

  @visibleForTesting
  static const Key repositorySourceDropdownKey = Key(
    'repository_source_dropdown',
  );

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
            backgroundColor: JofColors.danger,
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
              const Text(
                'Enter a new Backup Key. This will be hashed to create your unique Backup ID.',
              ),
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

  /// A form control with its label above and optional helper text below.
  Widget _field({
    required String label,
    required Widget child,
    String? helper,
    bool warning = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(color: JofColors.textMuted)),
        const SizedBox(height: JofSpace.xs),
        child,
        if (helper != null) ...[
          const SizedBox(height: JofSpace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warning) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: JofColors.warning,
                  ),
                ),
                const SizedBox(width: JofSpace.xs),
              ],
              Expanded(
                child: Text(
                  helper,
                  style: JofText.caption.copyWith(
                    color: warning ? JofColors.text : JofColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dropdown<T>({
    Key? key,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      dropdownColor: JofColors.surface,
      iconEnabledColor: JofColors.highlight,
      icon: const Icon(Icons.expand_more),
      borderRadius: BorderRadius.circular(JofRadius.sm),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPlatform =
        !kIsWeb &&
        (io.Platform.isLinux || io.Platform.isMacOS || io.Platform.isWindows);

    final platformFields = <Widget>[
      if (!kIsWeb && io.Platform.isLinux)
        _field(
          label: 'Linux system type',
          helper: 'Picks which client files are downloaded.',
          child: _dropdown<LinuxSystemArch>(
            value: _controller.linuxSystemArch,
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
        ),
      if (!kIsWeb &&
          io.Platform.isMacOS &&
          _controller.macosSystemArchNeedsSelection)
        _field(
          label: 'macOS system type',
          helper:
              'We could not auto-detect your CPU architecture. Please choose one.',
          child: _dropdown<MacosSystemArch>(
            value: _controller.macosSystemArch,
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
        ),
      _field(
        label: 'EternalJK client version',
        warning: true,
        helper:
            'Alpha and beta are unreleased test builds and may be '
            'unstable. Changing this re-downloads the client on the next sync.',
        child: _dropdown<ClientChannel>(
          key: SettingsView.clientChannelDropdownKey,
          value: _controller.clientChannel,
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
      ),
    ];

    return Scaffold(
      appBar: const JofTopBar(title: 'Settings'),
      body: SingleChildScrollView(
        child: JofContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPlatform) ...[
                JofBox(
                  title: 'Platform',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 640 ||
                          platformFields.length == 1) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < platformFields.length; i++) ...[
                              if (i > 0) const SizedBox(height: JofSpace.lg),
                              platformFields[i],
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < platformFields.length; i++) ...[
                            if (i > 0) const SizedBox(width: JofSpace.lg),
                            Expanded(child: platformFields[i]),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: JofSpace.lg),
              ],
              JofBox(
                title: 'Game data',
                child: _field(
                  label: 'GameData folder',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _gameDataPathController,
                          decoration: InputDecoration(
                            hintText: 'No location selected',
                            errorText: _controller.getGameDataPathError(
                              _controller.gameDataPath,
                            ),
                          ),
                          onChanged: (value) async {
                            final path = value.isEmpty ? null : value;
                            await _controller.setGameDataPath(path);
                          },
                        ),
                      ),
                      const SizedBox(width: JofSpace.sm),
                      ElevatedButton(
                        key: SettingsView.gameDataChangeButtonKey,
                        onPressed: kIsWeb ? null : _pickDirectory,
                        child: Text(kIsWeb ? 'NOT SUPPORTED ON WEB' : 'CHANGE'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: JofSpace.lg),
              JofBox(
                title: 'Downloads',
                child: _field(
                  label: 'Download source',
                  helper:
                      'Where game assets are downloaded from. '
                      'Auto uses the JoF Cloud mirror and falls back to jofhub.eu.',
                  child: _dropdown<RepositorySource>(
                    key: SettingsView.repositorySourceDropdownKey,
                    value: _controller.repositorySource,
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
                ),
              ),
              const SizedBox(height: JofSpace.lg),
              JofBox(
                title: 'Automation',
                padded: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: JofSpace.sm,
                    vertical: JofSpace.xs,
                  ),
                  child: Column(
                    children: [
                      _switchRow(
                        title: 'Automatically process assets on start',
                        subtitle:
                            'Sync files and verify only when the application is opened',
                        value: _controller.autoProcess,
                        onChanged: (value) async {
                          await _controller.setAutoProcess(value);
                        },
                      ),
                      const Divider(),
                      _switchRow(
                        title: 'Close launcher when game launches',
                        subtitle:
                            'Automatically close this launcher after starting the game',
                        value: _controller.autoCloseOnGameLaunch,
                        onChanged: (value) async {
                          await _controller.setAutoCloseOnGameLaunch(value);
                        },
                      ),
                      const Divider(),
                      _switchRow(
                        title: 'Check for launcher updates on start',
                        subtitle:
                            'Show a notice when a newer launcher version is released',
                        value: _controller.updateCheckEnabled,
                        onChanged: (value) async {
                          await _controller.setUpdateCheckEnabled(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (BackupService.featureEnabled) ...[
                const SizedBox(height: JofSpace.lg),
                _buildCloudBackupBox(),
              ],
              const SizedBox(height: JofSpace.lg),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'The log file and debug details are under ',
                    style: JofText.caption.copyWith(color: JofColors.textMuted),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const InfoView(),
                        ),
                      );
                    },
                    child: Text(
                      'Information',
                      style: JofText.caption.copyWith(
                        color: JofColors.link,
                        decoration: TextDecoration.underline,
                        decorationColor: JofColors.link,
                      ),
                    ),
                  ),
                  Text(
                    '.',
                    style: JofText.caption.copyWith(color: JofColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudBackupBox() {
    return JofBox(
      title: 'Cloud Backup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _switchRow(
            title: 'Enable encrypted cloud backup',
            subtitle: 'Backup .cfg files to Cloud, end to end encrypted',
            value: _controller.enableCloudBackup,
            onChanged: (value) async {
              await _controller.setEnableCloudBackup(value);
            },
          ),
          if (_controller.enableCloudBackup) ...[
            const SizedBox(height: JofSpace.sm),
            const Text(
              'Current Backup ID:',
              style: TextStyle(color: JofColors.textMuted),
            ),
            const SizedBox(height: JofSpace.xs),
            JofWell(
              child: SelectableText(
                _controller.cloudBackupId ?? 'Not generated',
                style: JofText.caption.copyWith(color: JofColors.text),
              ),
            ),
            const SizedBox(height: JofSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: JofColors.warning,
                ),
                const SizedBox(width: JofSpace.xs),
                Expanded(
                  child: Text(
                    'Do not share your Backup ID with anyone. It is the '
                    'password to your backups.',
                    style: JofText.body,
                  ),
                ),
              ],
            ),
            const SizedBox(height: JofSpace.md),
            Wrap(
              spacing: JofSpace.sm,
              runSpacing: JofSpace.sm,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: kIsWeb
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const BackupRestoreView(),
                            ),
                          );
                        },
                  child: const Text('RESTORE'),
                ),
                ElevatedButton(
                  key: SettingsView.cloudBackupGenerateButtonKey,
                  onPressed: _showGenerateBackupIdDialog,
                  child: const Text('GENERATE'),
                ),
                ElevatedButton(
                  key: SettingsView.cloudBackupChangeButtonKey,
                  onPressed: _showChangeBackupIdDialog,
                  child: const Text('CHANGE'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
