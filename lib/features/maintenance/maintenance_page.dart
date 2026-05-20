import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

class MaintenancePage extends ConsumerWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final now = DateTime.now();
    final dueAircraft = fleet.aircraft
        .where((aircraft) =>
            aircraft.nextService.isBefore(now) ||
            aircraft.status == AircraftStatus.maintenance)
        .toList()
      ..sort((a, b) => a.nextService.compareTo(b.nextService));
    final upcomingAircraft = fleet.aircraft
        .where((aircraft) =>
            aircraft.nextService.isAfter(now) &&
            aircraft.status != AircraftStatus.maintenance)
        .toList()
      ..sort((a, b) => a.nextService.compareTo(b.nextService));
    final batteriesToCheck = fleet.batteries
        .where((battery) => battery.status == BatteryStatus.service)
        .toList()
      ..sort((a, b) => b.cycles.compareTo(a.cycles));

    return AppScaffold(
      title: 'Wartung',
      subtitle:
          'Wartungsfaellige Modelle, Akkupruefung und naechste Termine im Blick behalten.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MaintenanceMetric(
              icon: Icons.build_circle_rounded,
              label: 'Offene Wartungen',
              value: '${dueAircraft.length}',
              color: const Color(0xFFEA580C),
            ),
            _MaintenanceMetric(
              icon: Icons.calendar_month_rounded,
              label: 'Geplant',
              value: '${upcomingAircraft.length}',
              color: const Color(0xFF0A84FF),
            ),
            _MaintenanceMetric(
              icon: Icons.battery_alert_rounded,
              label: 'Akkus pruefen',
              value: '${batteriesToCheck.length}',
              color: const Color(0xFF64748B),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            final duePanel = _AircraftMaintenancePanel(
              title: 'Faellige Wartungen',
              aircraft: dueAircraft,
              emptyText: 'Keine faelligen Wartungen.',
            );
            final upcomingPanel = _AircraftMaintenancePanel(
              title: 'Naechste Termine',
              aircraft: upcomingAircraft,
              emptyText: 'Keine geplanten Wartungen.',
            );
            final batteryPanel = _BatteryMaintenancePanel(
              batteries: batteriesToCheck,
              aircraft: fleet.aircraft,
            );

            if (!isWide) {
              return Column(
                children: [
                  duePanel,
                  const SizedBox(height: 14),
                  upcomingPanel,
                  const SizedBox(height: 14),
                  batteryPanel,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: duePanel),
                const SizedBox(width: 14),
                Expanded(child: upcomingPanel),
                const SizedBox(width: 14),
                SizedBox(width: 340, child: batteryPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MaintenanceMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MaintenanceMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AircraftMaintenancePanel extends StatelessWidget {
  final String title;
  final List<AircraftModel> aircraft;
  final String emptyText;

  const _AircraftMaintenancePanel({
    required this.title,
    required this.aircraft,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(icon: Icons.construction_rounded, title: title),
            const SizedBox(height: 12),
            if (aircraft.isEmpty)
              _EmptyMaintenanceText(text: emptyText)
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.4),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                  },
                  border: TableBorder.all(color: const Color(0xFFE2E8F0)),
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFEFF6FF)),
                      children: [
                        _TableCell('Modell', header: true),
                        _TableCell('Letzte', header: true),
                        _TableCell('Naechste', header: true),
                      ],
                    ),
                    for (final item in aircraft)
                      TableRow(
                        children: [
                          _TableCell(item.name),
                          _TableCell(formatter.format(item.lastService)),
                          _TableCell(formatter.format(item.nextService)),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BatteryMaintenancePanel extends StatelessWidget {
  final List<BatteryPack> batteries;
  final List<AircraftModel> aircraft;

  const _BatteryMaintenancePanel({
    required this.batteries,
    required this.aircraft,
  });

  @override
  Widget build(BuildContext context) {
    final aircraftById = {for (final item in aircraft) item.id: item};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.battery_alert_rounded,
              title: 'Akku-Pruefung',
            ),
            const SizedBox(height: 12),
            if (batteries.isEmpty)
              const _EmptyMaintenanceText(text: 'Keine Akkus zur Pruefung.')
            else
              for (final battery in batteries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.battery_charging_full_rounded,
                        color: Color(0xFF64748B),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              battery.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '${battery.cells}S ${battery.capacityMah} mAh - '
                              '${aircraftById[battery.assignedAircraftId]?.name ?? 'frei'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${battery.cycles}x',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0A84FF), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool header;

  const _TableCell(this.text, {this.header = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: header ? const Color(0xFF06172E) : const Color(0xFF334155),
          fontSize: 12,
          fontWeight: header ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyMaintenanceText extends StatelessWidget {
  final String text;

  const _EmptyMaintenanceText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
