import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/admin_access.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/starter_fleet_service.dart';
import '../../shared/services/subscription_service.dart';
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

    final deviceService = ref.watch(userDeviceServiceProvider);
    final subscriptionService = ref.watch(subscriptionServiceProvider);
    final summary = _summary;
    return AppScaffold(
      title: 'Admin',
      subtitle: 'Freischaltungen, Starter-Datei und Geraetezugriffe verwalten.',
      children: [
        _MemberDevelopmentCard(service: subscriptionService),
        const SizedBox(height: 16),
        _ManualActivationCard(
          service: subscriptionService,
          adminEmail: authState.valueOrNull?.email,
          onMessage: _showMessage,
        ),
        const SizedBox(height: 16),
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

class _MemberDevelopmentCard extends StatelessWidget {
  final SubscriptionService? service;

  const _MemberDevelopmentCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final currentService = service;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mitglieder-Entwicklung',
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
              'Neue Konten, Freischaltungen und Bezahlstatus im Blick.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (currentService == null)
              const _AdminInfoBox(
                icon: Icons.cloud_off_rounded,
                title: 'Firebase nicht verbunden',
                message:
                    'Mitgliederzahlen koennen gerade nicht geladen werden.',
              )
            else
              StreamBuilder<List<ManualActivationAccount>>(
                stream: currentService.watchManualActivationAccounts(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _AdminInfoBox(
                      icon: Icons.error_rounded,
                      title: 'Mitgliederzahlen konnten nicht geladen werden',
                      message:
                          'Bitte pruefe, ob die Firestore-Regeln veroeffentlicht sind.',
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }

                  final accounts =
                      snapshot.data ?? const <ManualActivationAccount>[];
                  if (accounts.isEmpty) {
                    return const _AdminInfoBox(
                      icon: Icons.groups_rounded,
                      title: 'Noch keine Mitglieder',
                      message:
                          'Sobald sich ein Konto anmeldet, startet hier die Auswertung.',
                    );
                  }

                  return _MemberDevelopmentContent(accounts: accounts);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberDevelopmentContent extends StatelessWidget {
  final List<ManualActivationAccount> accounts;

  const _MemberDevelopmentContent({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final summary = _MemberDevelopmentSummary.fromAccounts(accounts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MemberMetricTile(
              icon: Icons.groups_rounded,
              value: '${summary.totalCount}',
              label: 'Mitglieder gesamt',
              color: const Color(0xFF0A84FF),
            ),
            _MemberMetricTile(
              icon: Icons.person_add_alt_1_rounded,
              value: '${summary.currentMonthNew}',
              label: 'Neu in ${summary.currentMonthShortLabel}',
              color: const Color(0xFF047857),
            ),
            _MemberMetricTile(
              icon: Icons.history_rounded,
              value: '${summary.last30DaysNew}',
              label: 'Neue letzte 30 Tage',
              color: const Color(0xFF7C3AED),
            ),
            _MemberMetricTile(
              icon: Icons.hourglass_top_rounded,
              value: '${summary.trialCount}',
              label: 'Testversion',
              color: const Color(0xFF1D4ED8),
            ),
            _MemberMetricTile(
              icon: Icons.mark_email_read_rounded,
              value: '${summary.activationRequestedCount}',
              label: 'Warten',
              color: const Color(0xFFEA580C),
            ),
            _MemberMetricTile(
              icon: Icons.workspace_premium_rounded,
              value: '${summary.activeCount}',
              label: 'Bezahlversion',
              color: const Color(0xFF047857),
            ),
            _MemberMetricTile(
              icon: Icons.lock_clock_rounded,
              value: '${summary.expiredCount}',
              label: 'Abgelaufen',
              color: const Color(0xFFE11D48),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MemberDevelopmentText(summary: summary),
        const SizedBox(height: 16),
        _MemberDevelopmentChart(points: summary.points),
      ],
    );
  }
}

class _MemberMetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MemberMetricTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
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
    );
  }
}

class _MemberDevelopmentText extends StatelessWidget {
  final _MemberDevelopmentSummary summary;

  const _MemberDevelopmentText({required this.summary});

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.insights_rounded, color: Color(0xFF0A84FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${summary.trendSentence} ${summary.statusSentence}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberDevelopmentChart extends StatelessWidget {
  final List<_MemberChartPoint> points;

  const _MemberDevelopmentChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxCount = points.fold<int>(
      0,
      (previous, point) => math.max(previous, point.count),
    );
    final interval = _memberChartInterval(maxCount);
    final maxY = math
        .max(
          interval,
          (maxCount / interval).ceil() * interval,
        )
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Neue Mitglieder pro Monat',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = math.max(constraints.maxWidth, 620.0);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 250,
                child: BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: maxY,
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF0F172A),
                        tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final point = points[group.x.toInt()];
                          return BarTooltipItem(
                            '${_newMemberCountLabel(point.count)}\n'
                            '${point.longLabel}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          );
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: interval,
                      getDrawingHorizontalLine: (value) => const FlLine(
                        color: Color(0xFFD8DEE8),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        left: BorderSide(color: Color(0xFFCBD5E1)),
                        bottom: BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          interval: interval,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                points[index].shortLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var index = 0; index < points.length; index++)
                        BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: points[index].count.toDouble(),
                              width: 18,
                              color: const Color(0xFF0A84FF),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MemberDevelopmentSummary {
  final int totalCount;
  final int currentMonthNew;
  final int previousMonthNew;
  final int last30DaysNew;
  final int trialCount;
  final int activationRequestedCount;
  final int activeCount;
  final int expiredCount;
  final String currentMonthShortLabel;
  final String currentMonthLabel;
  final List<_MemberChartPoint> points;

  const _MemberDevelopmentSummary({
    required this.totalCount,
    required this.currentMonthNew,
    required this.previousMonthNew,
    required this.last30DaysNew,
    required this.trialCount,
    required this.activationRequestedCount,
    required this.activeCount,
    required this.expiredCount,
    required this.currentMonthShortLabel,
    required this.currentMonthLabel,
    required this.points,
  });

  factory _MemberDevelopmentSummary.fromAccounts(
    List<ManualActivationAccount> accounts,
  ) {
    final now = DateTime.now();
    final monthStarts = [
      for (var offset = 11; offset >= 0; offset--)
        DateTime(now.year, now.month - offset),
    ];
    final monthIndexByKey = {
      for (var index = 0; index < monthStarts.length; index++)
        _monthKey(monthStarts[index]): index,
    };
    final counts = List<int>.filled(monthStarts.length, 0);
    final last30DaysStart = now.subtract(const Duration(days: 30));
    final currentMonthStart = monthStarts.last;
    final nextMonthStart = DateTime(now.year, now.month + 1);
    var last30DaysNew = 0;
    var currentMonthNew = 0;

    for (final account in accounts) {
      final startedAt = account.trialStartedAt?.toLocal();
      if (startedAt == null || startedAt.isAfter(now)) {
        continue;
      }

      final monthIndex = monthIndexByKey[_monthKey(startedAt)];
      if (monthIndex != null) {
        counts[monthIndex] += 1;
      }
      if (!startedAt.isBefore(last30DaysStart)) {
        last30DaysNew += 1;
      }
      if (!startedAt.isBefore(currentMonthStart) &&
          startedAt.isBefore(nextMonthStart)) {
        currentMonthNew += 1;
      }
    }

    int countStatus(AccountAccessStatus status) {
      return accounts
          .where((account) => account.access.status == status)
          .length;
    }

    final points = [
      for (var index = 0; index < monthStarts.length; index++)
        _MemberChartPoint(
          month: monthStarts[index],
          count: counts[index],
        ),
    ];

    return _MemberDevelopmentSummary(
      totalCount: accounts.length,
      currentMonthNew: currentMonthNew,
      previousMonthNew: counts.length > 1 ? counts[counts.length - 2] : 0,
      last30DaysNew: last30DaysNew,
      trialCount: countStatus(AccountAccessStatus.trial),
      activationRequestedCount:
          countStatus(AccountAccessStatus.activationRequested),
      activeCount: countStatus(AccountAccessStatus.active),
      expiredCount: countStatus(AccountAccessStatus.expired),
      currentMonthShortLabel: _monthShortName(now.month),
      currentMonthLabel: _monthLongLabel(currentMonthStart),
      points: points,
    );
  }

  String get trendSentence {
    if (currentMonthNew == 0 && previousMonthNew == 0) {
      return 'Im $currentMonthLabel kam bisher kein neues Mitglied dazu.';
    }
    if (currentMonthNew == 0) {
      return 'Im $currentMonthLabel kam bisher kein neues Mitglied dazu, '
          'im Vormonat waren es ${_newMemberCountLabel(previousMonthNew)}.';
    }

    final sentenceStart =
        'Im $currentMonthLabel ${_newMemberVerb(currentMonthNew)} dazu';
    if (currentMonthNew == previousMonthNew) {
      return '$sentenceStart, genauso viele wie im Vormonat.';
    }
    if (previousMonthNew == 0) {
      return '$sentenceStart, im Vormonat kam kein neues Mitglied dazu.';
    }

    final difference = currentMonthNew - previousMonthNew;
    if (difference > 0) {
      return '$sentenceStart, '
          '${_memberDifferenceLabel(difference)} mehr als im Vormonat.';
    }
    return '$sentenceStart, '
        '${_memberDifferenceLabel(difference.abs())} weniger als im Vormonat.';
  }

  String get statusSentence {
    final waitingSentence = activationRequestedCount == 0
        ? 'Keine Freischaltung wartet gerade.'
        : activationRequestedCount == 1
            ? '1 Konto wartet auf Freischaltung.'
            : '$activationRequestedCount Konten warten auf Freischaltung.';
    final activeSentence = activeCount == 1
        ? '1 Konto ist als Bezahlversion aktiv.'
        : '$activeCount Konten sind als Bezahlversion aktiv.';
    return '$waitingSentence $activeSentence';
  }
}

class _MemberChartPoint {
  final DateTime month;
  final int count;

  const _MemberChartPoint({
    required this.month,
    required this.count,
  });

  String get shortLabel {
    return '${_monthShortName(month.month)}\n${month.year % 100}';
  }

  String get longLabel {
    return _monthLongLabel(month);
  }
}

double _memberChartInterval(int maxCount) {
  if (maxCount <= 5) {
    return 1;
  }
  if (maxCount <= 10) {
    return 2;
  }
  if (maxCount <= 25) {
    return 5;
  }
  if (maxCount <= 50) {
    return 10;
  }
  return 20;
}

int _monthKey(DateTime date) {
  return date.year * 12 + date.month;
}

String _monthShortName(int month) {
  return switch (month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mrz',
    4 => 'Apr',
    5 => 'Mai',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Okt',
    11 => 'Nov',
    12 => 'Dez',
    _ => '',
  };
}

String _monthLongLabel(DateTime month) {
  final name = switch (month.month) {
    1 => 'Januar',
    2 => 'Februar',
    3 => 'Maerz',
    4 => 'April',
    5 => 'Mai',
    6 => 'Juni',
    7 => 'Juli',
    8 => 'August',
    9 => 'September',
    10 => 'Oktober',
    11 => 'November',
    12 => 'Dezember',
    _ => '',
  };
  return '$name ${month.year}';
}

String _newMemberVerb(int count) {
  return count == 1
      ? 'kam ${_newMemberCountLabel(count)}'
      : 'kamen ${_newMemberCountLabel(count)}';
}

String _newMemberCountLabel(int count) {
  return count == 1 ? '1 neues Mitglied' : '$count neue Mitglieder';
}

String _memberDifferenceLabel(int count) {
  return count == 1 ? '1 Mitglied' : '$count Mitglieder';
}

class _PaymentSettingsSection extends StatelessWidget {
  final SubscriptionService service;
  final String? adminEmail;
  final ValueChanged<String> onMessage;

  const _PaymentSettingsSection({
    required this.service,
    required this.adminEmail,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.payments_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'PayPal-Zahlung',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Diesen Link sehen Mitglieder, wenn sie die Bezahlversion aktivieren.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<PaymentSettings>(
          stream: service.watchPaymentSettings(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _AdminInfoBox(
                icon: Icons.error_rounded,
                title: 'PayPal-Link konnte nicht geladen werden',
                message:
                    'Bitte pruefe, ob die Firestore-Regeln veroeffentlicht sind.',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const LinearProgressIndicator();
            }

            final settings = snapshot.data ?? PaymentSettings.empty();
            return _PaymentSettingsEditor(
              key: ValueKey(settings.paypalPaymentUrl),
              service: service,
              settings: settings,
              adminEmail: adminEmail,
              onMessage: onMessage,
            );
          },
        ),
      ],
    );
  }
}

class _PaymentSettingsEditor extends StatefulWidget {
  final SubscriptionService service;
  final PaymentSettings settings;
  final String? adminEmail;
  final ValueChanged<String> onMessage;

  const _PaymentSettingsEditor({
    super.key,
    required this.service,
    required this.settings,
    required this.adminEmail,
    required this.onMessage,
  });

  @override
  State<_PaymentSettingsEditor> createState() => _PaymentSettingsEditorState();
}

class _PaymentSettingsEditorState extends State<_PaymentSettingsEditor> {
  late final TextEditingController _paypalController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _paypalController = TextEditingController(
      text: widget.settings.paypalPaymentUrl,
    );
  }

  @override
  void dispose() {
    _paypalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _paypalController.text.trim();
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null ||
            !uri.hasScheme ||
            uri.host.isEmpty ||
            (uri.scheme != 'https' && uri.scheme != 'http'))) {
      widget.onMessage('Bitte einen gueltigen PayPal-Link eintragen.');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.service.savePaymentSettings(
        paypalPaymentUrl: url,
        adminEmail: widget.adminEmail,
      );
      if (mounted) {
        widget.onMessage('PayPal-Link wurde gespeichert.');
      }
    } catch (_) {
      if (mounted) {
        widget.onMessage('PayPal-Link konnte nicht gespeichert werden.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.settings.hasPaypalPaymentUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _paypalController,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'PayPal-Link',
            hintText: 'https://www.paypal.com/...',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('PayPal-Link speichern'),
            ),
            Chip(
              avatar: Icon(
                configured ? Icons.check_circle_rounded : Icons.info_rounded,
                size: 18,
              ),
              label: Text(configured ? 'Link aktiv' : 'Noch kein Link'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManualActivationCard extends StatelessWidget {
  final SubscriptionService? service;
  final String? adminEmail;
  final ValueChanged<String> onMessage;

  const _ManualActivationCard({
    required this.service,
    required this.adminEmail,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final currentService = service;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Manuelle Freischaltung',
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
              'Hier werden Konten nach Zahlung dauerhaft freigeschaltet.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (currentService == null)
              const _AdminInfoBox(
                icon: Icons.cloud_off_rounded,
                title: 'Firebase nicht verbunden',
                message: 'Freischaltungen koennen gerade nicht geladen werden.',
              )
            else ...[
              _PaymentSettingsSection(
                service: currentService,
                adminEmail: adminEmail,
                onMessage: onMessage,
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 14),
              const Text(
                'Freischalt-Anfragen',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<ManualActivationAccount>>(
                stream: currentService.watchManualActivationAccounts(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _AdminInfoBox(
                      icon: Icons.error_rounded,
                      title: 'Freischaltungen konnten nicht geladen werden',
                      message:
                          'Bitte pruefe, ob die Firestore-Regeln veroeffentlicht sind.',
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }

                  final accounts =
                      snapshot.data ?? const <ManualActivationAccount>[];
                  if (accounts.isEmpty) {
                    return const _AdminInfoBox(
                      icon: Icons.inbox_rounded,
                      title: 'Noch keine Konten',
                      message:
                          'Sobald ein Konto die Testversion startet, erscheint es hier.',
                    );
                  }

                  return _ManualActivationTable(
                    accounts: accounts,
                    service: currentService,
                    adminEmail: adminEmail,
                    onMessage: onMessage,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManualActivationTable extends StatelessWidget {
  final List<ManualActivationAccount> accounts;
  final SubscriptionService service;
  final String? adminEmail;
  final ValueChanged<String> onMessage;

  const _ManualActivationTable({
    required this.accounts,
    required this.service,
    required this.adminEmail,
    required this.onMessage,
  });

  Future<void> _activateAccount(
    BuildContext context,
    ManualActivationAccount account,
  ) async {
    try {
      await service.activateAccount(
        uid: account.uid,
        adminEmail: adminEmail,
      );
      if (context.mounted) {
        onMessage('Konto wurde freigeschaltet.');
      }
    } catch (_) {
      if (context.mounted) {
        onMessage('Konto konnte nicht freigeschaltet werden.');
      }
    }
  }

  Future<void> _expireAccount(
    BuildContext context,
    ManualActivationAccount account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Freischaltung sperren'),
        content: Text(
          'Soll ${_accountName(account)} wirklich wieder gesperrt werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Sperren'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await service.expireAccount(
        uid: account.uid,
        adminEmail: adminEmail,
      );
      if (context.mounted) {
        onMessage('Konto wurde gesperrt.');
      }
    } catch (_) {
      if (context.mounted) {
        onMessage('Konto konnte nicht gesperrt werden.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFEFF6FF)),
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Mitglied')),
          DataColumn(label: Text('Test bis')),
          DataColumn(label: Text('Anfrage')),
          DataColumn(label: Text('Bezahlversion')),
          DataColumn(label: Text('Aktion')),
        ],
        rows: [
          for (final account in accounts)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 165,
                    child: _AccountStatusBadge(access: account.access),
                  ),
                ),
                DataCell(
                  _AdminTableCell(
                    width: 210,
                    primary: _accountName(account),
                    secondary:
                        account.email.isEmpty ? account.uid : account.email,
                  ),
                ),
                DataCell(
                  _AdminTableCell(
                    width: 105,
                    primary: _adminDateLabel(account.trialEndsAt),
                    secondary: _trialRemainingLabel(account),
                  ),
                ),
                DataCell(
                  _AdminTableCell(
                    width: 130,
                    primary: _adminDateTimeLabel(
                        account.access.activationRequestedAt),
                    secondary: account.access.status ==
                            AccountAccessStatus.activationRequested
                        ? 'wartet'
                        : '-',
                  ),
                ),
                DataCell(
                  _AdminTableCell(
                    width: 135,
                    primary: _paidAccessLabel(account.access),
                    secondary:
                        _adminDateTimeLabel(account.subscriptionUpdatedAt),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: _ManualActivationAction(
                      account: account,
                      onActivate: () => _activateAccount(context, account),
                      onExpire: () => _expireAccount(context, account),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ManualActivationAction extends StatelessWidget {
  final ManualActivationAccount account;
  final Future<void> Function() onActivate;
  final Future<void> Function() onExpire;

  const _ManualActivationAction({
    required this.account,
    required this.onActivate,
    required this.onExpire,
  });

  @override
  Widget build(BuildContext context) {
    if (account.canActivate) {
      return FilledButton.icon(
        onPressed: () {
          onActivate();
        },
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: const Icon(Icons.check_circle_rounded, size: 18),
        label: const Text('Freischalten'),
      );
    }

    if (account.canExpire) {
      return OutlinedButton.icon(
        onPressed: () {
          onExpire();
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: const Color(0xFFB91C1C),
        ),
        icon: const Icon(Icons.lock_rounded, size: 18),
        label: const Text('Sperren'),
      );
    }

    return const Text(
      '-',
      style: TextStyle(fontWeight: FontWeight.w900),
    );
  }
}

class _AccountStatusBadge extends StatelessWidget {
  final AccountAccess access;

  const _AccountStatusBadge({required this.access});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(access.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_subscriptionIcon(access.status), size: 17, color: color.icon),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              access.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTableCell extends StatelessWidget {
  final double width;
  final String primary;
  final String secondary;

  const _AdminTableCell({
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

class _AdminInfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AdminInfoBox({
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

class _StatusColors {
  final Color background;
  final Color border;
  final Color icon;
  final Color text;

  const _StatusColors({
    required this.background,
    required this.border,
    required this.icon,
    required this.text,
  });
}

_StatusColors _statusColor(AccountAccessStatus status) {
  return switch (status) {
    AccountAccessStatus.active ||
    AccountAccessStatus.owner =>
      const _StatusColors(
        background: Color(0xFFECFDF5),
        border: Color(0xFFA7F3D0),
        icon: Color(0xFF047857),
        text: Color(0xFF065F46),
      ),
    AccountAccessStatus.activationRequested => const _StatusColors(
        background: Color(0xFFFFF7ED),
        border: Color(0xFFFED7AA),
        icon: Color(0xFFEA580C),
        text: Color(0xFF9A3412),
      ),
    AccountAccessStatus.expired => const _StatusColors(
        background: Color(0xFFFFF1F2),
        border: Color(0xFFFDA4AF),
        icon: Color(0xFFE11D48),
        text: Color(0xFF9F1239),
      ),
    AccountAccessStatus.trial => const _StatusColors(
        background: Color(0xFFEFF6FF),
        border: Color(0xFFBFDBFE),
        icon: Color(0xFF0A84FF),
        text: Color(0xFF1D4ED8),
      ),
    AccountAccessStatus.localDevelopment ||
    AccountAccessStatus.signedOut =>
      const _StatusColors(
        background: Color(0xFFF8FAFC),
        border: Color(0xFFE2E8F0),
        icon: Color(0xFF475569),
        text: Color(0xFF334155),
      ),
  };
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

String _accountName(ManualActivationAccount account) {
  if (account.displayName.trim().isNotEmpty) {
    return account.displayName.trim();
  }
  if (account.email.trim().isNotEmpty) {
    return account.email.trim();
  }
  return 'Konto ${account.uid}';
}

String _paidAccessLabel(AccountAccess access) {
  if (access.status == AccountAccessStatus.owner) {
    return 'Dauerhaft';
  }
  if (access.status != AccountAccessStatus.active) {
    return '-';
  }
  final endsAt = access.subscriptionEndsAt;
  return endsAt == null ? 'Dauerhaft' : _adminDateLabel(endsAt);
}

String _trialRemainingLabel(ManualActivationAccount account) {
  if (account.trialEndsAt == null ||
      account.access.status == AccountAccessStatus.active ||
      account.access.status == AccountAccessStatus.owner) {
    return '-';
  }
  return '${account.access.trialDaysRemaining} Tage';
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

String _adminDateLabel(DateTime? date) {
  if (date == null) {
    return '-';
  }
  final local = date.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}.${local.year}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}
