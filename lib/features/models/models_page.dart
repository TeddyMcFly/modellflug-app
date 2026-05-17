import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

class ModelsPage extends ConsumerStatefulWidget {
  const ModelsPage({super.key});

  @override
  ConsumerState<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends ConsumerState<ModelsPage> {
  String? _selectedAircraftId;

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    final aircraft = fleet.aircraft;
    final selectedAircraft =
        aircraft.isEmpty ? null : _selectedAircraft(aircraft);

    return AppScaffold(
      title: 'Meine Modelle',
      titleFontSize: 19,
      subtitle:
          'Links der komplette Bestand, rechts Fotos, Stammdaten und Details zum ausgewaehlten Modell.',
      action: FilledButton.icon(
        onPressed: () => _showAircraftDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Modell anlegen'),
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 940;

            if (aircraft.isEmpty) {
              return const _EmptyFleet();
            }

            final selected = selectedAircraft!;
            final assignedBatteries = fleet.batteries
                .where((battery) => battery.assignedAircraftId == selected.id)
                .toList();
            if (isWide) {
              return SizedBox(
                height: 680,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _AircraftInventoryList(
                        aircraft: aircraft,
                        selectedId: selected.id,
                        onSelected: _selectAircraft,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: _AircraftDetails(
                            aircraft: selected,
                            assignedBatteries: assignedBatteries,
                            onEdit: () => _showAircraftDialog(context,
                                aircraft: selected),
                            onDelete: () => _confirmDelete(context, selected),
                            onStatusChanged: (status) => ref
                                .read(fleetProvider.notifier)
                                .updateStatus(selected.id, status),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                SizedBox(
                  height: 390,
                  child: _AircraftInventoryList(
                    aircraft: aircraft,
                    selectedId: selected.id,
                    onSelected: _selectAircraft,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 820,
                  child: _AircraftDetails(
                    aircraft: selected,
                    assignedBatteries: assignedBatteries,
                    onEdit: () =>
                        _showAircraftDialog(context, aircraft: selected),
                    onDelete: () => _confirmDelete(context, selected),
                    onStatusChanged: (status) => ref
                        .read(fleetProvider.notifier)
                        .updateStatus(selected.id, status),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  AircraftModel _selectedAircraft(List<AircraftModel> aircraft) {
    if (aircraft.isEmpty) {
      throw StateError('No aircraft available');
    }

    return aircraft.firstWhere(
      (item) => item.id == _selectedAircraftId,
      orElse: () => aircraft.first,
    );
  }

  void _selectAircraft(String id) {
    setState(() => _selectedAircraftId = id);
  }

  void _showAircraftDialog(BuildContext context, {AircraftModel? aircraft}) {
    final editingAircraft = aircraft;
    showDialog<void>(
      context: context,
      builder: (context) => _AircraftDialog(
        aircraft: editingAircraft,
        onSubmit: (aircraft) {
          final notifier = ref.read(fleetProvider.notifier);
          if (editingAircraft == null) {
            notifier.addAircraft(aircraft);
          } else {
            notifier.updateAircraft(aircraft);
          }
          setState(() => _selectedAircraftId = aircraft.id);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AircraftModel aircraft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modell loeschen?'),
        content: Text(
          '${aircraft.name} wird aus dem Bestand entfernt. Zugehoerige Flugbucheintraege werden ebenfalls geloescht; Akkus werden freigegeben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    ref.read(fleetProvider.notifier).deleteAircraft(aircraft.id);
    setState(() => _selectedAircraftId = null);
  }
}

class _AircraftInventoryList extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _AircraftInventoryList({
    required this.aircraft,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Color(0xFF0A84FF)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Meine Modelle',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${aircraft.length}',
                  style: const TextStyle(
                    color: Color(0xFF0A84FF),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: aircraft.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = aircraft[index];
                  return _AircraftListItem(
                    aircraft: item,
                    selected: item.id == selectedId,
                    onTap: () => onSelected(item.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AircraftListItem extends StatelessWidget {
  final AircraftModel aircraft;
  final bool selected;
  final VoidCallback onTap;

  const _AircraftListItem({
    required this.aircraft,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(aircraft.status);

    return Material(
      color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  selected ? const Color(0xFF0A84FF) : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _AircraftPhoto(
                aircraft: aircraft,
                width: 86,
                height: 62,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aircraft.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${aircraft.type} - ${aircraft.registration}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(Icons.circle, color: statusColor, size: 10),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            aircraft.status.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AircraftDetails extends StatelessWidget {
  final AircraftModel aircraft;
  final List<BatteryPack> assignedBatteries;
  final ValueChanged<AircraftStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AircraftDetails({
    required this.aircraft,
    required this.assignedBatteries,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');
    final statusColor = _statusColor(aircraft.status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AircraftPhoto(
                      aircraft: aircraft,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: 20,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  aircraft.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${aircraft.manufacturer} - ${aircraft.registration}',
                                  style: const TextStyle(
                                    color: Color(0xFFE0F2FE),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<AircraftStatus>(
                            tooltip: 'Status aendern',
                            onSelected: onStatusChanged,
                            itemBuilder: (context) => [
                              for (final status in AircraftStatus.values)
                                PopupMenuItem(
                                  value: status,
                                  child: Text(status.label),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    aircraft.status.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.expand_more_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 18,
                      top: 18,
                      child: PopupMenuButton<_AircraftDetailsAction>(
                        tooltip: 'Modellaktionen',
                        onSelected: (action) {
                          switch (action) {
                            case _AircraftDetailsAction.edit:
                              onEdit();
                            case _AircraftDetailsAction.delete:
                              onDelete();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _AircraftDetailsAction.edit,
                            child: Row(
                              children: [
                                Icon(Icons.edit_rounded),
                                SizedBox(width: 10),
                                Text('Bearbeiten'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _AircraftDetailsAction.delete,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded),
                                SizedBox(width: 10),
                                Text('Löschen'),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AircraftInfoTable(
                    aircraft: aircraft,
                    formatter: formatter,
                  ),
                  const SizedBox(height: 22),
                  _FlightTimeGraphic(aircraft: aircraft),
                  const SizedBox(height: 22),
                  _AssignedBatteriesPanel(batteries: assignedBatteries),
                  if (aircraft.photos.length > 1) ...[
                    const SizedBox(height: 22),
                    _PhotoGallery(photos: aircraft.photos),
                  ],
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 650;
                      final maintenance = _InfoPanel(
                        title: 'Wartung',
                        icon: Icons.build_circle_rounded,
                        children: [
                          _InfoLine(
                            label: 'Letzte Wartung',
                            value: formatter.format(aircraft.lastService),
                          ),
                          _InfoLine(
                            label: 'Naechste Wartung',
                            value: formatter.format(aircraft.nextService),
                          ),
                        ],
                      );
                      final notes = _InfoPanel(
                        title: 'Notizen',
                        icon: Icons.notes_rounded,
                        children: [
                          Text(
                            aircraft.notes,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );

                      if (twoColumns) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: maintenance),
                            const SizedBox(width: 14),
                            Expanded(child: notes),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          maintenance,
                          const SizedBox(height: 14),
                          notes,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AircraftPhoto extends StatelessWidget {
  final AircraftModel aircraft;
  final double? width;
  final double? height;
  final BoxFit fit;

  const _AircraftPhoto({
    required this.aircraft,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final photoDataUri = aircraft.photos.isEmpty ? null : aircraft.photos.first;

    return ClipRRect(
      borderRadius: BorderRadius.circular(width == null ? 0 : 8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: photoDataUri == null
            ? Image.asset(
                'assets/splash/landing_page.png',
                fit: fit,
                alignment: _photoAlignment(aircraft),
                filterQuality: FilterQuality.high,
              )
            : Image.memory(
                _bytesFromDataUri(photoDataUri),
                fit: fit,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  'assets/splash/landing_page.png',
                  fit: fit,
                  alignment: _photoAlignment(aircraft),
                  filterQuality: FilterQuality.high,
                ),
              ),
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final List<String> photos;

  const _PhotoGallery({required this.photos});

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      title: 'Fotogalerie',
      icon: Icons.photo_library_rounded,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 132,
                height: 96,
                child: Image.memory(
                  _bytesFromDataUri(photos[index]),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlightTimeGraphic extends StatelessWidget {
  final AircraftModel aircraft;

  const _FlightTimeGraphic({required this.aircraft});

  @override
  Widget build(BuildContext context) {
    final maxHours =
        (aircraft.flightHours < 25 ? 25 : aircraft.flightHours).ceilToDouble();
    final averageMinutes = aircraft.totalFlights == 0
        ? 0
        : (aircraft.flightHours * 60 / aircraft.totalFlights).round();
    final segments = [
      _FlightTimeSegment(
          'Gesamt', aircraft.flightHours, const Color(0xFF0A84FF)),
      _FlightTimeSegment(
        'Starts',
        aircraft.totalFlights / 4,
        const Color(0xFF16A34A),
      ),
      _FlightTimeSegment(
        'Schnitt',
        averageMinutes / 3,
        const Color(0xFFFFB84D),
      ),
    ];

    return _InfoPanel(
      title: 'Flugzeit-Grafik',
      icon: Icons.bar_chart_rounded,
      children: [
        for (final segment in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        segment.label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      switch (segment.label) {
                        'Gesamt' =>
                          '${aircraft.flightHours.toStringAsFixed(1)} h',
                        'Starts' => '${aircraft.totalFlights} Fluege',
                        _ => '$averageMinutes min',
                      },
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 14,
                    value: (segment.value / maxHours).clamp(0.04, 1),
                    color: segment.color,
                    backgroundColor: const Color(0xFFE2E8F0),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlightTimeSegment {
  final String label;
  final double value;
  final Color color;

  const _FlightTimeSegment(this.label, this.value, this.color);
}

class _AssignedBatteriesPanel extends StatelessWidget {
  final List<BatteryPack> batteries;

  const _AssignedBatteriesPanel({required this.batteries});

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      title: 'Zugeordnete Akkus',
      icon: Icons.battery_charging_full_rounded,
      children: [
        if (batteries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Diesem Modell sind noch keine Akkus zugeordnet.',
              style: TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        else
          SizedBox(
            height: 152,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: batteries.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _BatteryImageCard(battery: batteries[index]),
            ),
          ),
      ],
    );
  }
}

class _BatteryImageCard extends StatelessWidget {
  final BatteryPack battery;

  const _BatteryImageCard({required this.battery});

  @override
  Widget build(BuildContext context) {
    final color = switch (battery.status) {
      BatteryStatus.charged => const Color(0xFF16A34A),
      BatteryStatus.storage => const Color(0xFF0A84FF),
      BatteryStatus.charging => const Color(0xFF7C3AED),
      BatteryStatus.service => const Color(0xFFEA580C),
    };

    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _BatteryPackPainter(
                color: color,
                percent: battery.chargePercent / 100,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            battery.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            '${battery.cells}S ${battery.capacityMah} mAh - ${battery.status.label}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryPackPainter extends CustomPainter {
  final Color color;
  final double percent;

  const _BatteryPackPainter({
    required this.color,
    required this.percent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, size.height * 0.18, size.width - 18, size.height * 0.58),
      const Radius.circular(8),
    );
    final terminal = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width - 14,
        size.height * 0.34,
        10,
        size.height * 0.26,
      ),
      const Radius.circular(4),
    );
    final fillWidth = (size.width - 30) * percent.clamp(0, 1);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, size.height * 0.26, fillWidth, size.height * 0.42),
      const Radius.circular(6),
    );
    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = const Color(0xFFE2E8F0);
    canvas.drawRRect(body, paint);
    canvas.drawRRect(terminal, paint);

    paint.color = color;
    canvas.drawRRect(fill, paint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.46)
      ..strokeWidth = 2;
    for (var i = 1; i < 4; i++) {
      final x = 10 + (size.width - 30) * i / 4;
      canvas.drawLine(
        Offset(x, size.height * 0.28),
        Offset(x, size.height * 0.66),
        linePaint,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${(percent * 100).round()}%',
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height * 0.79,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _BatteryPackPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.percent != percent;
  }
}

enum _AircraftDetailsAction { edit, delete }

class _AircraftInfoTable extends StatelessWidget {
  final AircraftModel aircraft;
  final DateFormat formatter;

  const _AircraftInfoTable({
    required this.aircraft,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Kategorie', aircraft.type),
      ('Hersteller', aircraft.manufacturer),
      ('Kennung', aircraft.registration),
      ('Spannweite', '${aircraft.wingspanMeters.toStringAsFixed(2)} m'),
      ('Laenge', '${aircraft.lengthMeters.toStringAsFixed(2)} m'),
      ('Gewicht', '${aircraft.weightKg.toStringAsFixed(1)} kg'),
      ('Antrieb', _fallback(aircraft.drive)),
      ('Empfaenger', _fallback(aircraft.receiver)),
      ('Propeller', _fallback(aircraft.propeller)),
      ('Kaufdatum', formatter.format(aircraft.purchaseDate)),
      ('Akkus', '${aircraft.batteryCount}'),
      ('Fluege', '${aircraft.totalFlights}'),
      ('Flugzeit', '${aircraft.flightHours.toStringAsFixed(1)} h'),
      ('Status', aircraft.status.label),
    ];

    return _InfoPanel(
      title: 'Modelldaten',
      icon: Icons.table_chart_rounded,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(110),
              1: FlexColumnWidth(),
              2: FixedColumnWidth(110),
              3: FlexColumnWidth(),
            },
            border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFE2E8F0)),
              verticalInside: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            children: [
              for (var index = 0; index < rows.length; index += 2)
                TableRow(
                  decoration: BoxDecoration(
                    color: (index ~/ 2).isEven
                        ? Colors.white
                        : const Color(0xFFF1F5F9),
                  ),
                  children: [
                    _InfoTableCell(
                      text: rows[index].$1,
                      isLabel: true,
                    ),
                    _InfoTableCell(text: rows[index].$2),
                    if (index + 1 < rows.length) ...[
                      _InfoTableCell(
                        text: rows[index + 1].$1,
                        isLabel: true,
                      ),
                      _InfoTableCell(text: rows[index + 1].$2),
                    ] else ...[
                      const SizedBox.shrink(),
                      const SizedBox.shrink(),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _fallback(String value) {
    return value.trim().isEmpty ? '-' : value.trim();
  }
}

class _InfoTableCell extends StatelessWidget {
  final String text;
  final bool isLabel;

  const _InfoTableCell({
    required this.text,
    this.isLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isLabel ? const Color(0xFF475569) : const Color(0xFF0F172A),
          fontSize: 13,
          height: 1.15,
          fontWeight: isLabel ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0A84FF)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _EmptyFleet extends StatelessWidget {
  const _EmptyFleet();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Noch keine Modelle angelegt.',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _AircraftDialog extends StatefulWidget {
  final AircraftModel? aircraft;
  final ValueChanged<AircraftModel> onSubmit;

  const _AircraftDialog({
    this.aircraft,
    required this.onSubmit,
  });

  @override
  State<_AircraftDialog> createState() => _AircraftDialogState();
}

class _AircraftDialogState extends State<_AircraftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _manufacturer = TextEditingController();
  final _registration = TextEditingController();
  final _wingspan = TextEditingController(text: '1.80');
  final _length = TextEditingController(text: '1.50');
  final _weight = TextEditingController(text: '2.4');
  final _receiver = TextEditingController();
  final _propeller = TextEditingController();
  final _purchaseDate = TextEditingController(
    text: DateFormat('dd.MM.yyyy').format(DateTime.now()),
  );
  final _drive = TextEditingController();
  final _batteries = TextEditingController(text: '2');
  final _notes = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<String> _photoDataUris = [];
  AircraftStatus _status = AircraftStatus.ready;
  String _type = _aircraftTypes.first;

  bool get _isEditing => widget.aircraft != null;

  @override
  void initState() {
    super.initState();
    final aircraft = widget.aircraft;
    if (aircraft == null) {
      return;
    }

    _name.text = aircraft.name;
    _type = _normalizeAircraftType(aircraft.type);
    _manufacturer.text = aircraft.manufacturer;
    _registration.text = aircraft.registration;
    _wingspan.text = aircraft.wingspanMeters.toStringAsFixed(2);
    _length.text = aircraft.lengthMeters.toStringAsFixed(2);
    _weight.text = aircraft.weightKg.toStringAsFixed(1);
    _receiver.text = aircraft.receiver;
    _propeller.text = aircraft.propeller;
    _purchaseDate.text = DateFormat('dd.MM.yyyy').format(aircraft.purchaseDate);
    _drive.text = aircraft.drive;
    _batteries.text = '${aircraft.batteryCount}';
    _notes.text = aircraft.notes;
    _status = aircraft.status;
    _photoDataUris.addAll(aircraft.photos);
  }

  @override
  void dispose() {
    _name.dispose();
    _manufacturer.dispose();
    _registration.dispose();
    _wingspan.dispose();
    _length.dispose();
    _weight.dispose();
    _receiver.dispose();
    _propeller.dispose();
    _purchaseDate.dispose();
    _drive.dispose();
    _batteries.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Modell bearbeiten' : 'Neues Modell'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 532,
                  child: _PhotoPickerPanel(
                    photoDataUris: _photoDataUris,
                    onPick: _pickPhotos,
                    onRemove: (index) =>
                        setState(() => _photoDataUris.removeAt(index)),
                  ),
                ),
                _TextField(controller: _name, label: 'Name'),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Kategorie'),
                    items: [
                      for (final type in _aircraftTypes)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  ),
                ),
                _TextField(controller: _manufacturer, label: 'Hersteller'),
                _TextField(controller: _registration, label: 'Kennung'),
                _TextField(controller: _wingspan, label: 'Spannweite m'),
                _TextField(controller: _length, label: 'Laenge m'),
                _TextField(controller: _weight, label: 'Gewicht kg'),
                _TextField(
                  controller: _drive,
                  label: 'Antrieb',
                  requiredField: false,
                ),
                _TextField(
                  controller: _receiver,
                  label: 'Empfaenger',
                  requiredField: false,
                ),
                _TextField(
                  controller: _propeller,
                  label: 'Propeller',
                  requiredField: false,
                ),
                _TextField(
                  controller: _purchaseDate,
                  label: 'Kaufdatum TT.MM.JJJJ',
                ),
                _TextField(controller: _batteries, label: 'Akkus'),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<AircraftStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final status in AircraftStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                ),
                SizedBox(
                  width: 532,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Aenderungen speichern' : 'Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final existing = widget.aircraft;
    final purchaseDate = _parseGermanDate(_purchaseDate.text.trim()) ??
        existing?.purchaseDate ??
        now;
    widget.onSubmit(
      AircraftModel(
        id: existing?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        type: _type,
        manufacturer: _manufacturer.text.trim(),
        registration: _registration.text.trim(),
        wingspanMeters: double.parse(_wingspan.text.replaceAll(',', '.')),
        lengthMeters: double.parse(_length.text.replaceAll(',', '.')),
        weightKg: double.parse(_weight.text.replaceAll(',', '.')),
        receiver: _receiver.text.trim(),
        propeller: _propeller.text.trim(),
        purchaseDate: purchaseDate,
        drive: _drive.text.trim(),
        batteryCount: int.parse(_batteries.text),
        totalFlights: existing?.totalFlights ?? 0,
        flightHours: existing?.flightHours ?? 0,
        status: _status,
        lastService: existing?.lastService ?? now,
        nextService: existing?.nextService ?? now.add(const Duration(days: 60)),
        notes: _notes.text.trim().isEmpty
            ? 'Noch keine Notizen hinterlegt.'
            : _notes.text.trim(),
        photoDataUris: List.unmodifiable(_photoDataUris),
      ),
    );
    Navigator.of(context).pop();
  }

  DateTime? _parseGermanDate(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      return DateFormat('dd.MM.yyyy').parseStrict(value);
    } on FormatException {
      return DateTime.tryParse(value);
    }
  }

  Future<void> _pickPhotos() async {
    final pickedImages = await _imagePicker.pickMultiImage(
      imageQuality: 78,
      maxWidth: 1400,
    );

    if (pickedImages.isEmpty) {
      return;
    }

    final dataUris = <String>[];
    for (final pickedImage in pickedImages) {
      final bytes = await pickedImage.readAsBytes();
      final mimeType = _mimeTypeForName(pickedImage.name);
      dataUris.add('data:$mimeType;base64,${base64Encode(bytes)}');
    }

    setState(() {
      _photoDataUris.addAll(dataUris);
    });
  }
}

class _PhotoPickerPanel extends StatelessWidget {
  final List<String> photoDataUris;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  const _PhotoPickerPanel({
    required this.photoDataUris,
    required this.onPick,
    required this.onRemove,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_library_rounded, color: Color(0xFF0A84FF)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modellfotos (${photoDataUris.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_photo_alternate_rounded),
                label: const Text('Fotos hinzufuegen'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (photoDataUris.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF0A84FF)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Noch keine Fotos hinterlegt. Du kannst mehrere Bilder pro Modell speichern.',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photoDataUris.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 142,
                          height: 112,
                          child: Image.memory(
                            _bytesFromDataUri(photoDataUris[index]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filled(
                          onPressed: () => onRemove(index),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool requiredField;

  const _TextField({
    required this.controller,
    required this.label,
    this.requiredField = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (!requiredField) {
            return null;
          }
          return value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;
        },
      ),
    );
  }
}

Color _statusColor(AircraftStatus status) {
  return switch (status) {
    AircraftStatus.ready => const Color(0xFF16A34A),
    AircraftStatus.maintenance => const Color(0xFFEA580C),
    AircraftStatus.destroyed => const Color(0xFFDC2626),
  };
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

const _aircraftTypes = [
  'Segler',
  'Elektromotor-Flieger',
  'Drohne',
  'Kunstflug',
  'Scale-Modell',
  'Jet',
  'Trainer',
  'Indoor',
  'Slowflyer',
  'Wasserflugzeug',
  'Hubschrauber',
  'Verbrenner',
  'Motorschirm',
];

String _normalizeAircraftType(String value) {
  if (_aircraftTypes.contains(value)) {
    return value;
  }

  final lower = value.toLowerCase();
  if (lower.contains('segler')) {
    return 'Segler';
  }
  if (lower.contains('drohne') ||
      lower.contains('drone') ||
      lower.contains('multi') ||
      lower.contains('quad')) {
    return 'Drohne';
  }
  if (lower.contains('kunst') || lower.contains('acro')) {
    return 'Kunstflug';
  }
  if (lower.contains('scale')) {
    return 'Scale-Modell';
  }
  if (lower.contains('jet')) {
    return 'Jet';
  }
  if (lower.contains('trainer') || lower.contains('schule')) {
    return 'Trainer';
  }
  if (lower.contains('indoor')) {
    return 'Indoor';
  }
  if (lower.contains('slow')) {
    return 'Slowflyer';
  }
  if (lower.contains('wasser') || lower.contains('float')) {
    return 'Wasserflugzeug';
  }
  if (lower.contains('hubschrauber') || lower.contains('heli')) {
    return 'Hubschrauber';
  }
  if (lower.contains('verbrenner') ||
      lower.contains('benzin') ||
      lower.contains('glow') ||
      lower.contains('nitro')) {
    return 'Verbrenner';
  }
  if (lower.contains('motorschirm') || lower.contains('para')) {
    return 'Motorschirm';
  }
  return 'Elektromotor-Flieger';
}

Alignment _photoAlignment(AircraftModel aircraft) {
  final id = aircraft.id.toLowerCase();
  final type = aircraft.type.toLowerCase();

  if (id.contains('quad') || type.contains('multi')) {
    return const Alignment(0.88, -0.30);
  }
  if (id.contains('asw') || type.contains('segler')) {
    return const Alignment(0.58, 0.28);
  }
  if (type.contains('kunst') || id.contains('extra')) {
    return const Alignment(-0.52, 0.62);
  }
  if (type.contains('heli')) {
    return const Alignment(-0.84, -0.12);
  }

  return Alignment.center;
}
