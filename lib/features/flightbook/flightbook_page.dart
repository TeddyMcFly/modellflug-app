import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/utils/media_source.dart';

class FlightbookPage extends ConsumerWidget {
  const FlightbookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final aircraftById = {for (final item in fleet.aircraft) item.id: item};

    return AppScaffold(
      title: 'Flugbuch',
      subtitle:
          'Starts, Flugzeiten, Akkusaetze und Beobachtungen direkt nach dem Flug erfassen.',
      action: _FlightbookActions(
        enabled: fleet.aircraft.isNotEmpty,
        onQuickEntry: () => _showQuickFlightDialog(context, ref, fleet),
      ),
      children: [
        _FlightbookTable(
          flights: fleet.flights,
          aircraftById: aircraftById,
          batteries: fleet.batteries,
          onEdit: (flight) => _showFlightDialog(
            context,
            ref,
            fleet.aircraft,
            flight: flight,
          ),
        ),
      ],
    );
  }

  Future<void> _showQuickFlightDialog(
    BuildContext context,
    WidgetRef ref,
    FleetState fleet,
  ) async {
    final result = await showDialog<_QuickFlightResult>(
      context: context,
      builder: (context) => _QuickFlightDialog(
        aircraft: fleet.aircraft,
        batteries: fleet.batteries,
        pilotProfile: fleet.pilotProfile,
      ),
    );

    if (result == null) {
      return;
    }

    ref.read(fleetProvider.notifier).addFlight(
          result.entry,
          usedBatteryId: result.usedBatteryId,
        );

    if (!context.mounted) {
      return;
    }

    final aircraftName = fleet.aircraft
        .cast<AircraftModel?>()
        .firstWhere(
          (item) => item?.id == result.entry.aircraftId,
          orElse: () => null,
        )
        ?.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${aircraftName ?? 'Flug'} gespeichert: ${result.entry.durationMinutes} min.',
        ),
      ),
    );
  }

  void _showFlightDialog(
    BuildContext context,
    WidgetRef ref,
    List<AircraftModel> aircraft, {
    FlightLogEntry? flight,
  }) {
    final fleet = ref.read(fleetProvider);
    showDialog<void>(
      context: context,
      builder: (context) => _FlightDialog(
        aircraft: aircraft,
        batteries: fleet.batteries,
        initialFlight: flight,
        onSubmit: (entry) {
          final notifier = ref.read(fleetProvider.notifier);
          if (flight == null) {
            notifier.addFlight(entry);
          } else {
            notifier.updateFlight(entry);
          }
        },
        onDelete: flight == null
            ? null
            : (entry) {
                ref.read(fleetProvider.notifier).deleteFlight(entry.id);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Flugbucheintrag gelöscht.')),
                );
              },
      ),
    );
  }
}

class _FlightbookActions extends StatelessWidget {
  final bool enabled;
  final VoidCallback onQuickEntry;

  const _FlightbookActions({
    required this.enabled,
    required this.onQuickEntry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: enabled ? onQuickEntry : null,
          icon: const Icon(Icons.flash_on_rounded),
          label: const Text('Neuer Eintrag'),
        ),
      ],
    );
  }
}

class _FlightbookTable extends StatefulWidget {
  final List<FlightLogEntry> flights;
  final Map<String, AircraftModel> aircraftById;
  final List<BatteryPack> batteries;
  final ValueChanged<FlightLogEntry> onEdit;

  const _FlightbookTable({
    required this.flights,
    required this.aircraftById,
    required this.batteries,
    required this.onEdit,
  });

  @override
  State<_FlightbookTable> createState() => _FlightbookTableState();
}

class _FlightbookTableState extends State<_FlightbookTable> {
  final ScrollController _horizontalController = ScrollController();
  int _sortColumnIndex = 1;
  bool _sortAscending = false;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy HH:mm');
    final flightNumbers = _flightNumbersById(widget.flights);
    final sortedFlights = _sortedFlights(flightNumbers);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 1260 ? 1260.0 : constraints.maxWidth;

        return SizedBox(
          width: constraints.maxWidth,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: sortedFlights.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Noch keine Fluege eingetragen.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 52, bottom: 10),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: tableWidth),
                            child: IconTheme.merge(
                              data: const IconThemeData(
                                color: Colors.white,
                                opacity: 1,
                                shadows: [
                                  Shadow(
                                    color: Color(0x99001E3C),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: DataTable(
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                headingRowColor: WidgetStateProperty.all(
                                  const Color(0xFF0A84FF),
                                ),
                                headingTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                                headingRowHeight: 40,
                                dataTextStyle: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                                columnSpacing: 16,
                                horizontalMargin: 12,
                                dataRowMinHeight: 72,
                                dataRowMaxHeight: 82,
                                columns: [
                                  _sortableColumn(0, 'Nr.'),
                                  _sortableColumn(1, 'Datum'),
                                  _sortableColumn(2, 'Modell'),
                                  _sortableColumn(3, 'Kategorie'),
                                  _sortableColumn(4, 'Dauer'),
                                  _sortableColumn(5, 'Akku'),
                                  _sortableColumn(6, 'Fluggebiet'),
                                  _sortableColumn(7, 'Pilot'),
                                  _sortableColumn(8, 'Notizen'),
                                  const DataColumn(label: _TableHeader('')),
                                ],
                                rows: List.generate(sortedFlights.length,
                                    (index) {
                                  final flight = sortedFlights[index];
                                  final flightNumber =
                                      flightNumbers[flight.id] ?? index + 1;

                                  return DataRow(
                                    cells: [
                                      DataCell(Text('$flightNumber')),
                                      DataCell(
                                          Text(formatter.format(flight.date))),
                                      DataCell(
                                        _AircraftModelCell(
                                          aircraft: widget
                                              .aircraftById[flight.aircraftId],
                                        ),
                                      ),
                                      DataCell(
                                        _CategoryCell(
                                          category: widget
                                                  .aircraftById[
                                                      flight.aircraftId]
                                                  ?.type ??
                                              '-',
                                        ),
                                      ),
                                      DataCell(Text(
                                          '${flight.durationMinutes} min')),
                                      DataCell(Text(
                                        _flightBatteryLabel(
                                          flight,
                                          widget.batteries,
                                        ),
                                      )),
                                      DataCell(Text(flight.location)),
                                      DataCell(Text(flight.pilot)),
                                      DataCell(
                                        SizedBox(
                                          width: 320,
                                          child: Text(
                                            flight.notes,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        IconButton(
                                          tooltip: 'Eintrag bearbeiten',
                                          icon: const Icon(Icons.edit_rounded),
                                          color: const Color(0xFF0A84FF),
                                          onPressed: () =>
                                              widget.onEdit(flight),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 34,
                        right: 34,
                        top: 8,
                        child: _FloatingTableScrollbar(
                          controller: _horizontalController,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  DataColumn _sortableColumn(int columnIndex, String label) {
    return DataColumn(
      label: _TableHeader(label),
      onSort: (index, ascending) {
        setState(() {
          _sortColumnIndex = index;
          _sortAscending = ascending;
        });
      },
    );
  }

  Map<String, int> _flightNumbersById(List<FlightLogEntry> flights) {
    final chronological = [...flights]
      ..sort((a, b) => a.date.compareTo(b.date));
    return {
      for (var index = 0; index < chronological.length; index++)
        chronological[index].id: index + 1,
    };
  }

  List<FlightLogEntry> _sortedFlights(Map<String, int> flightNumbers) {
    final sorted = [...widget.flights];

    int compareString(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    int compare(FlightLogEntry a, FlightLogEntry b) {
      final aircraftA = widget.aircraftById[a.aircraftId];
      final aircraftB = widget.aircraftById[b.aircraftId];

      return switch (_sortColumnIndex) {
        0 => (flightNumbers[a.id] ?? 0).compareTo(flightNumbers[b.id] ?? 0),
        1 => a.date.compareTo(b.date),
        2 => compareString(
            aircraftA?.name ?? 'Unbekanntes Modell',
            aircraftB?.name ?? 'Unbekanntes Modell',
          ),
        3 => compareString(aircraftA?.type ?? '-', aircraftB?.type ?? '-'),
        4 => a.durationMinutes.compareTo(b.durationMinutes),
        5 => compareString(
            _flightBatteryLabel(a, widget.batteries),
            _flightBatteryLabel(b, widget.batteries),
          ),
        6 => compareString(a.location, b.location),
        7 => compareString(a.pilot, b.pilot),
        8 => compareString(a.notes, b.notes),
        _ => b.date.compareTo(a.date),
      };
    }

    sorted.sort((a, b) {
      final result = compare(a, b);
      if (result != 0) {
        return _sortAscending ? result : -result;
      }
      return b.date.compareTo(a.date);
    });
    return sorted;
  }
}

class _AircraftModelCell extends StatelessWidget {
  final AircraftModel? aircraft;

  const _AircraftModelCell({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final photo =
        aircraft?.photos.isEmpty ?? true ? null : aircraft!.photos.first;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox.square(
            dimension: 60,
            child: photo == null
                ? Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(
                      Icons.flight_rounded,
                      color: Color(0xFF0A84FF),
                      size: 32,
                    ),
                  )
                : Image(
                    image: mediaImageProvider(photo),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(
                        Icons.flight_rounded,
                        color: Color(0xFF0A84FF),
                        size: 32,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 115),
          child: Text(
            aircraft?.name ?? 'Unbekanntes Modell',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FloatingTableScrollbar extends StatefulWidget {
  final ScrollController controller;

  const _FloatingTableScrollbar({required this.controller});

  @override
  State<_FloatingTableScrollbar> createState() =>
      _FloatingTableScrollbarState();
}

class _FloatingTableScrollbarState extends State<_FloatingTableScrollbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _FloatingTableScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleScroll);
      widget.controller.addListener(_handleScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasClients = widget.controller.hasClients;
        final maxExtent =
            hasClients ? widget.controller.position.maxScrollExtent : 0.0;
        final current = hasClients
            ? widget.controller.position.pixels.clamp(0.0, maxExtent)
            : 0.0;
        final ratio = maxExtent <= 0 ? 0.0 : current / maxExtent;
        final thumbWidth = (constraints.maxWidth * 0.36).clamp(92.0, 190.0);
        final travel =
            (constraints.maxWidth - thumbWidth).clamp(0.0, double.infinity);
        final left = travel * ratio;

        void jumpFromLocalDx(double dx) {
          if (!hasClients ||
              maxExtent <= 0 ||
              constraints.maxWidth <= thumbWidth) {
            return;
          }
          final nextRatio = ((dx - thumbWidth / 2) / travel).clamp(0.0, 1.0);
          widget.controller.jumpTo(maxExtent * nextRatio);
        }

        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF0A84FF),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => jumpFromLocalDx(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                jumpFromLocalDx(details.localPosition.dx),
            child: SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF93C5FD),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Positioned(
                    left: left,
                    child: Container(
                      width: thumbWidth,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A84FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String label;

  const _TableHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  static const _drohneIconAsset = 'assets/icons/drohne_60.png';
  static const _hubschrauberIconAsset = 'assets/icons/hubschrauber_60.png';
  static const _jetIconAsset = 'assets/icons/jet_60.png';
  static const _kunstflugIconAsset = 'assets/icons/kunstflug_60.png';
  static const _motorflugIconAsset = 'assets/icons/motorflugz_60.png';
  static const _nurflueglerIconAsset = 'assets/icons/nurfluegler_60.png';
  static const _paragleiterIconAsset = 'assets/icons/paragleiter_60.png';
  static const _scaleIconAsset = 'assets/icons/scale_60.png';
  static const _seglerIconAsset = 'assets/icons/segler_60.png';
  static const _slowflyerIconAsset = 'assets/icons/slowflyer_60.png';
  static const _sonstigeIconAsset = 'assets/icons/sonstige_60.png';

  final String category;

  const _CategoryCell({required this.category});

  @override
  Widget build(BuildContext context) {
    final imageSize = _categoryImageSize(category);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _categoryImageAsset(category) != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  _categoryImageAsset(category)!,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.contain,
                ),
              )
            : Icon(
                _categoryIcon(category),
                color: const Color(0xFF0A84FF),
                size: 60,
              ),
        const SizedBox(width: 7),
        Text(category),
      ],
    );
  }
}

double _categoryImageSize(String category) {
  if (_isSlowflyerCategory(category)) {
    return 40;
  }
  return 60;
}

String? _categoryImageAsset(String category) {
  if (_isDrohneCategory(category)) {
    return _CategoryCell._drohneIconAsset;
  }
  if (_isHubschrauberCategory(category)) {
    return _CategoryCell._hubschrauberIconAsset;
  }
  if (_isJetCategory(category)) {
    return _CategoryCell._jetIconAsset;
  }
  if (_isKunstflugCategory(category)) {
    return _CategoryCell._kunstflugIconAsset;
  }
  if (_isElektroCategory(category)) {
    return _CategoryCell._motorflugIconAsset;
  }
  if (_isParagleiterCategory(category)) {
    return _CategoryCell._paragleiterIconAsset;
  }
  if (_isNurflueglerCategory(category)) {
    return _CategoryCell._nurflueglerIconAsset;
  }
  if (_isSeglerCategory(category)) {
    return _CategoryCell._seglerIconAsset;
  }
  if (_isSlowflyerCategory(category)) {
    return _CategoryCell._slowflyerIconAsset;
  }
  if (_isScaleCategory(category)) {
    return _CategoryCell._scaleIconAsset;
  }
  if (_isSonstigeCategory(category)) {
    return _CategoryCell._sonstigeIconAsset;
  }
  return null;
}

bool _isDrohneCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('drohne') ||
      value.contains('drone') ||
      value.contains('multi') ||
      value.contains('quad');
}

bool _isHubschrauberCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('hubschrauber') || value.contains('heli');
}

bool _isJetCategory(String category) {
  return category.toLowerCase().contains('jet');
}

bool _isKunstflugCategory(String category) {
  return category.toLowerCase().contains('kunst');
}

bool _isElektroCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('elektro') || value.contains('motor');
}

bool _isParagleiterCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('paragleiter') || value.contains('para');
}

bool _isNurflueglerCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('nurfl') || value.contains('flying wing');
}

bool _isSeglerCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('segler') || value.contains('segelflug');
}

bool _isSlowflyerCategory(String category) {
  return category.toLowerCase().contains('slowflyer');
}

bool _isScaleCategory(String category) {
  return category.toLowerCase().contains('scale');
}

bool _isSonstigeCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('sonstige') || value.contains('sonstiges');
}

IconData _categoryIcon(String category) {
  final value = category.toLowerCase();

  if (value.contains('segler') || value.contains('segelflug')) {
    return Icons.air_rounded;
  }
  if (value.contains('elektro')) {
    return Icons.bolt_rounded;
  }
  if (value.contains('drohne') || value.contains('multi')) {
    return Icons.camera_alt_rounded;
  }
  if (value.contains('kunst')) {
    return Icons.loop_rounded;
  }
  if (value.contains('scale')) {
    return Icons.workspace_premium_rounded;
  }
  if (value.contains('jet')) {
    return Icons.flight_takeoff_rounded;
  }
  if (value.contains('trainer')) {
    return Icons.school_rounded;
  }
  if (value.contains('indoor')) {
    return Icons.home_rounded;
  }
  if (value.contains('slow')) {
    return Icons.speed_rounded;
  }
  if (value.contains('wasser')) {
    return Icons.water_drop_rounded;
  }
  if (value.contains('hubschrauber')) {
    return Icons.toys_rounded;
  }
  if (value.contains('verbrenner')) {
    return Icons.local_gas_station_rounded;
  }
  if (value.contains('motorschirm')) {
    return Icons.paragliding_rounded;
  }
  return Icons.airplanemode_active_rounded;
}

String _flightBatteryLabel(
  FlightLogEntry flight,
  Iterable<BatteryPack> batteries,
) {
  final battery = _batteryForFlight(flight, batteries);
  if (battery != null) {
    return _batteryEntryLabel(battery);
  }

  final label = _normalizeBatteryLabel(flight.batteryLabel);
  return label.isEmpty ? '-' : label;
}

class _QuickFlightResult {
  final FlightLogEntry entry;
  final String? usedBatteryId;

  const _QuickFlightResult({
    required this.entry,
    required this.usedBatteryId,
  });
}

class _QuickFlightDialog extends StatefulWidget {
  final List<AircraftModel> aircraft;
  final List<BatteryPack> batteries;
  final PilotProfile pilotProfile;

  const _QuickFlightDialog({
    required this.aircraft,
    required this.batteries,
    required this.pilotProfile,
  });

  @override
  State<_QuickFlightDialog> createState() => _QuickFlightDialogState();
}

class _QuickFlightDialogState extends State<_QuickFlightDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _date;
  late final TextEditingController _batteryLabel;
  late final TextEditingController _location;
  late final TextEditingController _pilot;
  late final TextEditingController _notes;
  late String _aircraftId;
  late DateTime _selectedDate;
  String _selectedBatteryId = '';
  int _durationMinutes = 10;
  int _batteryPacks = 1;
  final _dateFormatter = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _aircraftId = widget.aircraft.first.id;
    _date = TextEditingController(text: _dateFormatter.format(_selectedDate));
    _batteryLabel = TextEditingController();
    _location = TextEditingController(
      text: _defaultFlightLocation(widget.pilotProfile),
    );
    _pilot = TextEditingController(
      text: _defaultPilotName(widget.pilotProfile),
    );
    _notes = TextEditingController();
    _selectedBatteryId = _defaultBatteryId(_batteryOptions);
    if (_selectedBatteryId.isEmpty) {
      _batteryLabel.text = _customBatteryLabel;
    } else {
      _applySelectedBatteryLabel();
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _batteryLabel.dispose();
    _location.dispose();
    _pilot.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<BatteryPack> get _batteryOptions {
    final options = [
      for (final battery in widget.batteries)
        if (battery.aircraftIds.contains(_aircraftId)) battery,
    ]..sort(_compareBatteryOptions);
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final batteryOptions = _batteryOptions;
    final selectedBatteryStillAvailable = batteryOptions.any(
      (battery) => battery.id == _selectedBatteryId,
    );
    final selectedBatteryId =
        selectedBatteryStillAvailable ? _selectedBatteryId : '';
    if (selectedBatteryId != _selectedBatteryId) {
      _selectedBatteryId = selectedBatteryId;
      if (_selectedBatteryId.isEmpty &&
          _selectedBatteryFromLabel(batteryOptions, _batteryLabel.text) ==
              null) {
        _batteryLabel.text = _customBatteryLabel;
      }
    }

    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: const _QuickFlightDialogHeader(),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _aircraftId,
                  decoration: const InputDecoration(
                    labelText: 'Modell',
                    prefixIcon: Icon(Icons.airplanemode_active_rounded),
                  ),
                  items: [
                    for (final item in widget.aircraft)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _aircraftId = value;
                      _selectedBatteryId = _defaultBatteryId(_batteryOptions);
                      if (_selectedBatteryId.isEmpty) {
                        _batteryLabel.text = _customBatteryLabel;
                      } else {
                        _applySelectedBatteryLabel();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _date,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Datum und Uhrzeit',
                    prefixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  onTap: _pickDateTime,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Bitte Datum eintragen.'
                      : null,
                ),
                const SizedBox(height: 12),
                _QuickNumberStepper(
                  label: 'Flugzeit',
                  value: '$_durationMinutes min',
                  onDecrement: _durationMinutes <= 1
                      ? null
                      : () => setState(() => _durationMinutes--),
                  onIncrement: _durationMinutes >= 999
                      ? null
                      : () => setState(() => _durationMinutes++),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in const [5, 8, 10, 12, 15, 20])
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: _durationMinutes == minutes,
                        onSelected: (_) =>
                            setState(() => _durationMinutes = minutes),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _QuickBatteryField(
                  controller: _batteryLabel,
                  batteries: batteryOptions,
                  selectedBatteryId: _selectedBatteryId,
                  onCustomSelected: () {
                    setState(() {
                      _selectedBatteryId = '';
                      if (_batteryLabel.text.trim().isEmpty ||
                          _selectedBatteryFromLabel(
                                batteryOptions,
                                _batteryLabel.text,
                              ) !=
                              null) {
                        _batteryLabel.text = _customBatteryLabel;
                      }
                    });
                  },
                  onBatterySelected: (battery) {
                    setState(() {
                      _selectedBatteryId = battery.id;
                      _batteryLabel.text = _batteryEntryLabel(battery);
                    });
                  },
                ),
                const SizedBox(height: 12),
                _QuickNumberStepper(
                  label: 'Akkusaetze',
                  value: '$_batteryPacks',
                  onDecrement: _batteryPacks <= 1
                      ? null
                      : () => setState(() => _batteryPacks--),
                  onIncrement: _batteryPacks >= 12
                      ? null
                      : () => setState(() => _batteryPacks++),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(
                    labelText: 'Flugplatz',
                    prefixIcon: Icon(Icons.place_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Bitte Flugplatz eintragen.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pilot,
                  decoration: const InputDecoration(
                    labelText: 'Pilot',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Bitte Pilot eintragen.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Kurze Notiz',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final notes = _notes.text.trim();
    final selectedBattery = _batteryById(_batteryOptions, _selectedBatteryId);
    final batteryLabel = selectedBattery == null
        ? _normalizeBatteryLabel(_batteryLabel.text)
        : _batteryEntryLabel(selectedBattery);
    Navigator.of(context).pop(
      _QuickFlightResult(
        entry: FlightLogEntry(
          id: const Uuid().v4(),
          aircraftId: _aircraftId,
          date: _selectedDate,
          location: _location.text.trim(),
          durationMinutes: _durationMinutes,
          batteryPacks: _batteryPacks,
          batteryId: selectedBattery?.id ?? '',
          batteryLabel:
              batteryLabel.isEmpty ? _customBatteryLabel : batteryLabel,
          pilot: _pilot.text.trim(),
          notes: notes.isEmpty ? 'Per Schnelleingabe gespeichert.' : notes,
        ),
        usedBatteryId: _selectedBatteryIdForCycle(),
      ),
    );
  }

  String? _selectedBatteryIdForCycle() {
    return _batteryById(_batteryOptions, _selectedBatteryId)?.id;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _date.text = _dateFormatter.format(_selectedDate);
    });
  }

  void _applySelectedBatteryLabel() {
    if (_selectedBatteryId.isEmpty) {
      return;
    }

    for (final battery in _batteryOptions) {
      if (battery.id == _selectedBatteryId) {
        _batteryLabel.text = _batteryEntryLabel(battery);
        return;
      }
    }
  }
}

class _QuickFlightDialogHeader extends StatelessWidget {
  const _QuickFlightDialogHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF06172E),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: const Row(
        children: [
          Icon(
            Icons.flight_takeoff_rounded,
            color: Colors.white,
          ),
          SizedBox(width: 10),
          Text(
            'Neuer Eintrag',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickBatteryField extends StatelessWidget {
  static const _customValue = '__custom__';

  final TextEditingController controller;
  final List<BatteryPack> batteries;
  final String selectedBatteryId;
  final VoidCallback onCustomSelected;
  final ValueChanged<BatteryPack> onBatterySelected;

  const _QuickBatteryField({
    required this.controller,
    required this.batteries,
    required this.selectedBatteryId,
    required this.onCustomSelected,
    required this.onBatterySelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBattery = _batteryById(batteries, selectedBatteryId) ??
        _selectedBatteryFromLabel(batteries, controller.text);
    final dropdownValue = selectedBattery?.id ?? _customValue;

    final dropdown = batteries.isEmpty
        ? null
        : DropdownButtonFormField<String>(
            key: ValueKey(
              'battery-${batteries.map((battery) => '${battery.id}:${battery.label}:${battery.inventoryNumber}:${battery.status.name}').join('|')}-$dropdownValue',
            ),
            initialValue: dropdownValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Akku',
              prefixIcon: Icon(Icons.battery_charging_full_rounded),
            ),
            items: [
              for (final battery in batteries)
                DropdownMenuItem(
                  value: battery.id,
                  child: Text(
                    _batteryOptionLabel(battery),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const DropdownMenuItem(
                value: _customValue,
                child: Text('Anderer Akku'),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              if (value == _customValue) {
                onCustomSelected();
                return;
              }

              final battery = _batteryById(batteries, value);
              if (battery != null) {
                onBatterySelected(battery);
              }
            },
          );

    final customField = TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: batteries.isEmpty ? 'Akku' : 'Akku selbst eintragen',
        prefixIcon: const Icon(Icons.edit_rounded),
      ),
    );

    if (dropdown == null) {
      return customField;
    }

    if (dropdownValue != _customValue) {
      return dropdown;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dropdown,
        const SizedBox(height: 8),
        customField,
      ],
    );
  }
}

class _QuickNumberStepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const _QuickNumberStepper({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: '$label verringern',
            onPressed: onDecrement,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 86,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF06172E),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filled(
            tooltip: '$label erhoehen',
            onPressed: onIncrement,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

String _defaultBatteryId(List<BatteryPack> batteries) {
  for (final battery in batteries) {
    if (battery.status == BatteryStatus.charged) {
      return battery.id;
    }
  }
  return batteries.isEmpty ? '' : batteries.first.id;
}

int _compareBatteryOptions(BatteryPack a, BatteryPack b) {
  final status = _batteryStatusSortValue(a.status)
      .compareTo(_batteryStatusSortValue(b.status));
  if (status != 0) {
    return status;
  }
  final number = a.inventoryNumber.compareTo(b.inventoryNumber);
  if (number != 0) {
    return number;
  }
  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

int _batteryStatusSortValue(BatteryStatus status) {
  return switch (status) {
    BatteryStatus.charged => 0,
    BatteryStatus.storage => 1,
    BatteryStatus.discharged => 2,
    BatteryStatus.service => 3,
  };
}

String _batteryOptionLabel(BatteryPack battery) {
  final number =
      battery.inventoryNumber > 0 ? 'Akku ${battery.inventoryNumber}: ' : '';
  return '$number${battery.label} - ${battery.cells}S ${battery.capacityMah} mAh - ${battery.status.label}';
}

String _batteryEntryLabel(BatteryPack battery) {
  final number =
      battery.inventoryNumber > 0 ? 'Akku ${battery.inventoryNumber}: ' : '';
  return '$number${battery.label}';
}

const _customBatteryLabel = 'Anderer Akku';
const _legacyCustomBatteryLabel = 'Eigenangabe';

String _normalizeBatteryLabel(String label) {
  final cleanLabel = label.trim();
  if (cleanLabel == _legacyCustomBatteryLabel) {
    return _customBatteryLabel;
  }
  return cleanLabel;
}

BatteryPack? _selectedBatteryFromLabel(
  List<BatteryPack> batteries,
  String label,
) {
  final cleanLabel = _normalizeBatteryLabel(label);
  for (final battery in batteries) {
    if (_batteryEntryLabel(battery) == cleanLabel) {
      return battery;
    }
  }
  return null;
}

BatteryPack? _batteryById(Iterable<BatteryPack> batteries, String batteryId) {
  final cleanBatteryId = batteryId.trim();
  if (cleanBatteryId.isEmpty) {
    return null;
  }

  for (final battery in batteries) {
    if (battery.id == cleanBatteryId) {
      return battery;
    }
  }
  return null;
}

BatteryPack? _batteryForFlight(
  FlightLogEntry? flight,
  Iterable<BatteryPack> batteries,
) {
  if (flight == null) {
    return null;
  }

  final byId = _batteryById(batteries, flight.batteryId);
  if (byId != null) {
    return byId;
  }

  final batteryList = batteries.toList();
  final byLabel = _selectedBatteryFromLabel(batteryList, flight.batteryLabel);
  if (byLabel != null) {
    return byLabel;
  }

  final inventoryNumber = _batteryInventoryNumberFromLabel(flight.batteryLabel);
  if (inventoryNumber == null) {
    return null;
  }

  for (final battery in batteryList) {
    if (battery.inventoryNumber == inventoryNumber) {
      return battery;
    }
  }
  return null;
}

int? _batteryInventoryNumberFromLabel(String label) {
  final match = RegExp(r'^Akku\s+(\d+)\s*:').firstMatch(label.trim());
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

String _initialCustomBatteryLabel(String? label) {
  final cleanLabel = _normalizeBatteryLabel(label ?? '');
  return cleanLabel.isEmpty ? _customBatteryLabel : cleanLabel;
}

String _defaultFlightLocation(PilotProfile profile) {
  final homeAirfield = profile.homeAirfield.trim();
  if (homeAirfield.isNotEmpty) {
    return homeAirfield;
  }

  for (final area in profile.flightAreas) {
    final cleanArea = area.trim();
    if (cleanArea.isNotEmpty) {
      return cleanArea;
    }
  }

  return 'Flugplatz';
}

String _defaultPilotName(PilotProfile profile) {
  final name = profile.name.trim();
  return name.isEmpty ? 'Pilot' : name;
}

class _FlightDialog extends StatefulWidget {
  final List<AircraftModel> aircraft;
  final List<BatteryPack> batteries;
  final FlightLogEntry? initialFlight;
  final ValueChanged<FlightLogEntry> onSubmit;
  final ValueChanged<FlightLogEntry>? onDelete;

  const _FlightDialog({
    required this.aircraft,
    required this.batteries,
    this.initialFlight,
    required this.onSubmit,
    this.onDelete,
  });

  @override
  State<_FlightDialog> createState() => _FlightDialogState();
}

class _FlightDialogState extends State<_FlightDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _date;
  late final TextEditingController _location;
  late final TextEditingController _duration;
  late final TextEditingController _batteries;
  late final TextEditingController _batteryLabel;
  late final TextEditingController _pilot;
  late final TextEditingController _notes;
  late String _aircraftId;
  late String _selectedBatteryId;
  late DateTime _selectedDate;
  final _dateFormatter = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    final flight = widget.initialFlight;
    _selectedDate = flight?.date ?? DateTime.now();
    _aircraftId = flight?.aircraftId ?? widget.aircraft.first.id;
    _date = TextEditingController(text: _dateFormatter.format(_selectedDate));
    _location = TextEditingController(text: flight?.location ?? 'MFC Suedhang');
    _duration = TextEditingController(
      text: '${flight?.durationMinutes ?? 12}',
    );
    _batteries = TextEditingController(text: '${flight?.batteryPacks ?? 1}');
    final initialBattery = flight == null
        ? _batteryById(_batteryOptions, _defaultBatteryId(_batteryOptions))
        : _batteryForFlight(flight, _batteryOptions);
    _selectedBatteryId = initialBattery?.id ?? '';
    _batteryLabel = TextEditingController(
      text: initialBattery == null
          ? _initialCustomBatteryLabel(flight?.batteryLabel)
          : _batteryEntryLabel(initialBattery),
    );
    _pilot = TextEditingController(text: flight?.pilot ?? 'Teddy');
    _notes = TextEditingController(text: flight?.notes ?? '');
  }

  @override
  void dispose() {
    _location.dispose();
    _date.dispose();
    _duration.dispose();
    _batteries.dispose();
    _batteryLabel.dispose();
    _pilot.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialFlight != null;
    final batteryOptions = _batteryOptions;

    return AlertDialog(
      title: Text(isEditing ? 'Flug bearbeiten' : 'Flug eintragen'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 508,
                child: DropdownButtonFormField<String>(
                  initialValue: _aircraftId,
                  decoration: const InputDecoration(labelText: 'Modell'),
                  items: [
                    for (final item in widget.aircraft)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _aircraftId = value;
                      _normalizeBatteryLabelForCurrentModel(
                        useDefaultBattery: true,
                      );
                    });
                  },
                ),
              ),
              SizedBox(
                width: 248,
                child: TextFormField(
                  controller: _date,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Datum und Uhrzeit',
                    suffixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  onTap: _pickDateTime,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Pflichtfeld'
                      : null,
                ),
              ),
              _TextField(controller: _location, label: 'Ort'),
              _TextField(controller: _duration, label: 'Minuten'),
              _TextField(controller: _batteries, label: 'Akkusaetze'),
              SizedBox(
                width: 248,
                child: _QuickBatteryField(
                  controller: _batteryLabel,
                  batteries: batteryOptions,
                  selectedBatteryId: _selectedBatteryId,
                  onCustomSelected: () {
                    setState(() {
                      _selectedBatteryId = '';
                      if (_batteryLabel.text.trim().isEmpty ||
                          _selectedBatteryFromLabel(
                                batteryOptions,
                                _batteryLabel.text,
                              ) !=
                              null) {
                        _batteryLabel.text = _customBatteryLabel;
                      }
                    });
                  },
                  onBatterySelected: (battery) {
                    setState(() {
                      _selectedBatteryId = battery.id;
                      _batteryLabel.text = _batteryEntryLabel(battery);
                    });
                  },
                ),
              ),
              _TextField(controller: _pilot, label: 'Pilot'),
              SizedBox(
                width: 508,
                child: TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notizen'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton.icon(
            onPressed: _confirmDelete,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Löschen'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final flight = widget.initialFlight;
    final onDelete = widget.onDelete;
    if (flight == null || onDelete == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text(
          'Dieser Flugbucheintrag wird dauerhaft entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    onDelete(flight);
    Navigator.of(context).pop();
  }

  List<BatteryPack> get _batteryOptions {
    final options = [
      for (final battery in widget.batteries)
        if (battery.aircraftIds.contains(_aircraftId)) battery,
    ]..sort(_compareBatteryOptions);
    return options;
  }

  void _normalizeBatteryLabelForCurrentModel({
    required bool useDefaultBattery,
  }) {
    final selectedBattery = _batteryById(_batteryOptions, _selectedBatteryId) ??
        _selectedBatteryFromLabel(
          _batteryOptions,
          _batteryLabel.text,
        );
    if (selectedBattery != null) {
      _selectedBatteryId = selectedBattery.id;
      _batteryLabel.text = _batteryEntryLabel(selectedBattery);
      return;
    }

    if (useDefaultBattery) {
      final defaultBatteryId = _defaultBatteryId(_batteryOptions);
      for (final battery in _batteryOptions) {
        if (battery.id == defaultBatteryId) {
          _selectedBatteryId = battery.id;
          _batteryLabel.text = _batteryEntryLabel(battery);
          return;
        }
      }
    }

    _selectedBatteryId = '';
    _batteryLabel.text = _customBatteryLabel;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedBattery = _batteryById(_batteryOptions, _selectedBatteryId);
    final batteryLabel = selectedBattery == null
        ? _normalizeBatteryLabel(_batteryLabel.text)
        : _batteryEntryLabel(selectedBattery);
    widget.onSubmit(
      FlightLogEntry(
        id: widget.initialFlight?.id ?? const Uuid().v4(),
        aircraftId: _aircraftId,
        date: _selectedDate,
        location: _location.text.trim(),
        durationMinutes: int.parse(_duration.text),
        batteryPacks: int.parse(_batteries.text),
        batteryId: selectedBattery?.id ?? '',
        batteryLabel: batteryLabel.isEmpty ? _customBatteryLabel : batteryLabel,
        pilot: _pilot.text.trim(),
        notes: _notes.text.trim().isEmpty
            ? 'Keine besonderen Vorkommnisse.'
            : _notes.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _date.text = _dateFormatter.format(_selectedDate);
    });
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _TextField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 248,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Pflichtfeld' : null,
      ),
    );
  }
}
