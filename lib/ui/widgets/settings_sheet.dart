import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/dimming/dim_schedule.dart';
import '../../core/pack/sen_pack.dart';
import '../../core/state/brain_mode.dart';
import '../../core/state/display_controller.dart';
import '../../services/audio/wake_model_installer.dart';
import '../../services/sen_pack_service.dart';
import '../../services/update/app_updater.dart';
import '../../services/settings_service.dart';
import '../../services/wake_word_service.dart';
import '../strings.dart';
import '../theme/app_theme.dart';

enum _ProbeState { idle, testing, success, failure }

enum _SyncState { idle, syncing, updated, unchanged, invalid, failed }

enum _UpdateProbe { idle, checking, done }

Future<void> showSettingsSheet(
  BuildContext context,
  DisplayController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: _SettingsSheet.maxWidth),
    builder: (_) => _SettingsSheet(controller: controller),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller});

  final DisplayController controller;

  static const double maxWidth = 640;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const double _titleSize = 22;
  static const int _sensitivityDivisions = 10;
  static const int _percentScale = 100;
  static const int _hourDigits = 2;
  static const double _spinnerSize = 18;
  static const double _spinnerStroke = 2;

  /// One slider step per percent.
  static final int _dimDivisions =
      ((DimLimits.maxLevel - DimLimits.minLevel) * _percentScale).round();

  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final HubSettings _initial = widget.controller.settings;
  late final TextEditingController _host = TextEditingController(
    text: _initial.host,
  );
  late final TextEditingController _port = TextEditingController(
    text: _initial.port.toString(),
  );
  late final TextEditingController _keyword = TextEditingController(
    text: _initial.wakeKeyword,
  );
  late final TextEditingController _geminiKey = TextEditingController(
    text: _initial.geminiApiKey,
  );
  late final TextEditingController _packUrl = TextEditingController(
    text: _initial.knowledgePackUrl,
  );
  final GlobalKey<FormFieldState<String>> _packField = GlobalKey();
  late final TextEditingController _updateUrl = TextEditingController(
    text: _initial.updateUrl,
  );
  _UpdateProbe _updateProbe = _UpdateProbe.idle;
  UpdateCheck? _updateCheck;
  late final TextEditingController _photoUrl = TextEditingController(
    text: _initial.photoManifestUrl,
  );
  _SyncState _sync = _SyncState.idle;
  SenPack? _synced;
  late BrainMode _brain = _initial.brainMode;
  bool _keyVisible = false;
  late double _slideSec = _initial.slideIntervalSec.toDouble();
  late double _sensitivity = _initial.wakeSensitivity;
  late bool _alwaysListening = _initial.alwaysListening;
  late DimSettings _dim = _initial.dim;
  _ProbeState _probe = _ProbeState.idle;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _keyword.dispose();
    _geminiKey.dispose();
    _packUrl.dispose();
    _updateUrl.dispose();
    _photoUrl.dispose();
    super.dispose();
  }

  HubSettings? _draft() {
    if (!(_form.currentState?.validate() ?? false)) {
      return null;
    }
    return _initial.copyWith(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      slideIntervalSec: _slideSec.round(),
      wakeSensitivity: _sensitivity,
      wakeKeyword: _keyword.text,
      alwaysListening: _alwaysListening,
      dim: _dim,
      geminiApiKey: _geminiKey.text,
      brainMode: _brain,
      knowledgePackUrl: _packUrl.text,
      updateUrl: _updateUrl.text,
      photoManifestUrl: _photoUrl.text,
    );
  }

  Future<void> _checkUpdate() async {
    final draft = _draft();
    if (draft == null) {
      return;
    }
    setState(() => _updateProbe = _UpdateProbe.checking);
    final result = await widget.controller.checkUpdate(draft);
    if (!mounted) {
      return;
    }
    setState(() {
      _updateProbe = _UpdateProbe.done;
      _updateCheck = result;
    });
  }

  Future<void> _test() async {
    final draft = _draft();
    if (draft == null) {
      return;
    }
    setState(() => _probe = _ProbeState.testing);
    final ok = await widget.controller.testConnection(draft);
    if (!mounted) {
      return;
    }
    setState(() => _probe = ok ? _ProbeState.success : _ProbeState.failure);
  }

  Future<void> _syncPack() async {
    final url = _packUrl.text.trim();
    if (url.isEmpty || !(_packField.currentState?.validate() ?? false)) {
      setState(() => _sync = _SyncState.invalid);
      return;
    }
    setState(() => _sync = _SyncState.syncing);
    final result = await widget.controller.syncPack(url);
    if (!mounted) {
      return;
    }
    setState(() {
      _synced = result.pack;
      _sync = switch (result.status) {
        PackSync.updated => _SyncState.updated,
        PackSync.unchanged => _SyncState.unchanged,
        PackSync.invalid => _SyncState.invalid,
        PackSync.failed => _SyncState.failed,
      };
    });
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) {
      return;
    }
    await widget.controller.applySettings(draft);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  String? _validateHost(String? value) {
    final host = value?.trim() ?? '';
    if (host.isEmpty || host.contains(' ') || host.contains('/')) {
      return AppStrings.invalidHost;
    }
    return null;
  }

  String? _validatePackUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty || widget.controller.isPackUrl(url)) {
      return null;
    }
    return AppStrings.invalidPackUrl;
  }

  String? _validateUpdateUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty || widget.controller.isUpdateUrl(url)) {
      return null;
    }
    return AppStrings.invalidUpdateUrl;
  }

  String? _validatePhotoUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty || widget.controller.isPhotoUrl(url)) {
      return null;
    }
    return AppStrings.invalidPackUrl;
  }

  String? _validateKeyword(String? value) {
    return switch (widget.controller.checkKeyword(value ?? '')) {
      KeywordCheck.empty => AppStrings.invalidKeyword,
      KeywordCheck.unsupported => AppStrings.keywordUnsupported,
      KeywordCheck.ok || KeywordCheck.unverified => null,
    };
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null ||
        port < SettingsLimits.minPort ||
        port > SettingsLimits.maxPort) {
      return AppStrings.invalidPort;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        Spacing.lg + insets.bottom,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStrings.settingsTitle,
                style: TextStyle(
                  fontSize: _titleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              _addressRow(),
              const SizedBox(height: Spacing.md),
              _probeRow(),
              const SizedBox(height: Spacing.lg),
              ..._brainSection(),
              const SizedBox(height: Spacing.lg),
              ..._packSection(),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _photoUrl,
                validator: _validatePhotoUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: AppStrings.photoUrl,
                  helperText: AppStrings.photoUrlHint,
                  border: OutlineInputBorder(),
                ),
              ),
              ..._updateSection(),
              const SizedBox(height: Spacing.lg),
              _sliderTile(
                label: AppStrings.slideInterval,
                valueLabel: '${_slideSec.round()} ${AppStrings.secondsSuffix}',
                slider: Slider(
                  value: _slideSec,
                  min: SettingsLimits.minSlideSec.toDouble(),
                  max: SettingsLimits.maxSlideSec.toDouble(),
                  divisions:
                      SettingsLimits.maxSlideSec - SettingsLimits.minSlideSec,
                  onChanged: (v) => setState(() => _slideSec = v),
                ),
              ),
              TextFormField(
                controller: _keyword,
                validator: _validateKeyword,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: AppStrings.wakeKeyword,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              _sliderTile(
                label: AppStrings.wakeSensitivity,
                valueLabel: '${(_sensitivity * _percentScale).round()}%',
                slider: Slider(
                  value: _sensitivity,
                  min: SettingsLimits.minSensitivity,
                  max: SettingsLimits.maxSensitivity,
                  divisions: _sensitivityDivisions,
                  onChanged: (v) => setState(() => _sensitivity = v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(AppStrings.alwaysListening),
                subtitle: const Text(AppStrings.alwaysListeningHint),
                value: _alwaysListening,
                onChanged: (v) => setState(() => _alwaysListening = v),
              ),
              ..._dimSection(),
              _modelRow(),
              const SizedBox(height: Spacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.cancel),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: _save,
                    child: const Text(AppStrings.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _brainSection() {
    final noKey = _geminiKey.text.trim().isEmpty;
    final hint = _brain == BrainMode.gemini && noKey
        ? AppStrings.brainNoKey
        : AppStrings.brainVoiceHint;
    return [
      const Text(AppStrings.brainTitle),
      const SizedBox(height: Spacing.sm),
      SegmentedButton<BrainMode>(
        segments: const [
          ButtonSegment(
            value: BrainMode.hub,
            label: Text(AppStrings.brainHub),
            icon: Icon(Icons.hub_rounded),
          ),
          ButtonSegment(
            value: BrainMode.gemini,
            label: Text(AppStrings.brainGemini),
            icon: Icon(Icons.auto_awesome_rounded),
          ),
        ],
        selected: {_brain},
        onSelectionChanged: (picked) => setState(() => _brain = picked.first),
      ),
      const SizedBox(height: Spacing.md),
      TextFormField(
        controller: _geminiKey,
        obscureText: !_keyVisible,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: AppStrings.geminiKey,
          helperText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _keyVisible ? AppStrings.hideKey : AppStrings.showKey,
            icon: Icon(
              _keyVisible
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            onPressed: () => setState(() => _keyVisible = !_keyVisible),
          ),
        ),
      ),
    ];
  }

  List<Widget> _packSection() {
    final syncing = _sync == _SyncState.syncing;
    return [
      TextFormField(
        key: _packField,
        controller: _packUrl,
        validator: _validatePackUrl,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: AppStrings.packUrl,
          helperText: AppStrings.packUrlHint,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: Spacing.md),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: syncing ? null : _syncPack,
            icon: syncing
                ? const SizedBox.square(
                    dimension: _spinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: _spinnerStroke,
                    ),
                  )
                : const Icon(Icons.cloud_sync_rounded),
            label: const Text(AppStrings.syncNow),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: _syncLabel()),
        ],
      ),
    ];
  }

  Widget _syncLabel() {
    return switch (_sync) {
      _SyncState.idle => const SizedBox.shrink(),
      _SyncState.syncing => const Text(AppStrings.syncing),
      _SyncState.updated => Text(
        _syncSummary(_synced),
        style: const TextStyle(color: AppPalette.online),
      ),
      _SyncState.unchanged => const Text(
        AppStrings.syncUnchanged,
        style: TextStyle(color: AppPalette.online),
      ),
      _SyncState.invalid => const Text(
        AppStrings.syncInvalid,
        style: TextStyle(color: AppPalette.offline),
      ),
      _SyncState.failed => const Text(
        AppStrings.syncFailed,
        style: TextStyle(color: AppPalette.offline),
      ),
    };
  }

  static String _syncSummary(SenPack? pack) {
    if (pack == null) {
      return AppStrings.syncUpdated;
    }
    final version = pack.version.isEmpty ? '' : ' (${pack.version})';
    return '${AppStrings.syncUpdated}: ${pack.members.length} '
        '${AppStrings.syncMembers}, ${pack.skills.length} '
        '${AppStrings.syncSkills}, ${pack.rituals.length} '
        '${AppStrings.syncRituals}$version';
  }

  List<Widget> _updateSection() {
    final checking = _updateProbe == _UpdateProbe.checking;
    return [
      TextFormField(
        controller: _updateUrl,
        validator: _validateUpdateUrl,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: AppStrings.updateUrl,
          helperText: AppStrings.updateUrlHint,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: Spacing.md),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: checking ? null : _checkUpdate,
            icon: checking
                ? const SizedBox.square(
                    dimension: _spinnerSize,
                    child: CircularProgressIndicator(
                      strokeWidth: _spinnerStroke,
                    ),
                  )
                : const Icon(Icons.system_update_rounded),
            label: const Text(AppStrings.checkUpdate),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: _updateLabel()),
        ],
      ),
    ];
  }

  Widget _updateLabel() {
    if (_updateProbe == _UpdateProbe.checking) {
      return const Text(AppStrings.checkingUpdate);
    }
    final release = widget.controller.update.value.release;
    return switch (_updateCheck) {
      null => const SizedBox.shrink(),
      UpdateCheck.upToDate => const Text(
        AppStrings.updateUpToDate,
        style: TextStyle(color: AppPalette.online),
      ),
      UpdateCheck.ready => Text(
        release == null
            ? AppStrings.updateDownloaded
            : '${AppStrings.updateDownloaded} v${release.versionName}',
        style: const TextStyle(color: AppPalette.online),
      ),
      UpdateCheck.failed => const Text(
        AppStrings.updateFailed,
        style: TextStyle(color: AppPalette.offline),
      ),
      UpdateCheck.unsupported => const Text(
        AppStrings.updateUnsupported,
        style: TextStyle(color: AppPalette.offline),
      ),
    };
  }

  List<Widget> _dimSection() {
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(AppStrings.nightDim),
        subtitle: const Text(AppStrings.nightDimHint),
        value: _dim.enabled,
        onChanged: (v) => setState(() => _dim = _dim.copyWith(enabled: v)),
      ),
      if (_dim.enabled) ...[
        Row(
          children: [
            Expanded(
              child: _hourField(
                label: AppStrings.dimStart,
                value: _dim.startHour,
                onChanged: (h) => _dim = _dim.copyWith(startHour: h),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: _hourField(
                label: AppStrings.dimEnd,
                value: _dim.endHour,
                onChanged: (h) => _dim = _dim.copyWith(endHour: h),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _sliderTile(
          label: AppStrings.dimLevel,
          valueLabel: '${(_dim.level * _percentScale).round()}%',
          slider: Slider(
            value: _dim.level,
            min: DimLimits.minLevel,
            max: DimLimits.maxLevel,
            divisions: _dimDivisions,
            onChanged: (v) => setState(() => _dim = _dim.copyWith(level: v)),
          ),
        ),
      ],
    ];
  }

  Widget _hourField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var hour = DimLimits.minHour; hour <= DimLimits.maxHour; hour++)
          DropdownMenuItem(value: hour, child: Text(_hourLabel(hour))),
      ],
      onChanged: (hour) {
        if (hour == null) {
          return;
        }
        setState(() => onChanged(hour));
      },
    );
  }

  static String _hourLabel(int hour) {
    return '${hour.toString().padLeft(_hourDigits, '0')}:00';
  }

  Widget _addressRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _host,
            validator: _validateHost,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: AppStrings.hubHost,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: TextFormField(
            controller: _port,
            validator: _validatePort,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.hubPort,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _probeRow() {
    final testing = _probe == _ProbeState.testing;
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: testing ? null : _test,
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: const Text(AppStrings.testConnection),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(child: _probeLabel()),
      ],
    );
  }

  Widget _probeLabel() {
    return switch (_probe) {
      _ProbeState.idle => const SizedBox.shrink(),
      _ProbeState.testing => const Text(AppStrings.testing),
      _ProbeState.success => const Text(
        AppStrings.testOk,
        style: TextStyle(color: AppPalette.online),
      ),
      _ProbeState.failure => const Text(
        AppStrings.testFail,
        style: TextStyle(color: AppPalette.offline),
      ),
    };
  }

  Widget _modelRow() {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final progress = widget.controller.modelProgress;
        final failed = progress.phase == InstallPhase.failed;
        return Row(
          children: [
            const Expanded(child: Text(AppStrings.modelTitle)),
            Text(
              _modelLabel(progress),
              style: TextStyle(
                color: failed ? AppPalette.offline : AppPalette.accent,
              ),
            ),
            if (failed)
              TextButton(
                onPressed: widget.controller.installModel,
                child: const Text(AppStrings.retry),
              ),
          ],
        );
      },
    );
  }

  String _modelLabel(InstallProgress progress) {
    return switch (progress.phase) {
      InstallPhase.idle => AppStrings.modelIdle,
      InstallPhase.downloading =>
        '${AppStrings.modelDownloading} '
            '${(progress.fraction * _percentScale).round()}%',
      InstallPhase.verifying => AppStrings.modelVerifying,
      InstallPhase.ready => AppStrings.modelReady,
      InstallPhase.failed => AppStrings.modelFailed,
    };
  }

  Widget _sliderTile({
    required String label,
    required String valueLabel,
    required Widget slider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel, style: const TextStyle(color: AppPalette.accent)),
          ],
        ),
        slider,
      ],
    );
  }
}
