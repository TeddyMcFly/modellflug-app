import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

class BatteriesPage extends ConsumerWidget {
  const BatteriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final aircraftById = {for (final item in fleet.aircraft) item.id: item};

    return AppScaffold(
      title: 'Akkus',
      subtitle:
          'Akkupacks, Ladezustand, Zyklen und Zuordnung zu deinen Modellen verwalten.',
      action: FilledButton.icon(
        onPressed: () => _showBatteryDialog(context, ref, fleet.aircraft),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Akku anlegen'),
      ),
      children: [
        _BatterySummary(fleet: fleet),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1120
                ? 3
                : constraints.maxWidth >= 760
                    ? 2
                    : 1;

            return GridView.builder(
              itemCount: fleet.batteries.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: columns == 1 ? 1.62 : 1.16,
              ),
              itemBuilder: (context, index) {
                final battery = fleet.batteries[index];
                return _BatteryCard(
                  battery: battery,
                  aircraftName:
                      aircraftById[battery.assignedAircraftId]?.name ?? 'frei',
                  onStatusChanged: (status) => ref
                      .read(fleetProvider.notifier)
                      .updateBatteryStatus(battery.id, status),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _showBatteryDialog(
    BuildContext context,
    WidgetRef ref,
    List<AircraftModel> aircraft,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => _BatteryDialog(
        aircraft: aircraft,
        onSubmit: (battery) =>
            ref.read(fleetProvider.notifier).addBattery(battery),
      ),
    );
  }
}

class _BatterySummary extends StatelessWidget {
  final FleetState fleet;

  const _BatterySummary({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final serviceCount = fleet.batteries
        .where((item) => item.status == BatteryStatus.service)
        .length;

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _SummaryTile(
          icon: Icons.battery_full_rounded,
          label: 'Packs',
          value: '${fleet.batteries.length}',
          color: const Color(0xFF2563EB),
        ),
        _SummaryTile(
          icon: Icons.bolt_rounded,
          label: 'Voll geladen',
          value: '${fleet.chargedBatteryCount}',
          color: const Color(0xFF16A34A),
        ),
        _SummaryTile(
          icon: Icons.warning_rounded,
          label: 'Pruefen',
          value: '$serviceCount',
          color: const Color(0xFFEA580C),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final BatteryPack battery;
  final String aircraftName;
  final ValueChanged<BatteryStatus> onStatusChanged;

  const _BatteryCard({
    required this.battery,
    required this.aircraftName,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');
    final color = _statusColor(battery.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.battery_charging_full_rounded,
                      color: color, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        battery.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${battery.cells}S ${battery.capacityMah} mAh - $aircraftName',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<BatteryStatus>(
                  tooltip: 'Akkustatus aendern',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: onStatusChanged,
                  itemBuilder: (context) => [
                    for (final status in BatteryStatus.values)
                      PopupMenuItem(value: status, child: Text(status.label)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 12,
                value: battery.chargePercent / 100,
                backgroundColor: const Color(0xFFE2E8F0),
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${battery.chargePercent}%',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '${battery.cycles} Zyklen',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              battery.notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF475569), height: 1.35),
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    battery.status.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
                const Spacer(),
                Text(
                  formatter.format(battery.lastUsed),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.charged => const Color(0xFF16A34A),
      BatteryStatus.storage => const Color(0xFF2563EB),
      BatteryStatus.charging => const Color(0xFF7C3AED),
      BatteryStatus.service => const Color(0xFFEA580C),
    };
  }
}

class _BatteryDialog extends StatefulWidget {
  final List<AircraftModel> aircraft;
  final ValueChanged<BatteryPack> onSubmit;

  const _BatteryDialog({
    required this.aircraft,
    required this.onSubmit,
  });

  @override
  State<_BatteryDialog> createState() => _BatteryDialogState();
}

class _BatteryDialogState extends State<_BatteryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _chemistry = TextEditingController(text: 'LiPo');
  final _cells = TextEditingController(text: '4');
  final _capacity = TextEditingController(text: '2200');
  final _charge = TextEditingController(text: '60');
  final _cycles = TextEditingController(text: '0');
  final _notes = TextEditingController();
  BatteryStatus _status = BatteryStatus.storage;
  late String _aircraftId =
      widget.aircraft.isEmpty ? '' : widget.aircraft.first.id;

  @override
  void dispose() {
    _label.dispose();
    _chemistry.dispose();
    _cells.dispose();
    _capacity.dispose();
    _charge.dispose();
    _cycles.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuer Akku'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _TextField(controller: _label, label: 'Bezeichnung'),
                _TextField(controller: _chemistry, label: 'Chemie'),
                _TextField(controller: _cells, label: 'Zellen'),
                _TextField(controller: _capacity, label: 'Kapazitaet mAh'),
                _TextField(controller: _charge, label: 'Ladung %'),
                _TextField(controller: _cycles, label: 'Zyklen'),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<BatteryStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final status in BatteryStatus.values)
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
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: _aircraftId,
                    decoration: const InputDecoration(labelText: 'Modell'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('frei')),
                      for (final item in widget.aircraft)
                        DropdownMenuItem(
                            value: item.id, child: Text(item.name)),
                    ],
                    onChanged: (value) =>
                        setState(() => _aircraftId = value ?? _aircraftId),
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
      BatteryPack(
        id: const Uuid().v4(),
        label: _label.text.trim(),
        chemistry: _chemistry.text.trim(),
        cells: int.parse(_cells.text),
        capacityMah: int.parse(_capacity.text),
        chargePercent: int.parse(_charge.text).clamp(0, 100),
        cycles: int.parse(_cycles.text),
        status: _status,
        lastUsed: DateTime.now(),
        assignedAircraftId: _aircraftId,
        notes: _notes.text.trim().isEmpty
            ? 'Noch keine Akkunotizen hinterlegt.'
            : _notes.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _TextField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Pflichtfeld' : null,
      ),
    );
  }
}
