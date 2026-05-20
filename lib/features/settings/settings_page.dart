import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/utils/download_helper.dart';

const _tabAccentColor = Colors.white;

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);

    return AppScaffold(
      title: 'Einstellungen',
      subtitle:
          'Pilotprofil, Heimatplatz, Kontaktdaten und lokale App-Optionen verwalten.',
      children: [
        DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingsTabs(),
              Container(
                height: 1320,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: TabBarView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: _PilotProfileCard(
                        profile: fleet.pilotProfile,
                        onSave: (profile) => ref
                            .read(fleetProvider.notifier)
                            .updatePilotProfile(profile),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: _AppSettingsCard(
                        settings: fleet.appSettings,
                        onCreateBackup: () => _showBackupDialog(
                          context,
                          ref,
                        ),
                        onRestoreBackup: () => _importData(
                          context,
                          ref,
                          restore: true,
                        ),
                        onLocationSharingChanged: (value) => ref
                            .read(fleetProvider.notifier)
                            .updateLocationSharing(value),
                        onChatReachabilityChanged: (value) => ref
                            .read(fleetProvider.notifier)
                            .updateChatReachability(value),
                        onSettingsChanged: (settings) => ref
                            .read(fleetProvider.notifier)
                            .updateAppSettings(settings),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool> _exportData(
    BuildContext context,
    WidgetRef ref, {
    bool backup = false,
    String? preferredFileName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = preferredFileName ??
        (backup
            ? 'modellflug_backup_$stamp.json'
            : 'modellflug_export_$stamp.json');
    final rawJson = ref.read(fleetProvider.notifier).exportJson();
    final bytes = Uint8List.fromList(utf8.encode(rawJson));

    if (kIsWeb) {
      final saved = await saveTextFile(
        fileName: fileName,
        content: rawJson,
        mimeType: 'application/json;charset=utf-8',
      );
      if (!context.mounted) {
        return saved;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? backup
                    ? 'Sicherung wurde erstellt.'
                    : 'Daten wurden exportiert.'
                : 'Sicherung konnte in diesem Browser nicht geschrieben werden. Bitte Chrome verwenden.',
          ),
        ),
      );
      return saved;
    }

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: backup ? 'Sicherung speichern' : 'Daten exportieren',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );

    if (!context.mounted) {
      return savedPath != null;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          savedPath == null
              ? 'Speichern abgebrochen.'
              : backup
                  ? 'Sicherung wurde erstellt.'
                  : 'Daten wurden exportiert.',
        ),
      ),
    );
    return savedPath != null;
  }

  Future<void> _showBackupDialog(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileNameController = TextEditingController(
      text: 'modellflug_backup_$stamp.json',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        var saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Sicherung erstellen'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lege den Dateinamen fest. Danach oeffnet sich der Speichern-Dialog, in dem du den Speicherort auswaehlst und die Sicherung erstellst.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fileNameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Name der Sicherungs-Datei',
                        prefixIcon: Icon(Icons.backup_rounded),
                      ),
                    ),
                    if (saving) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final rawName = fileNameController.text.trim();
                          final normalized =
                              rawName.toLowerCase().endsWith('.json')
                                  ? rawName
                                  : '$rawName.json';
                          if (normalized == '.json') {
                            return;
                          }

                          setDialogState(() => saving = true);
                          await _exportData(
                            context,
                            ref,
                            backup: true,
                            preferredFileName: normalized,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(
                    saving ? 'Sicherung laeuft...' : 'Speicherort waehlen',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    fileNameController.dispose();
  }

  Future<void> _importData(
    BuildContext context,
    WidgetRef ref, {
    bool restore = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: restore ? 'Sicherung wiederherstellen' : 'Daten importieren',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Auswahl abgebrochen.')),
        );
      }
      return;
    }

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
        );
      }
      return;
    }

    try {
      await ref.read(fleetProvider.notifier).importJson(utf8.decode(bytes));
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              restore
                  ? 'Sicherung wurde wiederhergestellt.'
                  : 'Daten wurden importiert.',
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Die Datei ist keine gueltige Modellflug-Sicherung.'),
          ),
        );
      }
    }
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 4),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: const TabBar(
        isScrollable: true,
        dividerColor: Colors.transparent,
        labelColor: Color(0xFF06172E),
        unselectedLabelColor: Color(0xFF64748B),
        labelStyle: TextStyle(fontWeight: FontWeight.w900),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _tabAccentColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        tabs: [
          _SettingsTab(icon: Icons.person_rounded, label: 'Benutzer'),
          _SettingsTab(icon: Icons.tune_rounded, label: 'App Einstellungen'),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SettingsTab({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _PilotProfileCard extends StatefulWidget {
  final PilotProfile profile;
  final ValueChanged<PilotProfile> onSave;

  const _PilotProfileCard({
    required this.profile,
    required this.onSave,
  });

  @override
  State<_PilotProfileCard> createState() => _PilotProfileCardState();
}

class _PilotProfileCardState extends State<_PilotProfileCard> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _homeAirfield;
  late final TextEditingController _club;
  late final TextEditingController _licenseNumber;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  final List<TextEditingController> _transmitters = [];
  final List<TextEditingController> _flightAreas = [];
  late final TextEditingController _notes;
  String? _photoDataUri;
  String? _insuranceDocumentName;
  String? _insuranceDocumentDataUri;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _homeAirfield = TextEditingController(text: widget.profile.homeAirfield);
    _club = TextEditingController(text: widget.profile.club);
    _licenseNumber = TextEditingController(text: widget.profile.licenseNumber);
    _phone = TextEditingController(text: widget.profile.phone);
    _email = TextEditingController(text: widget.profile.email);
    _syncTransmitterControllers(widget.profile.transmitters);
    _syncFlightAreaControllers(widget.profile.flightAreas);
    _notes = TextEditingController(text: widget.profile.notes);
    _photoDataUri = widget.profile.photoDataUri;
    _insuranceDocumentName = widget.profile.insuranceDocumentName;
    _insuranceDocumentDataUri = widget.profile.insuranceDocumentDataUri;
  }

  @override
  void didUpdateWidget(covariant _PilotProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile == widget.profile) {
      return;
    }
    _name.text = widget.profile.name;
    _homeAirfield.text = widget.profile.homeAirfield;
    _club.text = widget.profile.club;
    _licenseNumber.text = widget.profile.licenseNumber;
    _phone.text = widget.profile.phone;
    _email.text = widget.profile.email;
    _syncTransmitterControllers(widget.profile.transmitters);
    _syncFlightAreaControllers(widget.profile.flightAreas);
    _notes.text = widget.profile.notes;
    _photoDataUri = widget.profile.photoDataUri;
    _insuranceDocumentName = widget.profile.insuranceDocumentName;
    _insuranceDocumentDataUri = widget.profile.insuranceDocumentDataUri;
  }

  @override
  void dispose() {
    _name.dispose();
    _homeAirfield.dispose();
    _club.dispose();
    _licenseNumber.dispose();
    _phone.dispose();
    _email.dispose();
    for (final controller in _transmitters) {
      controller.dispose();
    }
    for (final controller in _flightAreas) {
      controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profil',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  _PilotPhoto(
                    photoDataUri: _photoDataUri,
                    editing: _editing,
                    onTap: _showPhotoOptions,
                  ),
                  SizedBox(
                    width: 560,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ProfileField(
                          controller: _name,
                          label: 'Pilot',
                          enabled: _editing,
                        ),
                        _ProfileField(
                          controller: _homeAirfield,
                          label: 'Heimatplatz',
                          enabled: _editing,
                        ),
                        _ProfileField(
                          controller: _club,
                          label: 'Verein',
                          enabled: _editing,
                        ),
                        _ProfileField(
                          controller: _licenseNumber,
                          label: 'e-ID',
                          requiredField: false,
                          enabled: _editing,
                        ),
                        _ProfileField(
                          controller: _phone,
                          label: 'Telefon',
                          requiredField: false,
                          enabled: _editing,
                        ),
                        _ProfileField(
                          controller: _email,
                          label: 'E-Mail',
                          requiredField: false,
                          enabled: _editing,
                        ),
                        SizedBox(
                          width: 532,
                          child: _TransmitterFields(
                            controllers: _transmitters,
                            enabled: _editing,
                            onAdd: _addTransmitterField,
                            onRemove: _removeTransmitterField,
                          ),
                        ),
                        SizedBox(
                          width: 532,
                          child: _FlightAreaFields(
                            controllers: _flightAreas,
                            enabled: _editing,
                            onAdd: _addFlightAreaField,
                            onRemove: _removeFlightAreaField,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 798,
                child: _InsuranceDocumentBox(
                  fileName: _insuranceDocumentName,
                  dataUri: _insuranceDocumentDataUri,
                  enabled: _editing,
                  onPick: _pickInsuranceDocument,
                  onRemove: _insuranceDocumentName == null || !_editing
                      ? null
                      : () => setState(() {
                            _insuranceDocumentName = null;
                            _insuranceDocumentDataUri = null;
                          }),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_editing)
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Profil speichern'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Profil bearbeiten'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _StorageNote(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1000,
    );

    if (pickedImage == null) {
      return;
    }

    final bytes = await pickedImage.readAsBytes();
    final mimeType = _mimeTypeForName(pickedImage.name);
    setState(() {
      _photoDataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _pickInsuranceDocument() async {
    if (!_editing) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );

    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }

    setState(() {
      _insuranceDocumentName = file.name;
      _insuranceDocumentDataUri =
          'data:${_mimeTypeForName(file.name)};base64,${base64Encode(bytes)}';
    });
  }

  void _syncTransmitterControllers(List<String> transmitters) {
    for (final controller in _transmitters) {
      controller.dispose();
    }
    _transmitters
      ..clear()
      ..addAll(
        (transmitters.isEmpty ? [''] : transmitters).map(
          (transmitter) => TextEditingController(text: transmitter),
        ),
      );
  }

  void _addTransmitterField() {
    setState(() => _transmitters.add(TextEditingController()));
  }

  void _removeTransmitterField(int index) {
    if (_transmitters.length <= 1) {
      return;
    }
    final controller = _transmitters.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  void _syncFlightAreaControllers(List<String> flightAreas) {
    for (final controller in _flightAreas) {
      controller.dispose();
    }
    _flightAreas
      ..clear()
      ..addAll(
        (flightAreas.isEmpty ? [''] : flightAreas).map(
          (flightArea) => TextEditingController(text: flightArea),
        ),
      );
  }

  void _addFlightAreaField() {
    setState(() => _flightAreas.add(TextEditingController()));
  }

  void _removeFlightAreaField(int index) {
    if (_flightAreas.length <= 1) {
      return;
    }
    final controller = _flightAreas.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  Future<void> _showPhotoOptions() async {
    if (!_editing) {
      return;
    }

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title:
                  Text(_photoDataUri == null ? 'Foto waehlen' : 'Foto aendern'),
              onTap: () => Navigator.of(context).pop(_PhotoAction.pick),
            ),
            if (_photoDataUri != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Foto entfernen'),
                onTap: () => Navigator.of(context).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    if (action == _PhotoAction.pick) {
      await _pickPhoto();
    }
    if (action == _PhotoAction.remove) {
      setState(() => _photoDataUri = null);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    widget.onSave(
      PilotProfile(
        name: _name.text.trim(),
        homeAirfield: _homeAirfield.text.trim(),
        club: _club.text.trim(),
        licenseNumber: _licenseNumber.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        flightAreas: [
          for (final controller in _flightAreas)
            if (controller.text.trim().isNotEmpty) controller.text.trim(),
        ],
        transmitters: [
          for (final controller in _transmitters)
            if (controller.text.trim().isNotEmpty) controller.text.trim(),
        ],
        notes: _notes.text.trim(),
        photoDataUri: _photoDataUri,
        insuranceDocumentName: _insuranceDocumentName,
        insuranceDocumentDataUri: _insuranceDocumentDataUri,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pilotprofil gespeichert.')),
    );
    setState(() => _editing = false);
  }
}

enum _PhotoAction { pick, remove }

class _PilotPhoto extends StatelessWidget {
  final String? photoDataUri;
  final bool editing;
  final VoidCallback onTap;

  const _PilotPhoto({
    required this.photoDataUri,
    required this.editing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: editing ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: photoDataUri == null
                        ? Container(
                            color: const Color(0xFFEFF6FF),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF0A84FF),
                              size: 82,
                            ),
                          )
                        : Image.memory(
                            _bytesFromDataUri(photoDataUri!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                if (editing)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A84FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            const Text(
              'Foto anklicken zum Aendern oder Loeschen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransmitterFields extends StatelessWidget {
  static const _senderIconAsset = 'assets/icons/sender.jpg';

  final List<TextEditingController> controllers;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _TransmitterFields({
    required this.controllers,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < controllers.length; index++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox.square(
                  dimension: 38,
                  child: Image.asset(
                    _senderIconAsset,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: controllers[index],
                  readOnly: !enabled,
                  style: const TextStyle(
                    color: Color(0xFF06172E),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Sender ${index + 1}',
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (enabled && controllers.length > 1) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Sender entfernen',
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
          if (index < controllers.length - 1) const SizedBox(height: 10),
        ],
        if (enabled) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('weiterer Sender'),
          ),
        ],
      ],
    );
  }
}

class _FlightAreaFields extends StatelessWidget {
  final List<TextEditingController> controllers;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _FlightAreaFields({
    required this.controllers,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < controllers.length; index++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 38,
                child: Icon(
                  Icons.place_rounded,
                  color: Color(0xFF0A84FF),
                  size: 28,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: controllers[index],
                  readOnly: !enabled,
                  style: const TextStyle(
                    color: Color(0xFF06172E),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: index == 0
                        ? 'Weiteres Fluggebiet'
                        : 'Fluggebiet ${index + 1}',
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (enabled && controllers.length > 1) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Fluggebiet entfernen',
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
          if (index < controllers.length - 1) const SizedBox(height: 10),
        ],
        if (enabled) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('weiteres Fluggebiet'),
          ),
        ],
      ],
    );
  }
}

class _InsuranceDocumentBox extends StatelessWidget {
  final String? fileName;
  final String? dataUri;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _InsuranceDocumentBox({
    required this.fileName,
    required this.dataUri,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasDocument = fileName != null && fileName!.isNotEmpty;
    final isImage = dataUri != null && dataUri!.startsWith('data:image/');

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onPick : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (!isImage) ...[
                  const SizedBox.square(
                    dimension: 38,
                    child: _InsuranceDocumentIcon(),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Versicherungsnachweis',
                        style: TextStyle(
                          color: Color(0xFF06172E),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDocument
                            ? fileName!
                            : enabled
                                ? 'PDF oder Bilddatei auswaehlen'
                                : 'Noch kein Dokument hinterlegt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(hasDocument ? 'Aendern' : 'Einladen'),
                  ),
                ],
                if (onRemove != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Dokument entfernen',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
            if (isImage) ...[
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 11),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.memory(
                        _bytesFromDataUri(dataUri!),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 120,
                          color: const Color(0xFFEFF6FF),
                          child: const Center(
                            child: _InsuranceDocumentIcon(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsuranceDocumentIcon extends StatelessWidget {
  const _InsuranceDocumentIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF6FF),
      child: const Icon(
        Icons.cloud_upload_rounded,
        color: Color(0xFF0A84FF),
        size: 28,
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool requiredField;
  final bool enabled;

  const _ProfileField({
    required this.controller,
    required this.label,
    this.requiredField = true,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        readOnly: !enabled,
        style: const TextStyle(
          color: Color(0xFF06172E),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        validator: requiredField
            ? (value) =>
                value == null || value.trim().isEmpty ? 'Pflichtfeld' : null
            : null,
      ),
    );
  }
}

class _StorageNote extends StatelessWidget {
  const _StorageNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        children: [
          Icon(Icons.storage_rounded, color: Color(0xFF0A84FF)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Profil, Foto und Nachweis werden lokal im App-Zustand gespeichert.',
              style: TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSettingsCard extends StatelessWidget {
  final AppSettings settings;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final ValueChanged<bool> onLocationSharingChanged;
  final ValueChanged<bool> onChatReachabilityChanged;
  final ValueChanged<AppSettings> onSettingsChanged;

  const _AppSettingsCard({
    required this.settings,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onLocationSharingChanged,
    required this.onChatReachabilityChanged,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App Einstellungen',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _SettingsSectionGrid(
              children: [
                _SettingsSection(
                  title: 'Freigaben fuer Freunde',
                  icon: Icons.group_rounded,
                  children: [
                    _LocationShareSwitch(
                      value: settings.shareLocationWithFriends,
                      presenceStatus: settings.presenceStatus,
                      onChanged: onLocationSharingChanged,
                    ),
                    _ChatReachabilitySwitch(
                      value: settings.reachableByChat,
                      onChanged: onChatReachabilityChanged,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Benachrichtigungen',
                  icon: Icons.notifications_active_rounded,
                  children: [
                    _NotificationCheckTile(
                      icon: Icons.group_rounded,
                      title: 'Freunde am Platz',
                      description:
                          'Regelmaessige Pruefung, ob Freunde am Flugplatz sind.',
                      value: settings.notifyFriendsAtField,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(notifyFriendsAtField: value),
                      ),
                    ),
                    _NotificationCheckTile(
                      icon: Icons.battery_alert_rounded,
                      title: 'Akku-Grenzwertueberschreitungen',
                      description:
                          'Meldet zu viele Zyklen, Alterswarnungen und lagernde volle Akkus.',
                      value: settings.notifyBatteryLimits,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(notifyBatteryLimits: value),
                      ),
                    ),
                    _NotificationCheckTile(
                      icon: Icons.build_circle_rounded,
                      title: 'Reparaturen an Modellen',
                      description:
                          'Meldet eingetragene Reparaturarbeiten an Modellflugzeugen.',
                      value: settings.notifyRepairs,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(notifyRepairs: value),
                      ),
                    ),
                    _NotificationCheckTile(
                      icon: Icons.wb_sunny_rounded,
                      title: 'Gute Flugbedingungen',
                      description:
                          'Meldet wenig Wind und Sonnenschein an eingetragenen Fluggebieten.',
                      value: settings.notifyGoodWeather,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(notifyGoodWeather: value),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Region und Darstellung',
                  icon: Icons.public_rounded,
                  children: [
                    _DropdownSettingTile(
                      icon: Icons.schedule_rounded,
                      title: 'Zeitzone',
                      value: settings.timeZone,
                      values: const [
                        'Europe/Berlin',
                        'Europe/London',
                        'UTC',
                        'America/New_York',
                      ],
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(timeZone: value),
                      ),
                    ),
                    _DropdownSettingTile(
                      icon: Icons.social_distance_rounded,
                      title: 'Entfernung',
                      value: settings.distanceUnit,
                      values: const ['km', 'mi'],
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(distanceUnit: value),
                      ),
                    ),
                    _DropdownSettingTile(
                      icon: Icons.air_rounded,
                      title: 'Wind',
                      value: settings.windUnit,
                      values: const ['km/h', 'm/s', 'kn'],
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(windUnit: value),
                      ),
                    ),
                    _DropdownSettingTile(
                      icon: Icons.thermostat_rounded,
                      title: 'Temperatur',
                      value: settings.temperatureUnit,
                      values: const ['Celsius', 'Fahrenheit'],
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(temperatureUnit: value),
                      ),
                    ),
                    _DropdownSettingTile(
                      icon: Icons.language_rounded,
                      title: 'Sprache',
                      value: settings.language,
                      values: const ['Deutsch', 'English'],
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(language: value),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Sicherung',
                  icon: Icons.backup_rounded,
                  children: [
                    const _AppSettingTile(
                      icon: Icons.history_rounded,
                      title: 'Letzte Sicherung',
                      value: 'Heute, 06:30',
                    ),
                    const _AppSettingTile(
                      icon: Icons.event_repeat_rounded,
                      title: 'Naechste automatische Sicherung',
                      value: 'Morgen, 06:30',
                    ),
                    _ActionSettingTile(
                      icon: Icons.restore_rounded,
                      title: 'Sicherung wiederherstellen',
                      value: 'Aus Backup auswaehlen',
                      onTap: onRestoreBackup,
                    ),
                    _ButtonSettingTile(
                      icon: Icons.backup_rounded,
                      label: 'Jetzt sichern',
                      onPressed: onCreateBackup,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Synchronisation und Cloud',
                  icon: Icons.cloud_sync_rounded,
                  children: [
                    const _AppSettingTile(
                      icon: Icons.wifi_tethering_rounded,
                      title: 'Verbindung',
                      value: 'Vorbereitet',
                    ),
                    const _AppSettingTile(
                      icon: Icons.backup_table_rounded,
                      title: 'Automatische Sicherung',
                      value: 'Aktivierbar',
                    ),
                    _SwitchSettingTile(
                      icon: Icons.wifi_rounded,
                      title: 'Nur ueber WLAN synchronisieren?',
                      value: settings.wifiOnlySync,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(wifiOnlySync: value),
                      ),
                    ),
                    const _ButtonSettingTile(
                      icon: Icons.sync_rounded,
                      label: 'Jetzt synchronisieren',
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Webcams',
                  icon: Icons.videocam_rounded,
                  children: [
                    _WebcamSourcesEditor(
                      webcams: settings.webcams,
                      webcamUrls: settings.webcamUrls,
                      onChanged: (webcams, webcamUrls) => onSettingsChanged(
                        settings.copyWith(
                          webcams: webcams,
                          webcamUrls: webcamUrls,
                        ),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Akku Arten',
                  titleNote: 'Anzeige nach Anwahl auf der Akku-Seite',
                  icon: Icons.battery_charging_full_rounded,
                  children: [
                    _BatteryTypesSelector(
                      selectedTypes: settings.batteryTypes,
                      onChanged: (types) => onSettingsChanged(
                        settings.copyWith(batteryTypes: types),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Akku-Grenzwerte',
                  icon: Icons.battery_alert_rounded,
                  children: [
                    _NumericSettingTile(
                      icon: Icons.repeat_rounded,
                      title:
                          'Zustand problematisch bei dieser Anzahl Akku-Zyklen',
                      suffix: 'Zyklen',
                      value: settings.batteryProblemCycleThreshold,
                      fallback: 300,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(
                          batteryProblemCycleThreshold: value,
                        ),
                      ),
                    ),
                    _NumericSettingTile(
                      icon: Icons.schedule_rounded,
                      title:
                          'Hinweis auf Reduzierung auf Lagerspannung bei vollen Akkus',
                      suffix: 'Tage',
                      value: settings.fullBatteryStorageReminderDays,
                      fallback: 3,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(
                          fullBatteryStorageReminderDays: value,
                        ),
                      ),
                    ),
                    _NumericSettingTile(
                      icon: Icons.event_repeat_rounded,
                      title: 'Hinweis auf Akku-Alter nach Jahren',
                      suffix: 'Jahre',
                      value: settings.batteryAgeWarningYears,
                      fallback: 5,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(
                          batteryAgeWarningYears: value,
                        ),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'App-Informationen',
                  icon: Icons.info_rounded,
                  children: [
                    const _AppSettingTile(
                      icon: Icons.new_releases_rounded,
                      title: 'Version',
                      value: '1.0.0+1',
                    ),
                    const _ActionSettingTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Was ist neu',
                      value: 'Aenderungen anzeigen',
                    ),
                    _ActionSettingTile(
                      icon: Icons.contact_mail_rounded,
                      title: 'Kontakt',
                      value: 'Adresse anzeigen',
                      onTap: () => _showContactDialog(context),
                    ),
                    _ActionSettingTile(
                      icon: Icons.feedback_rounded,
                      title: 'Feedback senden',
                      value: 'Rueckmeldung geben',
                      onTap: () => _showFeedbackDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryTypesSelector extends StatelessWidget {
  final List<String> selectedTypes;
  final ValueChanged<List<String>> onChanged;

  const _BatteryTypesSelector({
    required this.selectedTypes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedTypes.toSet();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final type in defaultBatteryTypes)
            FilterChip(
              label: Text(type),
              selected: selected.contains(type),
              onSelected: (value) {
                final next = {...selected};
                if (value) {
                  next.add(type);
                } else if (next.length > 1) {
                  next.remove(type);
                }
                onChanged([
                  for (final option in defaultBatteryTypes)
                    if (next.contains(option)) option,
                ]);
              },
              selectedColor: const Color(0xFFEAF3FF),
              checkmarkColor: const Color(0xFF0A84FF),
              labelStyle: TextStyle(
                color: selected.contains(type)
                    ? const Color(0xFF06172E)
                    : const Color(0xFF475569),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _NumericSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String suffix;
  final int value;
  final int fallback;
  final ValueChanged<int> onChanged;

  const _NumericSettingTile({
    required this.icon,
    required this.title,
    required this.suffix,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: TextFormField(
              initialValue: '$value',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF06172E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                suffixText: suffix,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              ),
              onChanged: (text) {
                final parsed = int.tryParse(text.trim());
                onChanged(parsed == null || parsed < 0 ? fallback : parsed);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebcamSourcesEditor extends StatefulWidget {
  final List<String> webcams;
  final List<String> webcamUrls;
  final void Function(List<String> webcams, List<String> webcamUrls) onChanged;

  const _WebcamSourcesEditor({
    required this.webcams,
    required this.webcamUrls,
    required this.onChanged,
  });

  @override
  State<_WebcamSourcesEditor> createState() => _WebcamSourcesEditorState();
}

class _WebcamSourcesEditorState extends State<_WebcamSourcesEditor> {
  late List<TextEditingController> _controllers;
  late List<TextEditingController> _urlControllers;

  @override
  void initState() {
    super.initState();
    _controllers = _buildControllers(widget.webcams);
    _urlControllers = _buildUrlControllers(widget.webcams, widget.webcamUrls);
  }

  @override
  void didUpdateWidget(covariant _WebcamSourcesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.webcams.join('|') != widget.webcams.join('|') ||
        oldWidget.webcamUrls.join('|') != widget.webcamUrls.join('|')) {
      for (final controller in _controllers) {
        controller.dispose();
      }
      for (final controller in _urlControllers) {
        controller.dispose();
      }
      _controllers = _buildControllers(widget.webcams);
      _urlControllers = _buildUrlControllers(widget.webcams, widget.webcamUrls);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final controller in _urlControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> _buildControllers(List<String> values) {
    final source = values.isEmpty ? defaultWebcams : values;
    return [for (final value in source) TextEditingController(text: value)];
  }

  List<TextEditingController> _buildUrlControllers(
    List<String> webcams,
    List<String> urls,
  ) {
    final source = webcams.isEmpty ? defaultWebcams : webcams;
    return [
      for (var index = 0; index < source.length; index++)
        TextEditingController(text: index < urls.length ? urls[index] : ''),
    ];
  }

  void _emit() {
    final names = <String>[];
    final urls = <String>[];
    for (var index = 0; index < _controllers.length; index++) {
      final name = _controllers[index].text.trim();
      if (name.isEmpty) {
        continue;
      }
      names.add(name);
      urls.add(index < _urlControllers.length
          ? _urlControllers[index].text.trim()
          : '');
    }
    widget.onChanged(names.isEmpty ? ['Webcam'] : names, urls);
  }

  Future<void> _editUrl(int index) async {
    final controller = _urlControllers[index];
    final editor = TextEditingController(text: controller.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Internet-Adresse ${index + 1}'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: editor,
            decoration: const InputDecoration(
              labelText: 'Webcam-URL',
              hintText: 'https://...',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editor.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (result == null) {
      return;
    }
    setState(() {
      controller.text = result;
      _emit();
    });
  }

  void _addWebcam() {
    setState(() {
      _controllers.add(TextEditingController());
      _urlControllers.add(TextEditingController());
    });
  }

  void _removeWebcam(int index) {
    setState(() {
      _controllers.removeAt(index).dispose();
      _urlControllers.removeAt(index).dispose();
      _emit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var index = 0; index < _controllers.length; index++) ...[
            Row(
              children: [
                const Icon(
                  Icons.videocam_rounded,
                  color: Color(0xFF0A84FF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _controllers[index],
                    style: const TextStyle(
                      color: Color(0xFF06172E),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Webcam ${index + 1}',
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Internet-Adresse eingeben',
                  onPressed: () => _editUrl(index),
                  icon: Icon(
                    _urlControllers[index].text.trim().isEmpty
                        ? Icons.link_rounded
                        : Icons.link_rounded,
                    color: _urlControllers[index].text.trim().isEmpty
                        ? const Color(0xFF64748B)
                        : const Color(0xFF0A84FF),
                  ),
                ),
                if (_controllers.length > 1) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Webcam entfernen',
                    onPressed: () => _removeWebcam(index),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
            if (index < _controllers.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addWebcam,
              icon: const Icon(Icons.add_rounded),
              label: const Text('weitere Webcam'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonSettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ButtonSettingTile({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

class _LocationShareSwitch extends StatelessWidget {
  final bool value;
  final LocationPresenceStatus presenceStatus;
  final ValueChanged<bool> onChanged;

  const _LocationShareSwitch({
    required this.value,
    required this.presenceStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_rounded,
            color: Color(0xFF0A84FF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Standortfreigabe fuer Freunde',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Freunde sehen, ob du am Platz bist.'
                      : 'Alles bleibt alles anonym.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value ? 'Ja' : 'Nein',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.82,
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatReachabilitySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ChatReachabilitySwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.chat_bubble_rounded,
            color: Color(0xFF0A84FF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Erreichbar durch Chat',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Chatfunktion aktiv!'
                      : 'Kein Chat, keine Verbindung von und zu Freunden.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value ? 'Ja' : 'Nein',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.82,
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCheckTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotificationCheckTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value ? 'Ein' : 'Aus',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionGrid extends StatelessWidget {
  final List<Widget> children;

  const _SettingsSectionGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        final width = columns == 1
            ? double.infinity
            : (constraints.maxWidth - (10 * (columns - 1))) / columns;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children)
              SizedBox(
                width: width,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String? titleNote;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    this.titleNote,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final separatedChildren = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        separatedChildren.add(
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
        );
      }
      separatedChildren.add(children[index]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF0A84FF), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Color(0xFF06172E),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                      children: [
                        TextSpan(text: title),
                        if (titleNote != null)
                          TextSpan(
                            text: ' ($titleNote)',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...separatedChildren,
        ],
      ),
    );
  }
}

class _DropdownSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  const _DropdownSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = values.contains(value) ? value : values.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 250;

        final label = Row(
          children: [
            Icon(icon, color: const Color(0xFF0A84FF), size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );

        final dropdown = DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: safeValue,
            isExpanded: true,
            isDense: true,
            icon: const Icon(Icons.expand_more_rounded, size: 17),
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            items: [
              for (final option in values)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 5),
                SizedBox(width: double.infinity, child: dropdown),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: 8),
              SizedBox(width: 150, child: dropdown),
            ],
          ),
        );
      },
    );
  }
}

class _ActionSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _ActionSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _AppSettingTile(
      icon: icon,
      title: title,
      value: value,
      trailingIcon: Icons.chevron_right_rounded,
      onTap: onTap,
    );
  }
}

class _AppSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  const _AppSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueWidth = constraints.maxWidth >= 430 ? 190.0 : 140.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF0A84FF), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: valueWidth,
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      trailingIcon,
                      color: const Color(0xFF94A3B8),
                      size: 17,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SwitchSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value ? 'Ja' : 'Nein',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.82,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

Future<void> _showFeedbackDialog(BuildContext context) async {
  final subjectController = TextEditingController();
  final messageController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Feedback senden'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Empfaenger: teddroste@me.com',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Betreff',
                  prefixIcon: Icon(Icons.subject_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 5,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'Nachricht',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.mail_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Feedback an teddroste@me.com wurde vorbereitet.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Senden'),
          ),
        ],
      );
    },
  );

  subjectController.dispose();
  messageController.dispose();
}

Future<void> _showContactDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Kontakt'),
        content: const SizedBox(
          width: 360,
          child: Text(
            'Theodor Droste\nMengeder Str. 15\n44805 Bochum\nGermany',
            style: TextStyle(
              color: Color(0xFF334155),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schliessen'),
          ),
        ],
      );
    },
  );
}

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}

String _mimeTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
