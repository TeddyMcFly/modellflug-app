import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

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

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy HH:mm');
    final sortedFlights = [...widget.flights]
      ..sort((a, b) => b.date.compareTo(a.date));

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
                              dataRowMinHeight: 36,
                              dataRowMaxHeight: 52,
                              columns: const [
                                DataColumn(label: _TableHeader('Nr.')),
                                DataColumn(label: _TableHeader('Datum')),
                                DataColumn(label: _TableHeader('Modell')),
                                DataColumn(label: _TableHeader('Kategorie')),
                                DataColumn(label: _TableHeader('Dauer')),
                                DataColumn(label: _TableHeader('Fluggebiet')),
                                DataColumn(label: _TableHeader('Pilot')),
                                DataColumn(label: _TableHeader('Notizen')),
                                DataColumn(label: _TableHeader('')),
                              ],
                              rows:
                                  List.generate(sortedFlights.length, (index) {
                                final flight = sortedFlights[index];
                                final flightNumber =
                                    sortedFlights.length - index;

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
            dimension: 34,
            child: photo == null
                ? Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Icon(
                      Icons.flight_rounded,
                      color: Color(0xFF0A84FF),
                      size: 18,
                    ),
                  )
                : Image.memory(
                    _bytesFromDataUri(photo),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(
                        Icons.flight_rounded,
                        color: Color(0xFF0A84FF),
                        size: 18,
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
  static const _kunstflugIconAsset = 'assets/icons/kunstflug_icon.png';
  static const _motorflugIconAsset = 'assets/icons/motorflugz_icon.png';
  static const _scaleIconAsset = 'assets/icons/scale_icon.png';
  static const _seglerIconAsset = 'assets/icons/segler_icon.png';

  final String category;

  const _CategoryCell({required this.category});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _categoryImageAsset(category) != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  _categoryImageAsset(category)!,
                  width: _categoryImageWidth(category),
                  height: 22,
                  fit: BoxFit.contain,
                ),
              )
            : Icon(
                _categoryIcon(category),
                color: const Color(0xFF0A84FF),
                size: 18,
              ),
        const SizedBox(width: 7),
        Text(category),
      ],
    );
  }
}

String? _categoryImageAsset(String category) {
  if (_isKunstflugCategory(category)) {
    return _CategoryCell._kunstflugIconAsset;
  }
  if (_isElektroCategory(category)) {
    return _CategoryCell._motorflugIconAsset;
  }
  if (_isSeglerCategory(category)) {
    return _CategoryCell._seglerIconAsset;
  }
  if (_isScaleCategory(category)) {
    return _CategoryCell._scaleIconAsset;
  }
  return null;
}

double _categoryImageWidth(String category) {
  if (_isSeglerCategory(category)) {
    return 26;
  }
  if (_isScaleCategory(category)) {
    return 25;
  }
  return 30;
}

bool _isKunstflugCategory(String category) {
  return category.toLowerCase().contains('kunst');
}

bool _isElektroCategory(String category) {
  final value = category.toLowerCase();
  return value.contains('elektro') || value.contains('motor');
}

bool _isSeglerCategory(String category) {
  return category.toLowerCase().contains('segler');
}

bool _isScaleCategory(String category) {
  return category.toLowerCase().contains('scale');
}

IconData _categoryIcon(String category) {
  final value = category.toLowerCase();

  if (value.contains('segler')) {
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

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
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
