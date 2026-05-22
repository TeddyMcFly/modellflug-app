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
      action: FilledButton.icon(
        onPressed: fleet.aircraft.isEmpty
            ? null
            : () => _showFlightDialog(context, ref, fleet.aircraft),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Flug eintragen'),
      ),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FlightbookMetricCard(
              icon: Icons.timelapse_rounded,
              label: 'Gesamtflugzeit',
              value: '${_totalFlightHours(fleet.flights).toStringAsFixed(1)} h',
            ),
            _FlightbookMetricCard(
              icon: Icons.flight_takeoff_rounded,
              label: 'Gesamtfluege',
              value: '${fleet.flights.length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _FlightbookTable(
          flights: fleet.flights,
          aircraftById: aircraftById,
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

  void _showFlightDialog(
    BuildContext context,
    WidgetRef ref,
    List<AircraftModel> aircraft, {
    FlightLogEntry? flight,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => _FlightDialog(
        aircraft: aircraft,
        initialFlight: flight,
        onSubmit: (entry) {
          final notifier = ref.read(fleetProvider.notifier);
          if (flight == null) {
            notifier.addFlight(entry);
          } else {
            notifier.updateFlight(entry);
          }
        },
      ),
    );
  }
}

class _FlightbookMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FlightbookMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: IntrinsicWidth(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF0A84FF), size: 24),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF06172E),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlightbookTable extends StatefulWidget {
  final List<FlightLogEntry> flights;
  final Map<String, AircraftModel> aircraftById;
  final ValueChanged<FlightLogEntry> onEdit;

  const _FlightbookTable({
    required this.flights,
    required this.aircraftById,
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
            constraints.maxWidth < 1160 ? 1160.0 : constraints.maxWidth;

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
                          padding: const EdgeInsets.only(top: 30, bottom: 10),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: tableWidth),
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
                              columnSpacing: 22,
                              horizontalMargin: 16,
                              dataRowMinHeight: 72,
                              dataRowMaxHeight: 82,
                              columns: [
                                _sortableColumn(0, 'Nr.'),
                                _sortableColumn(1, 'Datum'),
                                _sortableColumn(2, 'Modell'),
                                _sortableColumn(3, 'Kategorie'),
                                _sortableColumn(4, 'Dauer'),
                                _sortableColumn(5, 'Fluggebiet'),
                                _sortableColumn(6, 'Pilot'),
                                _sortableColumn(7, 'Notizen'),
                                const DataColumn(label: _TableHeader('')),
                              ],
                              rows:
                                  List.generate(sortedFlights.length, (index) {
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
                                                .aircraftById[flight.aircraftId]
                                                ?.type ??
                                            '-',
                                      ),
                                    ),
                                    DataCell(
                                        Text('${flight.durationMinutes} min')),
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
                                        onPressed: () => widget.onEdit(flight),
                                      ),
                                    ),
                                  ],
                                );
                              }),
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
        5 => compareString(a.location, b.location),
        6 => compareString(a.pilot, b.pilot),
        7 => compareString(a.notes, b.notes),
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

        return Opacity(
          opacity: 0.55,
          child: Container(
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFCBD5E1).withValues(alpha: 0.55),
              ),
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
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Positioned(
                      left: left,
                      child: Container(
                        width: thumbWidth,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF64748B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
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

double _totalFlightHours(List<FlightLogEntry> flights) {
  final totalMinutes = flights.fold<int>(
    0,
    (sum, flight) => sum + flight.durationMinutes,
  );
  return totalMinutes / 60;
}

class _FlightDialog extends StatefulWidget {
  final List<AircraftModel> aircraft;
  final FlightLogEntry? initialFlight;
  final ValueChanged<FlightLogEntry> onSubmit;

  const _FlightDialog({
    required this.aircraft,
    this.initialFlight,
    required this.onSubmit,
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
  late final TextEditingController _pilot;
  late final TextEditingController _notes;
  late String _aircraftId;
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
    _pilot = TextEditingController(text: flight?.pilot ?? 'Teddy');
    _notes = TextEditingController(text: flight?.notes ?? '');
  }

  @override
  void dispose() {
    _location.dispose();
    _date.dispose();
    _duration.dispose();
    _batteries.dispose();
    _pilot.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialFlight != null;

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
                  onChanged: (value) =>
                      setState(() => _aircraftId = value ?? _aircraftId),
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

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    widget.onSubmit(
      FlightLogEntry(
        id: widget.initialFlight?.id ?? const Uuid().v4(),
        aircraftId: _aircraftId,
        date: _selectedDate,
        location: _location.text.trim(),
        durationMinutes: int.parse(_duration.text),
        batteryPacks: int.parse(_batteries.text),
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
