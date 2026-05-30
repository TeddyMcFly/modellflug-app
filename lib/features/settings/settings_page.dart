import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/app_info_provider.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/admin_access.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/subscription_service.dart';
import '../../shared/services/webcam_url_diagnostics.dart';
import '../../shared/utils/centered_snack_bar.dart';
import '../../shared/utils/download_helper.dart';
import '../../shared/utils/image_thumbnail.dart';
import '../../shared/utils/media_source.dart';
import '../webcam/webcam_page.dart';

const _tabAccentColor = Colors.white;
final settingsProfileHasUnsavedChanges = ValueNotifier<bool>(false);

enum _FlightbookExportFormat { pdf, csv }

Future<bool> confirmLeaveSettingsProfile(BuildContext context) async {
  if (!settingsProfileHasUnsavedChanges.value) {
    return true;
  }

  final leaveWithoutSaving = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Profil-Aenderungen nicht gespeichert'),
      content: const Text(
        'Du hast dein Profil geaendert, aber noch nicht gespeichert. Moechtest du die Seite ohne Speichern verlassen?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Auf Seite bleiben'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Ohne Speichern verlassen'),
        ),
      ],
    ),
  );

  if (leaveWithoutSaving == true) {
    settingsProfileHasUnsavedChanges.value = false;
  }

  return leaveWithoutSaving ?? false;
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final authUser = ref.watch(authStateProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    final accountAccess = ref.watch(accountAccessProvider);
    final userEmail = authUser?.email;
    final canOpenAdmin = isAdminEmail(userEmail);

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
              _SettingsTabContent(
                userSettings: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PilotProfileCard(
                      profile: fleet.pilotProfile,
                      onSave: (profile) => ref
                          .read(fleetProvider.notifier)
                          .updatePilotProfile(profile),
                    ),
                    const SizedBox(height: 12),
                    _AccountCard(
                      userEmail: userEmail,
                      emailVerified: authUser?.emailVerified ?? false,
                      syncStatus: fleet.syncStatus,
                      accountAccess: accountAccess,
                      onSyncNow: () => _syncNow(context, ref),
                      onRequestActivation: () =>
                          _requestPaidActivation(context, ref),
                      onPasswordChange: () =>
                          _sendPasswordReset(context, ref, userEmail),
                      onVerifyEmail: () => _sendEmailVerification(context, ref),
                      onDeleteAccount: () =>
                          _showDeleteAccountPreparation(context),
                      onSignOut: () => _signOut(context, ref),
                    ),
                  ],
                ),
                appSettings: _AppSettingsCard(
                  settings: fleet.appSettings,
                  syncStatus: fleet.syncStatus,
                  userEmail: userEmail,
                  canOpenAdmin: canOpenAdmin,
                  onCreateBackup: () => _showBackupDialog(
                    context,
                    ref,
                  ),
                  onExportFlightbook: () => _showFlightbookExportDialog(
                    context,
                    ref,
                  ),
                  onRestoreBackup: () => _showRestoreBackupDialog(
                    context,
                    ref,
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
                  onSyncNow: () => _syncNow(context, ref),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestPaidActivation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    final subscriptionService = ref.read(subscriptionServiceProvider);
    if (user == null || subscriptionService == null) {
      showCenteredSnackBar(
        context,
        'Die Freischaltung braucht ein angemeldetes Konto.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bezahlversion aktivieren'),
        content: const Text(
          'Die App merkt sich in deinem Konto, dass du die Bezahlversion aktivieren moechtest. Die eigentliche Zahlung oder manuelle Freischaltung kann danach angeschlossen werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('Aktivierung anfragen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await subscriptionService.requestActivation(user);
      if (!context.mounted) {
        return;
      }
      showCenteredSnackBar(
        context,
        'Die Aktivierungsanfrage wurde gespeichert.',
      );
    } on Object {
      if (!context.mounted) {
        return;
      }
      showCenteredSnackBar(
        context,
        'Die Aktivierungsanfrage konnte nicht gespeichert werden.',
      );
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final canLeave = await confirmLeaveSettingsProfile(context);
    if (!canLeave) {
      return;
    }

    await ref.read(authControllerProvider).signOut();
    if (context.mounted) {
      context.go('/login');
    }
  }

  Future<void> _sendPasswordReset(
    BuildContext context,
    WidgetRef ref,
    String? userEmail,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final email = userEmail?.trim();
    if (email == null || email.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fuer dieses Konto fehlt die E-Mail.')),
      );
      return;
    }

    try {
      await ref.read(authControllerProvider).sendPasswordResetEmail(email);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Passwort-Link wurde an $email gesendet.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(authErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _sendEmailVerification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(authControllerProvider).sendEmailVerification();
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Bestaetigungs-E-Mail wurde versendet.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(authErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _showDeleteAccountPreparation(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konto loeschen vorbereiten'),
        content: const Text(
          'Diese Funktion ist vorbereitet, loescht aber noch nichts. Fuer echtes Loeschen muessen spaeter Konto, Cloud-Daten und gespeicherte Dateien gemeinsam entfernt werden.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Future<bool> _exportData(
    BuildContext context,
    WidgetRef ref, {
    bool backup = false,
    String? preferredFileName,
  }) async {
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
      final saveResult = await saveTextFileResult(
        fileName: fileName,
        content: rawJson,
        mimeType: 'application/json;charset=utf-8',
      );
      if (!context.mounted) {
        return saveResult == SaveFileResult.saved;
      }
      final fallbackStarted = saveResult == SaveFileResult.unavailable ||
          saveResult == SaveFileResult.failed;
      if (fallbackStarted) {
        downloadTextFile(
          fileName: fileName,
          content: rawJson,
          mimeType: 'application/json;charset=utf-8',
        );
      }
      showCenteredSnackBar(
        context,
        switch (saveResult) {
          SaveFileResult.saved =>
            backup ? 'Sicherung wurde erstellt.' : 'Daten wurden exportiert.',
          SaveFileResult.cancelled => 'Speichern abgebrochen.',
          SaveFileResult.unavailable =>
            'Dieser Browser kann keinen Speicherort waehlen. Die Datei wurde als Download gestartet.',
          SaveFileResult.failed =>
            'Die Datei konnte dort nicht geschrieben werden. Ein Download wurde stattdessen gestartet.',
        },
      );
      return saveResult == SaveFileResult.saved || fallbackStarted;
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

    showCenteredSnackBar(
      context,
      savedPath == null
          ? 'Speichern abgebrochen.'
          : backup
              ? 'Sicherung wurde erstellt.'
              : 'Daten wurden exportiert.',
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

  Future<void> _showRestoreBackupDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final backups =
        await ref.read(fleetProvider.notifier).loadAutomaticBackups();

    if (!context.mounted) {
      return;
    }

    final selectedBackupId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sicherung wiederherstellen'),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Automatische Sicherungen liegen in der Cloud unter deinem Konto. Du kannst eine Cloud-Sicherung laden oder weiterhin eine JSON-Datei auswaehlen.',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (backups.isEmpty)
                const Text(
                  'Es wurde noch keine automatische Cloud-Sicherung gefunden.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final backup in backups)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.cloud_download_rounded,
                              color: Color(0xFF0A84FF),
                            ),
                            title: Text(_backupTitle(backup)),
                            subtitle: Text(_backupSubtitle(backup)),
                            onTap: () => Navigator.of(context).pop(backup.id),
                          ),
                      ],
                    ),
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
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('__file__'),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Datei auswaehlen'),
          ),
        ],
      ),
    );

    if (selectedBackupId == null) {
      return;
    }
    if (selectedBackupId == '__file__') {
      if (!context.mounted) {
        return;
      }
      await _importData(context, ref, restore: true);
      return;
    }

    final restored = await ref
        .read(fleetProvider.notifier)
        .restoreAutomaticBackup(selectedBackupId);
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Cloud-Sicherung wurde wiederhergestellt.'
              : 'Cloud-Sicherung konnte nicht geladen werden.',
        ),
      ),
    );
  }

  Future<void> _showFlightbookExportDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final fleet = ref.read(fleetProvider);
    if (fleet.flights.isEmpty) {
      showCenteredSnackBar(
        context,
        'Im Flugbuch sind noch keine Eintraege vorhanden.',
      );
      return;
    }

    final selectedFormat = await showDialog<_FlightbookExportFormat>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flugbuch exportieren'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Waehle das Format fuer den Export. CSV kann direkt mit Excel geoeffnet werden.',
            style: TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_FlightbookExportFormat.csv),
            icon: const Icon(Icons.table_chart_rounded),
            label: const Text('Excel / CSV'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_FlightbookExportFormat.pdf),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('PDF'),
          ),
        ],
      ),
    );

    if (selectedFormat == null || !context.mounted) {
      return;
    }

    final now = DateTime.now();
    final stamp = _exportFileStamp(now);
    switch (selectedFormat) {
      case _FlightbookExportFormat.csv:
        final content = _buildFlightbookCsv(fleet);
        await _saveFlightbookExport(
          context,
          fileName: 'modellflug_flugbuch_$stamp.csv',
          bytes: Uint8List.fromList(utf8.encode('\ufeff$content')),
          mimeType: 'text/csv;charset=utf-8',
          allowedExtensions: const ['csv'],
          description: 'Modellflug Flugbuch CSV',
          textContent: '\ufeff$content',
        );
      case _FlightbookExportFormat.pdf:
        final bytes = await _buildFlightbookPdf(fleet);
        if (!context.mounted) {
          return;
        }
        await _saveFlightbookExport(
          context,
          fileName: 'modellflug_flugbuch_$stamp.pdf',
          bytes: bytes,
          mimeType: 'application/pdf',
          allowedExtensions: const ['pdf'],
          description: 'Modellflug Flugbuch PDF',
        );
    }
  }

  Future<bool> _saveFlightbookExport(
    BuildContext context, {
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required List<String> allowedExtensions,
    required String description,
    String? textContent,
  }) async {
    if (kIsWeb) {
      final saveResult = textContent == null
          ? await saveBytesFileResult(
              fileName: fileName,
              bytes: bytes,
              mimeType: mimeType,
              allowedExtensions: allowedExtensions,
              description: description,
            )
          : await saveTextFileResult(
              fileName: fileName,
              content: textContent,
              mimeType: mimeType,
              allowedExtensions: allowedExtensions,
              description: description,
            );

      final fallbackStarted = saveResult == SaveFileResult.unavailable ||
          saveResult == SaveFileResult.failed;
      if (fallbackStarted) {
        if (textContent == null) {
          downloadBytesFile(
            fileName: fileName,
            bytes: bytes,
            mimeType: mimeType,
          );
        } else {
          downloadTextFile(
            fileName: fileName,
            content: textContent,
            mimeType: mimeType,
          );
        }
      }

      if (context.mounted) {
        showCenteredSnackBar(
          context,
          switch (saveResult) {
            SaveFileResult.saved => 'Flugbuch wurde als $fileName exportiert.',
            SaveFileResult.cancelled => 'Export abgebrochen.',
            SaveFileResult.unavailable =>
              'Dieser Browser kann keinen Speicherort waehlen. Das Flugbuch wurde als Download gestartet.',
            SaveFileResult.failed =>
              'Die Datei konnte dort nicht geschrieben werden. Ein Download wurde stattdessen gestartet.',
          },
        );
      }
      return saveResult == SaveFileResult.saved || fallbackStarted;
    }

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Flugbuch exportieren',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );

    if (!context.mounted) {
      return savedPath != null;
    }

    showCenteredSnackBar(
      context,
      savedPath == null
          ? 'Export abgebrochen.'
          : 'Flugbuch wurde als $fileName exportiert.',
    );
    return savedPath != null;
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final syncResult = await ref.read(fleetProvider.notifier).syncNow();

    if (!context.mounted) {
      return;
    }

    showCenteredSnackBar(
      context,
      switch (syncResult) {
        CloudSyncResult.synced => 'Daten wurden mit der Cloud synchronisiert.',
        CloudSyncResult.wifiRequired =>
          'Synchronisation wartet auf WLAN. Deine Daten bleiben lokal gespeichert.',
        CloudSyncResult.cloudUnavailable =>
          'Cloud-Synchronisation konnte nicht abgeschlossen werden. Bitte Internet und Anmeldung pruefen.',
      },
    );
  }

  Future<void> _importData(
    BuildContext context,
    WidgetRef ref, {
    bool restore = false,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: restore ? 'Sicherung wiederherstellen' : 'Daten importieren',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      if (context.mounted) {
        showCenteredSnackBar(context, 'Auswahl abgebrochen.');
      }
      return;
    }

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      if (context.mounted) {
        showCenteredSnackBar(context, 'Datei konnte nicht gelesen werden.');
      }
      return;
    }

    try {
      await ref.read(fleetProvider.notifier).importJson(utf8.decode(bytes));
      if (context.mounted) {
        showCenteredSnackBar(
          context,
          restore
              ? 'Sicherung wurde wiederhergestellt.'
              : 'Daten wurden importiert.',
        );
      }
    } on Object {
      if (context.mounted) {
        showCenteredSnackBar(
          context,
          'Die Datei ist keine gueltige Modellflug-Sicherung.',
        );
      }
    }
  }
}

class _FlightbookExportRow {
  final String date;
  final String aircraftName;
  final String location;
  final int durationMinutes;
  final int batteryPacks;
  final String batteryLabel;
  final String pilot;
  final String notes;

  const _FlightbookExportRow({
    required this.date,
    required this.aircraftName,
    required this.location,
    required this.durationMinutes,
    required this.batteryPacks,
    required this.batteryLabel,
    required this.pilot,
    required this.notes,
  });
}

String _buildFlightbookCsv(FleetState fleet) {
  final buffer = StringBuffer()
    ..writeln(
      [
        'Datum',
        'Modell',
        'Ort',
        'Dauer Minuten',
        'Akkus',
        'Akku',
        'Pilot',
        'Notizen',
      ].map(_csvCell).join(';'),
    );

  for (final row in _flightbookExportRows(fleet)) {
    buffer.writeln(
      [
        row.date,
        row.aircraftName,
        row.location,
        '${row.durationMinutes}',
        '${row.batteryPacks}',
        row.batteryLabel,
        row.pilot,
        row.notes,
      ].map(_csvCell).join(';'),
    );
  }

  return buffer.toString();
}

Future<Uint8List> _buildFlightbookPdf(FleetState fleet) async {
  final rows = _flightbookExportRows(fleet);
  final totalMinutes = rows.fold<int>(
    0,
    (sum, row) => sum + row.durationMinutes,
  );
  final document = pw.Document();

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'Flugbuch',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Exportiert am ${_formatExportDateTime(DateTime.now())}'),
        pw.Text(
          '${rows.length} Fluege, ${_formatExportDuration(totalMinutes)} Gesamtflugzeit',
        ),
        pw.SizedBox(height: 14),
        if (rows.isEmpty)
          pw.Text('Keine Flugbucheintraege vorhanden.')
        else
          pw.TableHelper.fromTextArray(
            headers: const [
              'Datum',
              'Modell',
              'Ort',
              'Dauer',
              'Akkus',
              'Akku',
              'Pilot',
              'Notizen',
            ],
            data: [
              for (final row in rows)
                [
                  row.date,
                  row.aircraftName,
                  row.location,
                  '${row.durationMinutes} min',
                  '${row.batteryPacks}',
                  row.batteryLabel,
                  row.pilot,
                  row.notes,
                ],
            ],
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blue50,
            ),
            headerStyle: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellPadding: const pw.EdgeInsets.all(4),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColors.grey100,
            ),
          ),
      ],
    ),
  );

  return document.save();
}

List<_FlightbookExportRow> _flightbookExportRows(FleetState fleet) {
  final aircraftNamesById = {
    for (final aircraft in fleet.aircraft) aircraft.id: aircraft.name,
  };
  final sortedFlights = [...fleet.flights]
    ..sort((a, b) => b.date.compareTo(a.date));

  return [
    for (final flight in sortedFlights)
      _FlightbookExportRow(
        date: _formatExportDate(flight.date),
        aircraftName:
            aircraftNamesById[flight.aircraftId] ?? 'Unbekanntes Modell',
        location: flight.location,
        durationMinutes: flight.durationMinutes,
        batteryPacks: flight.batteryPacks,
        batteryLabel: flight.batteryLabel,
        pilot: flight.pilot,
        notes: flight.notes,
      ),
  ];
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""').replaceAll('\r\n', '\n');
  return '"$escaped"';
}

String _exportFileStamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}${_twoDigits(local.month)}${_twoDigits(local.day)}_'
      '${_twoDigits(local.hour)}${_twoDigits(local.minute)}';
}

String _formatExportDate(DateTime value) {
  final local = value.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year}';
}

String _formatExportDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_formatExportDate(local)} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _formatExportDuration(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '$minutes min';
  }
  return '$hours h ${_twoDigits(minutes)} min';
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

class _SettingsTabContent extends StatelessWidget {
  final Widget userSettings;
  final Widget appSettings;

  const _SettingsTabContent({
    required this.userSettings,
    required this.appSettings,
  });

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selectedIndex = controller.index;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Visibility(
              visible: selectedIndex == 0,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: userSettings,
              ),
            ),
            Visibility(
              visible: selectedIndex == 1,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: appSettings,
              ),
            ),
          ],
        );
      },
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

class _AccountCard extends StatelessWidget {
  final String? userEmail;
  final bool emailVerified;
  final FleetSyncStatus syncStatus;
  final AsyncValue<AccountAccess> accountAccess;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onRequestActivation;
  final Future<void> Function() onPasswordChange;
  final Future<void> Function() onVerifyEmail;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function() onSignOut;

  const _AccountCard({
    required this.userEmail,
    required this.emailVerified,
    required this.syncStatus,
    required this.accountAccess,
    required this.onSyncNow,
    required this.onRequestActivation,
    required this.onPasswordChange,
    required this.onVerifyEmail,
    required this.onDeleteAccount,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final account = userEmail?.trim();
    final hasAccount = account != null && account.isNotEmpty;
    final cloudStatus = _accountCloudStatus(syncStatus, hasAccount);
    final access = accountAccess.valueOrNull;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_circle_rounded, color: Color(0xFF0A84FF)),
                SizedBox(width: 10),
                Text(
                  'Konto',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 2 : 1;
                final width = columns == 1
                    ? double.infinity
                    : (constraints.maxWidth - 10) / 2;

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _AccountInfoTile(
                        icon: Icons.alternate_email_rounded,
                        title: 'Angemeldet als',
                        value: hasAccount ? account : 'Kein Konto aktiv',
                        detail: emailVerified
                            ? 'E-Mail ist bestaetigt.'
                            : 'E-Mail ist noch nicht bestaetigt.',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _AccountInfoTile(
                        icon: cloudStatus.icon,
                        title: 'Cloud-Sync',
                        value: cloudStatus.title,
                        detail: cloudStatus.detail,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SubscriptionInfoTile(
                        accountAccess: accountAccess,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: cloudStatus.canSync ? onSyncNow : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Jetzt synchronisieren'),
                ),
                FilledButton.icon(
                  onPressed:
                      hasAccount && (access?.canRequestActivation ?? false)
                          ? onRequestActivation
                          : null,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Bezahlversion aktivieren'),
                ),
                OutlinedButton.icon(
                  onPressed: hasAccount ? onPasswordChange : null,
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Passwort aendern'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      hasAccount && !emailVerified ? onVerifyEmail : null,
                  icon: const Icon(Icons.mark_email_read_rounded),
                  label: const Text('E-Mail bestaetigen'),
                ),
                OutlinedButton.icon(
                  onPressed: hasAccount ? onSignOut : null,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Abmelden'),
                ),
                OutlinedButton.icon(
                  onPressed: hasAccount ? onDeleteAccount : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                  ),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Konto loeschen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionInfoTile extends StatelessWidget {
  final AsyncValue<AccountAccess> accountAccess;

  const _SubscriptionInfoTile({required this.accountAccess});

  @override
  Widget build(BuildContext context) {
    return accountAccess.when(
      data: (access) => _AccountInfoTile(
        icon: _subscriptionIcon(access.status),
        title: 'Testversion / Bezahlversion',
        value: access.title,
        detail: access.detail,
      ),
      loading: () => const _AccountInfoTile(
        icon: Icons.hourglass_top_rounded,
        title: 'Testversion / Bezahlversion',
        value: 'wird geprueft',
        detail: 'Die Konto-Freischaltung wird geladen.',
      ),
      error: (_, __) => const _AccountInfoTile(
        icon: Icons.warning_amber_rounded,
        title: 'Testversion / Bezahlversion',
        value: 'nicht pruefbar',
        detail: 'Bitte Internet und Anmeldung pruefen.',
      ),
    );
  }
}

IconData _subscriptionIcon(AccountAccessStatus status) {
  return switch (status) {
    AccountAccessStatus.owner => Icons.verified_user_rounded,
    AccountAccessStatus.active => Icons.workspace_premium_rounded,
    AccountAccessStatus.activationRequested => Icons.mark_email_read_rounded,
    AccountAccessStatus.expired => Icons.lock_clock_rounded,
    AccountAccessStatus.trial => Icons.hourglass_top_rounded,
    AccountAccessStatus.localDevelopment => Icons.developer_mode_rounded,
    AccountAccessStatus.signedOut => Icons.account_circle_rounded,
  };
}

class _AccountInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? detail;

  const _AccountInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF06172E),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

({IconData icon, String title, String detail, bool canSync})
    _accountCloudStatus(
  FleetSyncStatus syncStatus,
  bool hasAccount,
) {
  return switch (syncStatus) {
    FleetSyncStatus.cloudActive => (
        icon: Icons.cloud_done_rounded,
        title: 'Cloud aktiv',
        detail: 'Firebase ist verbunden.',
        canSync: true,
      ),
    FleetSyncStatus.syncing => (
        icon: Icons.cloud_sync_rounded,
        title: 'Synchronisiert',
        detail: 'Aenderungen werden uebertragen.',
        canSync: false,
      ),
    FleetSyncStatus.cloudPaused => (
        icon: Icons.cloud_off_rounded,
        title: 'Cloud pausiert',
        detail: 'Lokale Daten bleiben erhalten.',
        canSync: true,
      ),
    FleetSyncStatus.localOnly => (
        icon: Icons.storage_rounded,
        title: 'Nur lokal',
        detail: hasAccount ? 'Cloud-Sync wartet.' : 'Ohne Konto angemeldet.',
        canSync: false,
      ),
  };
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
  String? _photoThumbnailDataUri;
  String? _insuranceDocumentName;
  String? _insuranceDocumentDataUri;
  PilotProfile? _lastSubmittedProfile;
  DateTime? _protectSubmittedProfileUntil;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _name = _profileController(widget.profile.name);
    _homeAirfield = _profileController(widget.profile.homeAirfield);
    _club = _profileController(widget.profile.club);
    _licenseNumber = _profileController(widget.profile.licenseNumber);
    _phone = _profileController(widget.profile.phone);
    _email = _profileController(widget.profile.email);
    _syncTransmitterControllers(widget.profile.transmitters);
    _syncFlightAreaControllers(widget.profile.flightAreas);
    _notes = _profileController(widget.profile.notes);
    _photoDataUri = widget.profile.photoSource;
    _photoThumbnailDataUri = widget.profile.photoThumbnailDataUri;
    _insuranceDocumentName = widget.profile.insuranceDocumentName;
    _insuranceDocumentDataUri = widget.profile.insuranceDocumentSource;
    settingsProfileHasUnsavedChanges.value = false;
  }

  @override
  void didUpdateWidget(covariant _PilotProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile == widget.profile) {
      return;
    }
    if (_editing) {
      return;
    }
    if (_shouldKeepSubmittedProfile(widget.profile)) {
      return;
    }
    _lastSubmittedProfile = null;
    _protectSubmittedProfileUntil = null;
    _name.text = widget.profile.name;
    _homeAirfield.text = widget.profile.homeAirfield;
    _club.text = widget.profile.club;
    _licenseNumber.text = widget.profile.licenseNumber;
    _phone.text = widget.profile.phone;
    _email.text = widget.profile.email;
    _syncTransmitterControllers(widget.profile.transmitters);
    _syncFlightAreaControllers(widget.profile.flightAreas);
    _notes.text = widget.profile.notes;
    _photoDataUri = widget.profile.photoSource;
    _photoThumbnailDataUri = widget.profile.photoThumbnailDataUri;
    _insuranceDocumentName = widget.profile.insuranceDocumentName;
    _insuranceDocumentDataUri = widget.profile.insuranceDocumentSource;
    _updateUnsavedProfileFlag();
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
    settingsProfileHasUnsavedChanges.value = false;
    super.dispose();
  }

  TextEditingController _profileController(String text) {
    final controller = TextEditingController(text: text);
    controller.addListener(_updateUnsavedProfileFlag);
    return controller;
  }

  void _updateUnsavedProfileFlag() {
    settingsProfileHasUnsavedChanges.value = _hasUnsavedProfileChanges;
  }

  bool get _hasUnsavedProfileChanges {
    if (!_editing) {
      return false;
    }

    final currentProfile = _currentProfileFromFields();
    return currentProfile.name != widget.profile.name ||
        currentProfile.homeAirfield != widget.profile.homeAirfield ||
        currentProfile.club != widget.profile.club ||
        currentProfile.licenseNumber != widget.profile.licenseNumber ||
        currentProfile.phone != widget.profile.phone ||
        currentProfile.email != widget.profile.email ||
        currentProfile.notes != widget.profile.notes ||
        !listEquals(currentProfile.flightAreas, widget.profile.flightAreas) ||
        !listEquals(currentProfile.transmitters, widget.profile.transmitters) ||
        currentProfile.photoSource != widget.profile.photoSource ||
        currentProfile.photoThumbnailDataUri !=
            widget.profile.photoThumbnailDataUri ||
        currentProfile.insuranceDocumentName !=
            widget.profile.insuranceDocumentName ||
        currentProfile.insuranceDocumentSource !=
            widget.profile.insuranceDocumentSource;
  }

  PilotProfile _currentProfileFromFields() {
    return PilotProfile(
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
      photoThumbnailDataUri: _photoThumbnailDataUri,
      insuranceDocumentName: _insuranceDocumentName,
      insuranceDocumentDataUri: _insuranceDocumentDataUri,
    );
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
                width: 560,
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
                            _updateUnsavedProfileFlag();
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
                      onPressed: _startEditing,
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

  void _startEditing() {
    setState(() => _editing = true);
    _updateUnsavedProfileFlag();
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

    final editedPhoto = _prepareProfilePhoto(
      await pickedImage.readAsBytes(),
      _mimeTypeForName(pickedImage.name),
    );

    setState(() {
      _photoDataUri = editedPhoto.dataUri;
      _photoThumbnailDataUri = editedPhoto.thumbnailDataUri;
      _updateUnsavedProfileFlag();
    });
  }

  _EditedPhoto _prepareProfilePhoto(Uint8List bytes, String mimeType) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final source = img.bakeOrientation(decoded);
        final compactPhoto = _resizeImageToMaxEdge(source, 1200);
        final encoded =
            Uint8List.fromList(img.encodeJpg(compactPhoto, quality: 84));
        return _EditedPhoto(
          dataUri: 'data:image/jpeg;base64,${base64Encode(encoded)}',
          thumbnailDataUri: createImageThumbnailDataUri(encoded),
        );
      }
    } catch (_) {
      // Falls ein ungewoehnliches Bildformat nicht lesbar ist, bleibt die Datei unveraendert.
    }

    final encoded = base64Encode(bytes);
    return _EditedPhoto(
      dataUri: 'data:$mimeType;base64,$encoded',
      thumbnailDataUri: createImageThumbnailDataUri(bytes),
    );
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
      _insuranceDocumentDataUri = _createCompactDocumentDataUri(
        fileName: file.name,
        bytes: bytes,
      );
      _updateUnsavedProfileFlag();
    });
  }

  String _createCompactDocumentDataUri({
    required String fileName,
    required Uint8List bytes,
  }) {
    final mimeType = _mimeTypeForName(fileName);
    if (!mimeType.startsWith('image/')) {
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    }

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      final compact = _resizeImageToMaxEdge(img.bakeOrientation(decoded), 1200);
      final encoded = img.encodeJpg(compact, quality: 82);
      return 'data:image/jpeg;base64,${base64Encode(encoded)}';
    } catch (_) {
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    }
  }

  img.Image _resizeImageToMaxEdge(img.Image source, int maxEdge) {
    final longestEdge =
        source.width > source.height ? source.width : source.height;
    if (longestEdge <= maxEdge) {
      return source;
    }

    if (source.width >= source.height) {
      return img.copyResize(
        source,
        width: maxEdge,
        interpolation: img.Interpolation.average,
      );
    }

    return img.copyResize(
      source,
      height: maxEdge,
      interpolation: img.Interpolation.average,
    );
  }

  void _syncTransmitterControllers(List<String> transmitters) {
    for (final controller in _transmitters) {
      controller.dispose();
    }
    _transmitters
      ..clear()
      ..addAll(
        (transmitters.isEmpty ? [''] : transmitters).map(
          _profileController,
        ),
      );
  }

  void _addTransmitterField() {
    setState(() => _transmitters.add(_profileController('')));
    _updateUnsavedProfileFlag();
  }

  void _removeTransmitterField(int index) {
    if (_transmitters.length <= 1) {
      return;
    }
    final controller = _transmitters.removeAt(index);
    controller.dispose();
    setState(() {});
    _updateUnsavedProfileFlag();
  }

  void _syncFlightAreaControllers(List<String> flightAreas) {
    for (final controller in _flightAreas) {
      controller.dispose();
    }
    _flightAreas
      ..clear()
      ..addAll(
        (flightAreas.isEmpty ? [''] : flightAreas).map(
          _profileController,
        ),
      );
  }

  void _addFlightAreaField() {
    setState(() => _flightAreas.add(_profileController('')));
    _updateUnsavedProfileFlag();
  }

  void _removeFlightAreaField(int index) {
    if (_flightAreas.length <= 1) {
      return;
    }
    final controller = _flightAreas.removeAt(index);
    controller.dispose();
    setState(() {});
    _updateUnsavedProfileFlag();
  }

  Future<void> _showPhotoOptions() async {
    if (!_editing) {
      return;
    }

    final action = await showDialog<_PhotoAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Foto laden'),
        content: Column(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );

    if (action == _PhotoAction.pick) {
      await _pickPhoto();
    }
    if (action == _PhotoAction.remove) {
      setState(() {
        _photoDataUri = null;
        _photoThumbnailDataUri = null;
        _updateUnsavedProfileFlag();
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final submittedProfile = _currentProfileFromFields();

    _lastSubmittedProfile = submittedProfile;
    _protectSubmittedProfileUntil =
        DateTime.now().add(const Duration(seconds: 20));
    widget.onSave(submittedProfile);
    settingsProfileHasUnsavedChanges.value = false;

    showCenteredSnackBar(context, 'Pilotprofil gespeichert.');
    setState(() => _editing = false);
  }

  bool _shouldKeepSubmittedProfile(PilotProfile incomingProfile) {
    final submittedProfile = _lastSubmittedProfile;
    final protectUntil = _protectSubmittedProfileUntil;
    if (submittedProfile == null ||
        protectUntil == null ||
        DateTime.now().isAfter(protectUntil)) {
      return false;
    }

    final incomingHasSubmittedText =
        incomingProfile.name == submittedProfile.name &&
            incomingProfile.homeAirfield == submittedProfile.homeAirfield &&
            incomingProfile.club == submittedProfile.club &&
            incomingProfile.licenseNumber == submittedProfile.licenseNumber &&
            incomingProfile.phone == submittedProfile.phone &&
            incomingProfile.email == submittedProfile.email &&
            incomingProfile.notes == submittedProfile.notes &&
            listEquals(
              incomingProfile.flightAreas,
              submittedProfile.flightAreas,
            ) &&
            listEquals(
              incomingProfile.transmitters,
              submittedProfile.transmitters,
            );

    final incomingPhoto = incomingProfile.photoSource;
    final submittedPhoto = submittedProfile.photoSource;
    final incomingLostSubmittedPhoto = submittedPhoto != null &&
        submittedPhoto.isNotEmpty &&
        (incomingPhoto == null || incomingPhoto.isEmpty);
    final incomingRestoredRemovedPhoto =
        (submittedPhoto == null || submittedPhoto.isEmpty) &&
            incomingPhoto != null &&
            incomingPhoto.isNotEmpty;

    final incomingDocument = incomingProfile.insuranceDocumentSource;
    final submittedDocument = submittedProfile.insuranceDocumentSource;
    final incomingLostSubmittedDocument = submittedDocument != null &&
        submittedDocument.isNotEmpty &&
        (incomingDocument == null || incomingDocument.isEmpty);
    final incomingRestoredRemovedDocument =
        (submittedDocument == null || submittedDocument.isEmpty) &&
            incomingDocument != null &&
            incomingDocument.isNotEmpty;

    return !incomingHasSubmittedText ||
        incomingLostSubmittedPhoto ||
        incomingRestoredRemovedPhoto ||
        incomingLostSubmittedDocument ||
        incomingRestoredRemovedDocument;
  }
}

enum _PhotoAction { pick, remove }

class _EditedPhoto {
  final String dataUri;
  final String? thumbnailDataUri;

  const _EditedPhoto({
    required this.dataUri,
    required this.thumbnailDataUri,
  });
}

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
                        : ColoredBox(
                            color: const Color(0xFFEFF6FF),
                            child: Image(
                              image: browserVisibleMediaImageProvider(
                                photoDataUri!,
                              ),
                              fit: BoxFit.contain,
                            ),
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
    final isImage = dataUri != null && isImageMediaSource(dataUri!);

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
                  constraints: const BoxConstraints(
                    maxWidth: 320,
                    maxHeight: 220,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image(
                        image: browserVisibleMediaImageProvider(dataUri!),
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
              'Profil, Foto und Nachweis werden lokal gespeichert und bei aktivem Konto mit Firebase synchronisiert.',
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

({IconData icon, String value, bool canSync}) _cloudConnectionInfo(
  FleetSyncStatus syncStatus,
  String? userEmail,
) {
  final account = userEmail?.trim();
  final hasAccount = account != null && account.isNotEmpty;

  return switch (syncStatus) {
    FleetSyncStatus.cloudActive => (
        icon: Icons.cloud_done_rounded,
        value: hasAccount ? 'Cloud aktiv\n$account' : 'Cloud aktiv',
        canSync: true,
      ),
    FleetSyncStatus.syncing => (
        icon: Icons.cloud_sync_rounded,
        value: hasAccount ? 'Verbindung laeuft\n$account' : 'Verbindung laeuft',
        canSync: false,
      ),
    FleetSyncStatus.cloudPaused => (
        icon: Icons.cloud_off_rounded,
        value: hasAccount ? 'Cloud pausiert\n$account' : 'Cloud pausiert',
        canSync: true,
      ),
    FleetSyncStatus.localOnly => (
        icon: Icons.storage_rounded,
        value: hasAccount ? 'Nur lokal\n$account' : 'Nur lokal',
        canSync: false,
      ),
  };
}

String _lastAutomaticBackupLabel(AppSettings settings) {
  final lastBackup = _parseBackupDate(settings.lastAutomaticBackupAt);
  if (lastBackup == null) {
    return 'Noch keine';
  }
  return _formatBackupDateTime(lastBackup);
}

String _nextAutomaticBackupLabel(AppSettings settings) {
  if (!settings.automaticBackupEnabled) {
    return 'Aus';
  }
  final lastBackup = _parseBackupDate(settings.lastAutomaticBackupAt);
  if (lastBackup == null) {
    return 'Beim naechsten Start';
  }
  final nextBackup = lastBackup.toLocal().add(const Duration(days: 1));
  if (!DateTime.now().isBefore(nextBackup)) {
    return 'Bei naechster Aenderung';
  }
  return 'Ab ${_formatBackupDateTime(nextBackup)}';
}

String _backupTitle(FleetCloudBackup backup) {
  final createdAt = backup.createdAt;
  if (createdAt == null) {
    return 'Cloud-Sicherung ${backup.id}';
  }
  return 'Cloud-Sicherung ${_formatBackupDateTime(createdAt)}';
}

String _backupSubtitle(FleetCloudBackup backup) {
  return '${backup.aircraftCount} Modelle, ${backup.batteryCount} Akkus, ${backup.flightCount} Fluege';
}

DateTime? _parseBackupDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

String _formatBackupDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

class _AppSettingsCard extends StatelessWidget {
  final AppSettings settings;
  final FleetSyncStatus syncStatus;
  final String? userEmail;
  final bool canOpenAdmin;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onExportFlightbook;
  final Future<void> Function() onRestoreBackup;
  final ValueChanged<bool> onLocationSharingChanged;
  final ValueChanged<bool> onChatReachabilityChanged;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Future<void> Function() onSyncNow;

  const _AppSettingsCard({
    required this.settings,
    required this.syncStatus,
    required this.userEmail,
    required this.canOpenAdmin,
    required this.onCreateBackup,
    required this.onExportFlightbook,
    required this.onRestoreBackup,
    required this.onLocationSharingChanged,
    required this.onChatReachabilityChanged,
    required this.onSettingsChanged,
    required this.onSyncNow,
  });

  @override
  Widget build(BuildContext context) {
    final cloudConnection = _cloudConnectionInfo(syncStatus, userEmail);

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
                      title: 'Freunde online',
                      description:
                          'Regelmaessige Pruefung, ob Freunde online sind.',
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
                  title: 'Oberfläche',
                  icon: Icons.palette_rounded,
                  children: [
                    _SwitchSettingTile(
                      icon: Icons.volume_up_rounded,
                      title: 'Startsound beim Programmstart abspielen',
                      value: settings.playStartSound,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(playStartSound: value),
                      ),
                    ),
                    _SwitchSettingTile(
                      icon: Icons.timer_rounded,
                      title: 'Startansage und Minutenton beim Flugtimer',
                      value: settings.playFlightTimerMinuteTone,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(playFlightTimerMinuteTone: value),
                      ),
                    ),
                    _SwitchSettingTile(
                      icon: Icons.login_rounded,
                      title:
                          'Programmstart: Bei 100 % automatisch zum Dashboard',
                      value: settings.autoOpenDashboardAfterLoading,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(
                          autoOpenDashboardAfterLoading: value,
                        ),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Sicherung',
                  icon: Icons.backup_rounded,
                  children: [
                    _AppSettingTile(
                      icon: Icons.history_rounded,
                      title: 'Letzte Sicherung',
                      value: _lastAutomaticBackupLabel(settings),
                    ),
                    _AppSettingTile(
                      icon: Icons.event_repeat_rounded,
                      title: 'Naechste automatische Sicherung',
                      value: _nextAutomaticBackupLabel(settings),
                    ),
                    _SwitchSettingTile(
                      icon: Icons.event_available_rounded,
                      title: 'Automatische Sicherung taeglich',
                      value: settings.automaticBackupEnabled,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(automaticBackupEnabled: value),
                      ),
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
                    _ButtonSettingTile(
                      icon: Icons.ios_share_rounded,
                      label: 'Flugbuch exportieren',
                      onPressed: onExportFlightbook,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Synchronisation und Cloud',
                  icon: Icons.cloud_sync_rounded,
                  children: [
                    _AppSettingTile(
                      icon: cloudConnection.icon,
                      title: 'Verbindung',
                      value: cloudConnection.value,
                    ),
                    _SwitchSettingTile(
                      icon: Icons.wifi_rounded,
                      title: 'Nur ueber WLAN synchronisieren?',
                      value: settings.wifiOnlySync,
                      onChanged: (value) => onSettingsChanged(
                        settings.copyWith(wifiOnlySync: value),
                      ),
                    ),
                    _ButtonSettingTile(
                      icon: Icons.sync_rounded,
                      label: 'Jetzt synchronisieren',
                      onPressed: cloudConnection.canSync ? onSyncNow : null,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Webcams',
                  icon: Icons.videocam_rounded,
                  children: [
                    _ButtonSettingTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Webcam-Infos',
                      onPressed: () => _showWebcamInfoDialog(context),
                    ),
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
                    const _AppVersionSettingTile(),
                    _ActionSettingTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Was ist neu',
                      value: 'Aenderungen anzeigen',
                      onTap: () => _showWhatsNewDialog(context),
                    ),
                    if (canOpenAdmin)
                      _ActionSettingTile(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Admin-Seite',
                        value: 'Starter-Datei verwalten',
                        onTap: () => context.go('/admin'),
                      ),
                    _ActionSettingTile(
                      icon: Icons.help_center_rounded,
                      title: 'Programm-Hilfe',
                      value: 'PDF-Hilfe oeffnen',
                      onTap: () => _showProgramHelpDialog(context),
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
    final incomingNames = _sourceWebcamNames(widget.webcams);
    final incomingUrls = _sourceWebcamUrls(incomingNames, widget.webcamUrls);
    if (!listEquals(incomingNames, _currentWebcamNames()) ||
        !listEquals(incomingUrls, _currentWebcamUrls())) {
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
    final source = _sourceWebcamNames(values);
    return [for (final value in source) TextEditingController(text: value)];
  }

  List<TextEditingController> _buildUrlControllers(
    List<String> webcams,
    List<String> urls,
  ) {
    final source = _sourceWebcamNames(webcams);
    final sourceUrls = _sourceWebcamUrls(source, urls);
    return [
      for (var index = 0; index < source.length; index++)
        TextEditingController(text: sourceUrls[index]),
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

  List<String> _sourceWebcamNames(List<String> values) {
    final names = [
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    ];
    return names.isEmpty ? defaultWebcams : names;
  }

  List<String> _sourceWebcamUrls(List<String> names, List<String> urls) {
    return [
      for (var index = 0; index < names.length; index++)
        index < urls.length ? urls[index].trim() : '',
    ];
  }

  List<String> _currentWebcamNames() {
    final names = [
      for (final controller in _controllers)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];
    return names.isEmpty ? ['Webcam'] : names;
  }

  List<String> _currentWebcamUrls() {
    final urls = <String>[];
    var hasName = false;
    for (var index = 0; index < _controllers.length; index++) {
      if (_controllers[index].text.trim().isEmpty) {
        continue;
      }
      hasName = true;
      urls.add(index < _urlControllers.length
          ? _urlControllers[index].text.trim()
          : '');
    }
    return hasName ? urls : [''];
  }

  Future<void> _editUrl(int index) async {
    final controller = _urlControllers[index];
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _WebcamUrlDialog(
        webcamName: _controllers[index].text.trim().isEmpty
            ? 'Webcam ${index + 1}'
            : _controllers[index].text.trim(),
        initialUrl: controller.text,
      ),
    );
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
                  tooltip: 'Internet-Adresse pruefen',
                  onPressed: () => _editUrl(index),
                  icon: Icon(
                    _urlControllers[index].text.trim().isEmpty
                        ? Icons.manage_search_rounded
                        : Icons.fact_check_rounded,
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

class _WebcamUrlDialog extends StatefulWidget {
  final String webcamName;
  final String initialUrl;

  const _WebcamUrlDialog({
    required this.webcamName,
    required this.initialUrl,
  });

  @override
  State<_WebcamUrlDialog> createState() => _WebcamUrlDialogState();
}

class _WebcamUrlDialogState extends State<_WebcamUrlDialog> {
  late final TextEditingController _controller;
  WebcamUrlDiagnostic? _diagnostic;
  int _previewSerial = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
    if (widget.initialUrl.trim().isNotEmpty) {
      _diagnostic = diagnoseWebcamUrl(widget.initialUrl);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runCheck() {
    setState(() {
      _diagnostic = diagnoseWebcamUrl(_controller.text);
      _previewSerial++;
    });
  }

  void _useSuggestedUrl() {
    final suggestedUrl = _diagnostic?.suggestedUrl;
    if (suggestedUrl == null) {
      return;
    }
    setState(() {
      _controller.text = suggestedUrl;
      _diagnostic = diagnoseWebcamUrl(suggestedUrl);
      _previewSerial++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnostic = _diagnostic;
    return AlertDialog(
      title: Text('${widget.webcamName} pruefen'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Webcam-URL',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                onChanged: (_) => setState(() => _diagnostic = null),
                onSubmitted: (_) => _runCheck(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _runCheck,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Pruefen'),
                  ),
                  if (diagnostic?.suggestedUrl != null)
                    OutlinedButton.icon(
                      onPressed: _useSuggestedUrl,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('bessere Adresse einsetzen'),
                    ),
                ],
              ),
              if (diagnostic != null) ...[
                const SizedBox(height: 12),
                _WebcamDiagnosticPanel(diagnostic: diagnostic),
                if (diagnostic.hasPreview) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: WebcamLivePreview(
                        title: widget.webcamName,
                        sourceUrl: _controller.text,
                        refreshSerial: _previewSerial,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _WebcamDiagnosticPanel extends StatelessWidget {
  final WebcamUrlDiagnostic diagnostic;

  const _WebcamDiagnosticPanel({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final color = switch (diagnostic.level) {
      WebcamDiagnosticLevel.success => const Color(0xFF0F8A4B),
      WebcamDiagnosticLevel.warning => const Color(0xFFD97706),
      WebcamDiagnosticLevel.error => const Color(0xFFDC2626),
    };
    final icon = switch (diagnostic.level) {
      WebcamDiagnosticLevel.success => Icons.check_circle_rounded,
      WebcamDiagnosticLevel.warning => Icons.info_rounded,
      WebcamDiagnosticLevel.error => Icons.error_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diagnostic.title,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        diagnostic.message,
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (diagnostic.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final detail in diagnostic.details)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '- ',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          detail,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (diagnostic.suggestedUrl != null) ...[
              const SizedBox(height: 8),
              Text(
                'Vorschlag: ${diagnostic.suggestedUrl}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
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
                  'Statusfreigabe fuer Freunde',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Freunde sehen, ob du online bist.'
                      : 'Alles bleibt anonym.',
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

class _AppVersionSettingTile extends ConsumerWidget {
  const _AppVersionSettingTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider);

    return _AppSettingTile(
      icon: Icons.new_releases_rounded,
      title: 'Version',
      value: appInfo.when(
        data: formatAppVersion,
        loading: () => 'wird geladen',
        error: (_, __) => 'nicht verfuegbar',
      ),
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

Future<void> _showWhatsNewDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const _WhatsNewDialog(),
  );
}

Future<void> _showProgramHelpDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Programm-Hilfe'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Die Hilfe-PDF wird spaeter hier geoeffnet. Am sparsamsten ist eine kleine PDF-Datei, die mit der App ausgeliefert und nach dem ersten Laden im Browser zwischengespeichert wird.',
            style: TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
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

Future<void> _showWebcamInfoDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Webcam-Infos'),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WebcamInfoItem(
                  icon: Icons.link_rounded,
                  title: 'Direkte Bild- oder Stream-Adresse',
                  text:
                      'Viele Webseiten zeigen eine Webcam nur in einer ganzen Internetseite. Die App braucht am besten die direkte Adresse zum Bild oder Stream.',
                ),
                _WebcamInfoItem(
                  icon: Icons.lock_rounded,
                  title: 'Login oder Zustimmung',
                  text:
                      'Wenn die Kamera-Seite ein Passwort, Cookies oder eine Zustimmung verlangt, kann die App das Bild oft nicht automatisch laden.',
                ),
                _WebcamInfoItem(
                  icon: Icons.block_rounded,
                  title: 'Einbettung blockiert',
                  text:
                      'Einige Anbieter verbieten, dass ihre Webcam in einer anderen App angezeigt wird. Dann bleibt die Vorschau leer, obwohl die Adresse im Browser funktioniert.',
                ),
                _WebcamInfoItem(
                  icon: Icons.security_rounded,
                  title: 'http und https',
                  text:
                      'Wenn die App ueber eine sichere https-Seite laeuft, blockieren Browser manchmal unsichere http-Webcams.',
                ),
                _WebcamInfoItem(
                  icon: Icons.refresh_rounded,
                  title: 'Zwischenspeicher',
                  text:
                      'Manche Webcam-Bilder werden vom Browser zwischengespeichert. Dann hilft oft ein Neuladen oder eine Adresse, die regelmaessig ein neues Bild liefert.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      );
    },
  );
}

class _WebcamInfoItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _WebcamInfoItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF06172E),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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

class _WhatsNewDialog extends ConsumerWidget {
  const _WhatsNewDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider);
    final versionLabel = appInfo.maybeWhen(
      data: formatAppVersion,
      orElse: () => 'aktuelle Version',
    );

    return AlertDialog(
      title: const Text('Was ist neu'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version $versionLabel',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            const _WhatsNewEntry(
              icon: Icons.new_releases_rounded,
              title: 'Versionsanzeige',
              text:
                  'Die App-Version wird jetzt automatisch aus den App-Daten gelesen.',
            ),
            const _WhatsNewEntry(
              icon: Icons.settings_rounded,
              title: 'App-Informationen',
              text:
                  'Version, Kontakt und Feedback sind im Bereich App-Informationen gebuendelt.',
            ),
            const _WhatsNewEntry(
              icon: Icons.flight_takeoff_rounded,
              title: 'Grundversion',
              text:
                  'Dashboard, Modelle, Akkus, Webcam, Freunde und Sicherung sind vorbereitet.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schliessen'),
        ),
      ],
    );
  }
}

class _WhatsNewEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _WhatsNewEntry({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
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
