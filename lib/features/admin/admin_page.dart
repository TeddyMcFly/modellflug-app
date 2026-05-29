import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/admin_access.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/starter_fleet_service.dart';
import '../../shared/services/user_device_service.dart';
import '../../shared/utils/centered_snack_bar.dart';
import '../../shared/utils/download_helper.dart';

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  final _jsonController = TextEditingController();
  bool _loading = true;
  bool _hasLocalOverride = false;
  String? _errorText;
  _StarterFleetSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadEffectiveStarterFleet();
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _loadEffectiveStarterFleet() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final content = await loadEffectiveStarterFleetJson();
      final override = await hasStarterFleetOverride();
      _setJsonContent(content, hasLocalOverride: override);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Starter-Datei konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  Future<void> _loadBundledStarterFleet() async {
    try {
      _setJsonContent(
        await loadBundledStarterFleetJson(),
        hasLocalOverride: await hasStarterFleetOverride(),
      );
      _showMessage('Eingebaute Starter-Datei geladen.');
    } catch (_) {
      _showMessage('Eingebaute Starter-Datei konnte nicht geladen werden.');
    }
  }

  Future<void> _loadJsonFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Starter-Datei laden',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        _showMessage('Laden abgebrochen.');
        return;
      }
      _setJsonContent(
        utf8.decode(bytes),
        hasLocalOverride: _hasLocalOverride,
      );
      _showMessage('Datei geladen.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Die ausgewaehlte Datei konnte nicht geladen werden.';
      });
      _showMessage('Datei konnte nicht geladen werden.');
    }
  }

  void _useCurrentAccount() {
    final fleet = ref.read(fleetProvider);
    _setJsonContent(
      starterFleetJsonFromState(fleet),
      hasLocalOverride: _hasLocalOverride,
    );
    _showMessage('Aktuelles Konto als Vorlage vorbereitet.');
  }

  void _setJsonContent(String content, {required bool hasLocalOverride}) {
    final normalized = normalizeStarterFleetJson(content);
    final parsed = parseStarterFleetState(normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _jsonController.text = normalized;
      _summary = _StarterFleetSummary.fromState(parsed);
      _hasLocalOverride = hasLocalOverride;
      _errorText = null;
      _loading = false;
    });
  }

  bool _validateJson({bool showSuccess = true}) {
    try {
      final normalized = normalizeStarterFleetJson(_jsonController.text);
      final parsed = parseStarterFleetState(normalized);
      setState(() {
        _jsonController.text = normalized;
        _summary = _StarterFleetSummary.fromState(parsed);
        _errorText = null;
      });
      if (showSuccess) {
        _showMessage('Starter-Datei ist gueltig.');
      }
      return true;
    } catch (error) {
      setState(() {
        _errorText = 'Die Starter-Datei enthaelt noch einen Fehler.';
      });
      _showMessage('Bitte die JSON-Datei pruefen.');
      return false;
    }
  }

  Future<void> _saveLocalOverride() async {
    if (!_validateJson(showSuccess: false)) {
      return;
    }
    await saveStarterFleetOverrideJson(_jsonController.text);
    if (!mounted) {
      return;
    }
    setState(() => _hasLocalOverride = true);
    _showMessage('Starter-Vorlage in dieser Browser-Vorschau gemerkt.');
  }

  Future<void> _clearLocalOverride() async {
    await clearStarterFleetOverride();
    if (!mounted) {
      return;
    }
    setState(() => _hasLocalOverride = false);
    await _loadBundledStarterFleet();
    _showMessage('Vorschau-Vorlage zurueckgesetzt.');
  }

  Future<void> _downloadStarterFleet() async {
    if (!_validateJson(showSuccess: false)) {
      return;
    }
    final content = normalizeStarterFleetJson(_jsonController.text);
    if (kIsWeb) {
      final saveResult = await saveTextFileResult(
        fileName: starterFleetFileName,
        content: content,
        mimeType: 'application/json',
        allowedExtensions: const ['json'],
        description: 'Modellflug Starter-Datei',
      );
      final fallbackStarted = saveResult == SaveFileResult.unavailable ||
          saveResult == SaveFileResult.failed;
      if (fallbackStarted) {
        downloadBytesFile(
          fileName: starterFleetFileName,
          bytes: Uint8List.fromList(utf8.encode(content)),
          mimeType: 'application/json',
        );
      }
      _showMessage(
        switch (saveResult) {
          SaveFileResult.saved =>
            'Starter-Datei wurde im gewaehlten Ordner gespeichert.',
          SaveFileResult.cancelled => 'Speichern abgebrochen.',
          SaveFileResult.unavailable =>
            'Dieser Browser kann keinen Speicherort waehlen. Die Datei wurde als Download gestartet.',
          SaveFileResult.failed =>
            'Die Datei konnte dort nicht geschrieben werden. Ein Download wurde stattdessen gestartet.',
        },
      );
      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Starter-Datei speichern',
      fileName: starterFleetFileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    _showMessage(
      path == null ? 'Speichern abgebrochen.' : 'Starter-Datei gespeichert.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    showCenteredSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final adminAllowed = authState.maybeWhen(
      data: (user) => isAdminEmail(user?.email),
      orElse: () => false,
    );
    final authResolved = authState.maybeWhen(
      data: (_) => true,
      orElse: () => false,
    );

    if (!authResolved) {
      return const AppScaffold(
        title: 'Admin',
        subtitle: 'Zugriff wird geprueft.',
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(22),
              child: LinearProgressIndicator(),
            ),
          ),
        ],
      );
    }

    if (!adminAllowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/dashboard');
        }
      });
      return const AppScaffold(
        title: 'Kein Zugriff',
        subtitle: 'Diese Seite ist nur fuer das Admin-Konto freigegeben.',
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'Du wirst zum Dashboard zurueckgeleitet.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    final summary = _summary;
    final deviceService = ref.watch(userDeviceServiceProvider);
    return AppScaffold(
      title: 'Admin',
      subtitle: 'Starter-Datei fuer neue Konten vorbereiten.',
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Starter-Vorlage',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _OverrideChip(active: _hasLocalOverride),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _useCurrentAccount,
                      icon: const Icon(Icons.account_circle_rounded),
                      label: const Text('Aus aktuellem Konto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loadBundledStarterFleet,
                      icon: const Icon(Icons.inventory_2_rounded),
                      label: const Text('Eingebaute Datei'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loadJsonFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Datei laden'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _validateJson(),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Pruefen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _saveLocalOverride,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('In Vorschau merken'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading || !_hasLocalOverride
                          ? null
                          : _clearLocalOverride,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Zuruecksetzen'),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : _downloadStarterFleet,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Als Datei speichern'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary != null) _StarterFleetSummaryBar(summary: summary),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: _errorText!),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 520,
                  child: TextField(
                    controller: _jsonController,
                    enabled: !_loading,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                      labelText: 'starter_fleet.json',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _DeviceAccessCard(service: deviceService),
      ],
    );
  }
}

class _OverrideChip extends StatelessWidget {
  final bool active;

  const _OverrideChip({required this.active});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.tune_rounded : Icons.inventory_2_rounded,
        size: 18,
      ),
      label: Text(active ? 'Vorschau geaendert' : 'Eingebaut'),
    );
  }
}

class _StarterFleetSummaryBar extends StatelessWidget {
  final _StarterFleetSummary summary;

  const _StarterFleetSummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryPill(
          icon: Icons.airplanemode_active_rounded,
          label: '${summary.aircraftCount} Modelle',
        ),
        _SummaryPill(
          icon: Icons.battery_charging_full_rounded,
          label: '${summary.batteryCount} Akkus',
        ),
        _SummaryPill(
          icon: Icons.menu_book_rounded,
          label: '${summary.flightCount} Fluege',
        ),
        _SummaryPill(
          icon: Icons.person_rounded,
          label: summary.pilotName.isEmpty ? 'Profil leer' : summary.pilotName,
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0A84FF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDA4AF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_rounded, color: Color(0xFFE11D48)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceAccessCard extends StatelessWidget {
  final UserDeviceService? service;

  const _DeviceAccessCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.devices_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Geraetezugriffe',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Diese Tabelle ist nur im Admin-Bereich sichtbar.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (service == null)
              const _DeviceAccessInfo(
                icon: Icons.cloud_off_rounded,
                title: 'Firebase nicht verbunden',
                message: 'Geraetezugriffe koennen gerade nicht geladen werden.',
              )
            else
              StreamBuilder<List<UserDeviceAccess>>(
                stream: service!.watchDeviceAccess(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _DeviceAccessInfo(
                      icon: Icons.error_rounded,
                      title: 'Geraete konnten nicht geladen werden',
                      message:
                          'Bitte pruefe, ob die Firestore-Regeln veroeffentlicht sind.',
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }

                  final records = snapshot.data ?? const <UserDeviceAccess>[];
                  if (records.isEmpty) {
                    return const _DeviceAccessInfo(
                      icon: Icons.devices_other_rounded,
                      title: 'Noch keine Eintraege',
                      message:
                          'Sobald sich ein Mitglied anmeldet, erscheint sein Browser oder Geraet hier.',
                    );
                  }

                  return _DeviceAccessTable(records: records);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceAccessTable extends StatelessWidget {
  final List<UserDeviceAccess> records;

  const _DeviceAccessTable({required this.records});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFEFF6FF)),
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('Mitglied')),
          DataColumn(label: Text('Geraet')),
          DataColumn(label: Text('Browser')),
          DataColumn(label: Text('Bildschirm')),
          DataColumn(label: Text('Zuletzt')),
          DataColumn(label: Text('Erstzugriff')),
        ],
        rows: [
          for (final record in records)
            DataRow(
              cells: [
                DataCell(
                  _DeviceAccessCell(
                    width: 190,
                    primary: record.displayName,
                    secondary: record.email ?? record.uid,
                  ),
                ),
                DataCell(
                  Tooltip(
                    message: record.userAgent.isEmpty
                        ? 'Keine Browserkennung'
                        : record.userAgent,
                    child: _DeviceAccessCell(
                      width: 170,
                      primary: record.deviceLabel,
                      secondary: 'ID ${record.shortDeviceId}',
                    ),
                  ),
                ),
                DataCell(
                  _DeviceAccessCell(
                    width: 150,
                    primary: record.browserLabel,
                    secondary: record.platform.isEmpty
                        ? record.operatingSystem
                        : record.platform,
                  ),
                ),
                DataCell(
                  _DeviceAccessCell(
                    width: 140,
                    primary: record.screenLabel,
                    secondary: 'Fenster ${record.viewportLabel}',
                  ),
                ),
                DataCell(
                  _DeviceAccessCell(
                    width: 140,
                    primary: _adminDateTimeLabel(record.lastSeenAt),
                    secondary: record.language.isEmpty ? '-' : record.language,
                  ),
                ),
                DataCell(
                  _DeviceAccessCell(
                    width: 140,
                    primary: _adminDateTimeLabel(record.firstSeenAt),
                    secondary: record.deviceType,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DeviceAccessCell extends StatelessWidget {
  final double width;
  final String primary;
  final String secondary;

  const _DeviceAccessCell({
    required this.width,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary.isEmpty ? '-' : primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            secondary.isEmpty ? '-' : secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceAccessInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _DeviceAccessInfo({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarterFleetSummary {
  final int aircraftCount;
  final int batteryCount;
  final int flightCount;
  final String pilotName;

  const _StarterFleetSummary({
    required this.aircraftCount,
    required this.batteryCount,
    required this.flightCount,
    required this.pilotName,
  });

  factory _StarterFleetSummary.fromState(FleetState state) {
    return _StarterFleetSummary(
      aircraftCount: state.aircraft.length,
      batteryCount: state.batteries.length,
      flightCount: state.flights.length,
      pilotName: state.pilotProfile.name.trim(),
    );
  }
}

String _adminDateTimeLabel(DateTime? date) {
  if (date == null) {
    return '-';
  }
  final local = date.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}
