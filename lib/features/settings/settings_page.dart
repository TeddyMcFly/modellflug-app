import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

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
              SizedBox(
                height: 650,
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: _PilotProfileCard(
                        profile: fleet.pilotProfile,
                        onSave: (profile) => ref
                            .read(fleetProvider.notifier)
                            .updatePilotProfile(profile),
                      ),
                    ),
                    SingleChildScrollView(
                      child: _AppSettingsCard(
                        settings: fleet.appSettings,
                        onLocationSharingChanged: (value) => ref
                            .read(fleetProvider.notifier)
                            .updateLocationSharing(value),
                        onChatReachabilityChanged: (value) => ref
                            .read(fleetProvider.notifier)
                            .updateChatReachability(value),
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
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 4),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.white, width: 1),
        ),
      ),
      child: const TabBar(
        isScrollable: true,
        dividerColor: Colors.transparent,
        labelColor: Color(0xFF06172E),
        unselectedLabelColor: Color(0xFF64748B),
        labelStyle: TextStyle(fontWeight: FontWeight.w900),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(
            top: BorderSide(color: Colors.white, width: 1),
            left: BorderSide(color: Colors.white, width: 1),
            right: BorderSide(color: Colors.white, width: 1),
          ),
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_rounded),
                SizedBox(width: 8),
                Text('Benutzer'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded),
                SizedBox(width: 8),
                Text('App Einstellungen'),
              ],
            ),
          ),
        ],
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
  late final TextEditingController _notes;
  String? _photoDataUri;
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
    _notes = TextEditingController(text: widget.profile.notes);
    _photoDataUri = widget.profile.photoDataUri;
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
    _notes.text = widget.profile.notes;
    _photoDataUri = widget.profile.photoDataUri;
  }

  @override
  void dispose() {
    _name.dispose();
    _homeAirfield.dispose();
    _club.dispose();
    _licenseNumber.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilotprofil',
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
                          child: TextFormField(
                            controller: _notes,
                            readOnly: !_editing,
                            style: const TextStyle(
                              color: Color(0xFF06172E),
                              fontWeight: FontWeight.w700,
                            ),
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                                labelText: 'Profilnotizen'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
        notes: _notes.text.trim(),
        photoDataUri: _photoDataUri,
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
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(labelText: label),
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
              'Profil und Foto werden lokal im App-Zustand gespeichert.',
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
  final ValueChanged<bool> onLocationSharingChanged;
  final ValueChanged<bool> onChatReachabilityChanged;

  const _AppSettingsCard({
    required this.settings,
    required this.onLocationSharingChanged,
    required this.onChatReachabilityChanged,
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
            _LocationShareSwitch(
              value: settings.shareLocationWithFriends,
              presenceStatus: settings.presenceStatus,
              onChanged: onLocationSharingChanged,
            ),
            _ChatReachabilitySwitch(
              value: settings.reachableByChat,
              onChanged: onChatReachabilityChanged,
            ),
            const SizedBox(height: 10),
            const _AppSettingTile(
              icon: Icons.cloud_sync_rounded,
              title: 'Cloud-Synchronisation',
              value: 'Vorbereitet',
            ),
            const _AppSettingTile(
              icon: Icons.storage_rounded,
              title: 'Lokaler Bestand',
              value: 'Aktiv',
            ),
            const _AppSettingTile(
              icon: Icons.notifications_active_rounded,
              title: 'Benachrichtigungen',
              value: 'Standard',
            ),
          ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: Color(0xFF0A84FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Standortfreigabe fuer Freunde',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  'Freunde sehen deinen Status: ${presenceStatus.label}.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value ? 'Ja' : 'Nein',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_rounded, color: Color(0xFF0A84FF)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Erreichbar durch Chat',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 2),
                Text(
                  'Bei Nein ist die Chatfunktion fuer Freunde ausgeblendet.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value ? 'Ja' : 'Nein',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AppSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _AppSettingTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}

String _mimeTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
