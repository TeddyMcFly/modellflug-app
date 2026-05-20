import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

const _tabAccentColor = Colors.white;

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
        _BatteryInventoryTabs(
          batteries: fleet.batteries,
          aircraftById: aircraftById,
          batteryTypes: fleet.appSettings.batteryTypes,
          cycleWarningThreshold: fleet.appSettings.batteryProblemCycleThreshold,
          onEdit: (battery) => _showBatteryDialog(
            context,
            ref,
            fleet.aircraft,
            battery: battery,
          ),
          onStatusChanged: (batteryId, status) => ref
              .read(fleetProvider.notifier)
              .updateBatteryStatus(batteryId, status),
          onDelete: (batteryId) =>
              ref.read(fleetProvider.notifier).deleteBattery(batteryId),
        ),
      ],
    );
  }

  void _showBatteryDialog(
    BuildContext context,
    WidgetRef ref,
    List<AircraftModel> aircraft, {
    BatteryPack? battery,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => _BatteryDialog(
        aircraft: aircraft,
        battery: battery,
        suggestedInventoryNumber:
            ref.read(fleetProvider).nextBatteryInventoryNumber,
        onSubmit: (nextBattery) {
          final notifier = ref.read(fleetProvider.notifier);
          if (battery == null) {
            notifier.addBattery(nextBattery);
          } else {
            notifier.updateBattery(nextBattery);
          }
        },
      ),
    );
  }
}

class _BatteryInventoryTabs extends StatefulWidget {
  final List<BatteryPack> batteries;
  final Map<String, AircraftModel> aircraftById;
  final List<String> batteryTypes;
  final int cycleWarningThreshold;
  final ValueChanged<BatteryPack> onEdit;
  final void Function(String batteryId, BatteryStatus status) onStatusChanged;
  final ValueChanged<String> onDelete;

  const _BatteryInventoryTabs({
    required this.batteries,
    required this.aircraftById,
    required this.batteryTypes,
    required this.cycleWarningThreshold,
    required this.onEdit,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  State<_BatteryInventoryTabs> createState() => _BatteryInventoryTabsState();
}

class _BatteryInventoryTabsState extends State<_BatteryInventoryTabs> {
  int _selectedIndex = 0;

  List<String> get _tabs =>
      widget.batteryTypes.isEmpty ? defaultBatteryTypes : widget.batteryTypes;

  @override
  void didUpdateWidget(covariant _BatteryInventoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= _tabs.length) {
      _selectedIndex = _tabs.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = _tabs[_selectedIndex];
    final filteredBatteries = widget.batteries
        .where((battery) => _matchesBatteryType(battery, selectedType))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BatteryTabs(
          tabs: _tabs,
          selectedIndex: _selectedIndex,
          onSelected: (index) => setState(() => _selectedIndex = index),
        ),
        Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: filteredBatteries.isEmpty
                ? _EmptyBatteryTab(label: selectedType)
                : _BatteryGrid(
                    batteries: filteredBatteries,
                    aircraftById: widget.aircraftById,
                    cycleWarningThreshold: widget.cycleWarningThreshold,
                    onEdit: widget.onEdit,
                    onStatusChanged: widget.onStatusChanged,
                    onDelete: widget.onDelete,
                  ),
          ),
        ),
      ],
    );
  }
}

class _BatteryTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _BatteryTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 4, bottom: 0),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (var index = 0; index < tabs.length; index++)
            _BatteryTab(
              label: tabs[index],
              selected: index == selectedIndex,
              onTap: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _BatteryTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BatteryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      onTap: onTap,
      child: Opacity(
        opacity: selected ? 1 : 0.48,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? _tabAccentColor
                : Colors.white.withValues(alpha: 0.32),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BatteryBoltTabIcon(),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF06172E)
                      : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryBoltTabIcon extends StatelessWidget {
  const _BatteryBoltTabIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 22,
      child: CustomPaint(
        painter: _BatteryBoltTabIconPainter(),
      ),
    );
  }
}

class _BatteryBoltTabIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()..color = Colors.black;
    final innerFramePaint = Paint()..color = Colors.white;
    final innerFillPaint = Paint()..color = Colors.black;
    final battery = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.12, size.width, size.height * 0.88),
      Radius.circular(size.width * 0.20),
    );
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.30,
        0,
        size.width * 0.40,
        size.height * 0.18,
      ),
      Radius.circular(size.width * 0.08),
    );
    final innerFrame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.24,
        size.height * 0.28,
        size.width * 0.52,
        size.height * 0.56,
      ),
      Radius.circular(size.width * 0.04),
    );
    final innerFill = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.32,
        size.height * 0.34,
        size.width * 0.36,
        size.height * 0.44,
      ),
      Radius.circular(size.width * 0.02),
    );
    final bolt = Path()
      ..moveTo(size.width * 0.58, size.height * 0.36)
      ..lineTo(size.width * 0.36, size.height * 0.60)
      ..lineTo(size.width * 0.50, size.height * 0.60)
      ..lineTo(size.width * 0.39, size.height * 0.80)
      ..lineTo(size.width * 0.66, size.height * 0.52)
      ..lineTo(size.width * 0.52, size.height * 0.52)
      ..close();

    canvas.drawRRect(battery, outerPaint);
    canvas.drawRRect(head, outerPaint);
    canvas.drawRRect(innerFrame, innerFramePaint);
    canvas.drawRRect(innerFill, innerFillPaint);
    canvas.drawPath(bolt, Paint()..color = const Color(0xFFF8FAFC));
  }

  @override
  bool shouldRepaint(covariant _BatteryBoltTabIconPainter oldDelegate) => false;
}

class _BatteryGrid extends StatelessWidget {
  final List<BatteryPack> batteries;
  final Map<String, AircraftModel> aircraftById;
  final int cycleWarningThreshold;
  final ValueChanged<BatteryPack> onEdit;
  final void Function(String batteryId, BatteryStatus status) onStatusChanged;
  final ValueChanged<String> onDelete;

  const _BatteryGrid({
    required this.batteries,
    required this.aircraftById,
    required this.cycleWarningThreshold,
    required this.onEdit,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1340
            ? 5
            : constraints.maxWidth >= 1080
                ? 4
                : constraints.maxWidth >= 800
                    ? 3
                    : 1;

        return GridView.builder(
          itemCount: batteries.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 2.22 : 0.94,
          ),
          itemBuilder: (context, index) {
            final battery = batteries[index];
            final aircraftNames = battery.aircraftIds
                .map((id) => aircraftById[id]?.name)
                .whereType<String>()
                .toList();
            return _BatteryCard(
              battery: battery,
              aircraftNames: aircraftNames,
              cycleWarningThreshold: cycleWarningThreshold,
              onEdit: () => onEdit(battery),
              onStatusChanged: (status) => onStatusChanged(battery.id, status),
              onDelete: () => onDelete(battery.id),
            );
          },
        );
      },
    );
  }
}

class _EmptyBatteryTab extends StatelessWidget {
  final String label;

  const _EmptyBatteryTab({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.battery_unknown_rounded,
            color: Color(0xFF94A3B8),
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            'Keine $label Akkus vorhanden.',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
    final flightReadyBatteries = fleet.batteries
        .where((item) => item.status == BatteryStatus.charged)
        .toList();
    final storageBatteries = fleet.batteries
        .where((item) => item.status == BatteryStatus.storage)
        .toList();
    final dischargedBatteries = fleet.batteries
        .where((item) => item.status == BatteryStatus.discharged)
        .toList();
    final serviceBatteries = fleet.batteries
        .where((item) => item.status == BatteryStatus.service)
        .toList();
    final storageCount = fleet.batteries
        .where((item) => item.status == BatteryStatus.storage)
        .length;
    final dischargedCount = fleet.batteries
        .where((item) => item.status == BatteryStatus.discharged)
        .length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryTile(
          icon: Icons.battery_full_rounded,
          label: 'Akku-Anzahl',
          value: '${fleet.batteries.length}',
          color: const Color(0xFF2563EB),
        ),
        _StatusInfoHover(
          info: _BatteryStatusInfo.flightReady,
          statusLabel: 'Flug-ready',
          batteries: flightReadyBatteries,
          child: _SummaryTile(
            icon: Icons.bolt_rounded,
            label: 'Flug-ready',
            value: '${fleet.chargedBatteryCount}',
            color: const Color(0xFF16A34A),
          ),
        ),
        _StatusInfoHover(
          info: _BatteryStatusInfo.storage,
          statusLabel: 'Lagerspannung',
          batteries: storageBatteries,
          child: _SummaryTile(
            icon: Icons.inventory_2_rounded,
            label: 'Lagerspannung',
            value: '$storageCount',
            color: const Color(0xFF2563EB),
          ),
        ),
        _StatusInfoHover(
          info: _BatteryStatusInfo.discharged,
          statusLabel: 'Leer geflogen',
          batteries: dischargedBatteries,
          child: _SummaryTile(
            icon: Icons.battery_alert_rounded,
            label: 'Leer geflogen',
            value: '$dischargedCount',
            color: const Color(0xFFEAB308),
          ),
        ),
        _StatusInfoHover(
          info: _BatteryStatusInfo.service,
          statusLabel: 'Pruefen',
          batteries: serviceBatteries,
          child: _SummaryTile(
            icon: Icons.warning_rounded,
            label: 'Pruefen',
            value: '$serviceCount',
            color: const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }
}

class _StatusInfoHover extends StatefulWidget {
  final _BatteryStatusInfo info;
  final String statusLabel;
  final List<BatteryPack> batteries;
  final Widget child;

  const _StatusInfoHover({
    required this.info,
    required this.statusLabel,
    required this.batteries,
    required this.child,
  });

  @override
  State<_StatusInfoHover> createState() => _StatusInfoHoverState();
}

class _StatusInfoHoverState extends State<_StatusInfoHover> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        onEnter: (_) => _showOverlay(),
        onExit: (_) => _hideOverlay(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _hideOverlay();
            _showAffectedBatteriesDialog(
              context,
              statusLabel: widget.statusLabel,
              batteries: widget.batteries,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 8),
            child: Material(
              color: Colors.transparent,
              child: UnconstrainedBox(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 160,
                  child: _BatteryStatusPopup(info: widget.info),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

Future<void> _showAffectedBatteriesDialog(
  BuildContext context, {
  required String statusLabel,
  required List<BatteryPack> batteries,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Akkus: $statusLabel'),
        content: SizedBox(
          width: 420,
          child: batteries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Keine Akkus mit diesem Status vorhanden.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < batteries.length; index++) ...[
                      _AffectedBatteryTile(battery: batteries[index]),
                      if (index < batteries.length - 1)
                        const Divider(height: 18),
                    ],
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
    },
  );
}

class _AffectedBatteryTile extends StatelessWidget {
  final BatteryPack battery;

  const _AffectedBatteryTile({required this.battery});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 50,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            _statusIconAssetFor(battery.status),
            fit: BoxFit.contain,
          ),
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
                  color: Color(0xFF06172E),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${battery.cells}S ${battery.capacityMah} mAh - ${battery.cRate}C',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${battery.cycles} Zyklen',
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
    );
  }
}

class _BatteryStatusInfo {
  final String assetPath;
  final Color color;

  const _BatteryStatusInfo({
    required this.assetPath,
    required this.color,
  });

  static const flightReady = _BatteryStatusInfo(
    assetPath: 'assets/icons/battery_status_full.jpg',
    color: Color(0xFF16A34A),
  );

  static const storage = _BatteryStatusInfo(
    assetPath: 'assets/icons/battery_status_storage.jpg',
    color: Color(0xFF2563EB),
  );

  static const discharged = _BatteryStatusInfo(
    assetPath: 'assets/icons/battery_status_discharged.jpg',
    color: Color(0xFFEAB308),
  );

  static const service = _BatteryStatusInfo(
    assetPath: 'assets/icons/battery_status_service.jpg',
    color: Color(0xFFDC2626),
  );
}

class _BatteryStatusPopup extends StatelessWidget {
  final _BatteryStatusInfo info;

  const _BatteryStatusPopup({required this.info});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black,
      elevation: 10,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: info.color.withValues(alpha: 0.85), width: 1.2),
      ),
      child: Image.asset(
        info.assetPath,
        width: 210,
        fit: BoxFit.contain,
      ),
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
      width: 168,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
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
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _matchesBatteryType(BatteryPack battery, String type) {
  final normalizedType = type.toLowerCase();
  final chemistry = battery.chemistry.toLowerCase();
  final lipoMatch = RegExp(r'lipo\s+(\d+)s').firstMatch(normalizedType);
  if (lipoMatch != null) {
    return chemistry.contains('lipo') &&
        battery.cells == int.parse(lipoMatch.group(1)!);
  }
  if (normalizedType.contains('life')) {
    return chemistry.contains('life') || chemistry.contains('lifepo');
  }
  if (normalizedType.contains('liion')) {
    return chemistry.contains('liion') || chemistry.contains('li-ion');
  }
  if (normalizedType.contains('nimh')) {
    return chemistry.contains('nimh');
  }
  return chemistry.contains(normalizedType);
}

String _statusIconAssetFor(BatteryStatus status) {
  return switch (status) {
    BatteryStatus.charged => 'assets/icons/battery_card_status_full.jpg',
    BatteryStatus.storage => 'assets/icons/battery_card_status_storage.jpg',
    BatteryStatus.discharged =>
      'assets/icons/battery_card_status_discharged.jpg',
    BatteryStatus.service => 'assets/icons/battery_card_status_service.jpg',
  };
}

class _BatteryCard extends StatelessWidget {
  final BatteryPack battery;
  final List<String> aircraftNames;
  final int cycleWarningThreshold;
  final VoidCallback onEdit;
  final ValueChanged<BatteryStatus> onStatusChanged;
  final VoidCallback onDelete;

  const _BatteryCard({
    required this.battery,
    required this.aircraftNames,
    required this.cycleWarningThreshold,
    required this.onEdit,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(battery.status);
    final backgroundColor = _statusBackgroundColor(battery.status);
    final cycleRatio = cycleWarningThreshold <= 0
        ? 0.0
        : (battery.cycles / cycleWarningThreshold).clamp(0.0, 1.0);
    final cycleColor = Color.lerp(
      const Color(0xFF16A34A),
      const Color(0xFFDC2626),
      cycleRatio,
    )!;

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.48),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    battery.inventoryNumber.toString(),
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 38,
                  height: 62,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.55)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    _statusIconAsset(battery.status),
                    fit: BoxFit.contain,
                  ),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${battery.cells}S ${battery.capacityMah} mAh - ${battery.cRate}C',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        battery.manufacturer.isNotEmpty
                            ? battery.manufacturer
                            : battery.chemistry,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (battery.manufacturer.isNotEmpty)
                        Text(
                          battery.chemistry,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
                PopupMenuButton<Object>(
                  tooltip: 'Akkuaktionen',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    } else if (value is BatteryStatus) {
                      onStatusChanged(value);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded),
                          SizedBox(width: 10),
                          Text('Bearbeiten'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    for (final status in BatteryStatus.values)
                      PopupMenuItem(value: status, child: Text(status.label)),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(width: 10),
                          Text('Loeschen'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AssignedAircraftRow(aircraftNames: aircraftNames),
            const SizedBox(height: 8),
            _CycleStatusBar(
              cycles: battery.cycles,
              threshold: cycleWarningThreshold,
              ratio: cycleRatio,
              markerColor: cycleColor,
            ),
            const SizedBox(height: 5),
            Text(
              _cycleAssessment(cycleRatio),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cycleColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              battery.notes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    battery.status.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _batteryAgeText(battery.purchaseDate),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
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

  String _batteryAgeText(DateTime purchaseDate) {
    final now = DateTime.now();
    var years = now.year - purchaseDate.year;
    var months = now.month - purchaseDate.month;
    var days = now.day - purchaseDate.day;

    if (days < 0) {
      months -= 1;
      final previousMonth = DateTime(now.year, now.month, 0);
      days += previousMonth.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    if (years > 0) {
      final yearText = years == 1 ? '1 Jahr' : '$years Jahre';
      if (months > 0) {
        final monthText = months == 1 ? '1 Monat' : '$months Monate';
        return '$yearText und $monthText alt';
      }
      return '$yearText alt';
    }
    if (months > 0) {
      return months == 1 ? '1 Monat alt' : '$months Monate alt';
    }

    final totalDays = now.difference(purchaseDate).inDays.clamp(0, 99999);
    return totalDays == 1 ? '1 Tag alt' : '$totalDays Tage alt';
  }

  String _cycleAssessment(double ratio) {
    if (ratio <= 0.2) {
      return 'Akku wie NEU!';
    }
    if (ratio <= 0.4) {
      return 'Immer noch gut in Schuss';
    }
    if (ratio <= 0.6) {
      return 'Nicht mehr ganz taufrisch';
    }
    if (ratio <= 0.8) {
      return 'Schon in die Jahre gekommen';
    }
    return 'Das Ende ist nah...';
  }

  Color _statusColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.charged => const Color(0xFF16A34A),
      BatteryStatus.storage => const Color(0xFF2563EB),
      BatteryStatus.discharged => const Color(0xFFEAB308),
      BatteryStatus.service => const Color(0xFFDC2626),
    };
  }

  Color _statusBackgroundColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.charged => const Color(0xFFEAFBF0),
      BatteryStatus.storage => const Color(0xFFEAF3FF),
      BatteryStatus.discharged => const Color(0xFFFEF9C3),
      BatteryStatus.service => const Color(0xFFFFEEEE),
    };
  }

  String _statusIconAsset(BatteryStatus status) {
    return _statusIconAssetFor(status);
  }
}

class _AssignedAircraftRow extends StatefulWidget {
  final List<String> aircraftNames;

  const _AssignedAircraftRow({required this.aircraftNames});

  @override
  State<_AssignedAircraftRow> createState() => _AssignedAircraftRowState();
}

class _AssignedAircraftRowState extends State<_AssignedAircraftRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names =
        widget.aircraftNames.isEmpty ? ['frei'] : widget.aircraftNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modelle',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 42,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: names.length > 2,
            trackVisibility: names.length > 2,
            thickness: 5,
            radius: const Radius.circular(999),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (var index = 0; index < names.length; index++) ...[
                      _AssignedAircraftChip(label: names[index]),
                      if (index < names.length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssignedAircraftChip extends StatelessWidget {
  final String label;

  const _AssignedAircraftChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.flight_rounded,
            color: Color(0xFF0A84FF),
            size: 13,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleStatusBar extends StatelessWidget {
  final int cycles;
  final int threshold;
  final double ratio;
  final Color markerColor;

  const _CycleStatusBar({
    required this.cycles,
    required this.threshold,
    required this.ratio,
    required this.markerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$cycles Zyklen',
              style: TextStyle(
                color: markerColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              'Grenze $threshold',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        LayoutBuilder(
          builder: (context, constraints) {
            final markerLeft =
                (constraints.maxWidth - 10) * ratio.clamp(0.0, 1.0);

            return SizedBox(
              height: 10,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF16A34A),
                          Color(0xFFEAB308),
                          Color(0xFFDC2626),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: markerLeft,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: markerColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BatteryDialog extends StatefulWidget {
  final List<AircraftModel> aircraft;
  final BatteryPack? battery;
  final int suggestedInventoryNumber;
  final ValueChanged<BatteryPack> onSubmit;

  const _BatteryDialog({
    required this.aircraft,
    this.battery,
    required this.suggestedInventoryNumber,
    required this.onSubmit,
  });

  @override
  State<_BatteryDialog> createState() => _BatteryDialogState();
}

class _BatteryDialogState extends State<_BatteryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _manufacturer;
  late final TextEditingController _chemistry;
  late final TextEditingController _cells;
  late final TextEditingController _capacity;
  late final TextEditingController _cRate;
  late final TextEditingController _cycles;
  late final TextEditingController _purchaseDate;
  late final TextEditingController _notes;
  late BatteryStatus _status;
  late Set<String> _aircraftIds;

  @override
  void initState() {
    super.initState();
    final battery = widget.battery;
    _label = TextEditingController(text: battery?.label ?? '');
    _manufacturer = TextEditingController(text: battery?.manufacturer ?? '');
    _chemistry = TextEditingController(text: battery?.chemistry ?? 'LiPo');
    _cells = TextEditingController(text: '${battery?.cells ?? 4}');
    _capacity = TextEditingController(text: '${battery?.capacityMah ?? 2200}');
    _cRate = TextEditingController(text: '${battery?.cRate ?? 30}');
    _cycles = TextEditingController(text: '${battery?.cycles ?? 0}');
    _purchaseDate = TextEditingController(
      text: DateFormat('dd.MM.yyyy').format(
        battery?.purchaseDate ?? DateTime.now(),
      ),
    );
    _notes = TextEditingController(text: battery?.notes ?? '');
    _status = battery?.status ?? BatteryStatus.storage;
    _aircraftIds = {...?battery?.aircraftIds};
  }

  @override
  void dispose() {
    _label.dispose();
    _manufacturer.dispose();
    _chemistry.dispose();
    _cells.dispose();
    _capacity.dispose();
    _cRate.dispose();
    _cycles.dispose();
    _purchaseDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryNumber =
        widget.battery?.inventoryNumber ?? widget.suggestedInventoryNumber;

    return AlertDialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      title: Text(widget.battery == null ? 'Neuer Akku' : 'Akku bearbeiten'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 2),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 532,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06172E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Akku-Nr. $inventoryNumber',
                        style: const TextStyle(
                          color: Color(0xFF06172E),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  _TextField(controller: _label, label: 'Bezeichnung'),
                  _TextField(controller: _manufacturer, label: 'Hersteller'),
                  _TextField(controller: _chemistry, label: 'Chemie'),
                  _TextField(controller: _cells, label: 'Zellen'),
                  _TextField(controller: _capacity, label: 'Kapazitaet mAh'),
                  _TextField(controller: _cRate, label: 'C-Rate'),
                  _TextField(controller: _cycles, label: 'Zyklen'),
                  _TextField(controller: _purchaseDate, label: 'Kaufdatum'),
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
                    width: 532,
                    child: _AircraftMultiSelect(
                      aircraft: widget.aircraft,
                      selectedIds: _aircraftIds,
                      onChanged: (ids) => setState(() => _aircraftIds = ids),
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
        id: widget.battery?.id ?? const Uuid().v4(),
        inventoryNumber:
            widget.battery?.inventoryNumber ?? widget.suggestedInventoryNumber,
        label: _label.text.trim(),
        manufacturer: _manufacturer.text.trim(),
        chemistry: _chemistry.text.trim(),
        cells: int.parse(_cells.text),
        capacityMah: int.parse(_capacity.text),
        cRate: int.parse(_cRate.text),
        chargePercent: _chargePercentForStatus(_status),
        cycles: int.parse(_cycles.text),
        status: _status,
        purchaseDate: _parseDate(_purchaseDate.text),
        lastUsed: widget.battery?.lastUsed ?? DateTime.now(),
        assignedAircraftId: _aircraftIds.isEmpty ? '' : _aircraftIds.first,
        assignedAircraftIds: _aircraftIds.toList(),
        notes: _notes.text.trim().isEmpty
            ? 'Noch keine Akkunotizen hinterlegt.'
            : _notes.text.trim(),
      ),
    );
    Navigator.of(context).pop();
  }

  DateTime _parseDate(String value) {
    try {
      return DateFormat('dd.MM.yyyy').parseStrict(value.trim());
    } catch (_) {
      return DateTime.now();
    }
  }

  int _chargePercentForStatus(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.charged => 100,
      BatteryStatus.storage => 45,
      BatteryStatus.discharged => 20,
      BatteryStatus.service => widget.battery?.chargePercent ?? 20,
    };
  }
}

class _AircraftMultiSelect extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const _AircraftMultiSelect({
    required this.aircraft,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Modelle'),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (aircraft.isEmpty)
            const Text(
              'Keine Modelle vorhanden',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (final item in aircraft)
              FilterChip(
                label: Text(item.name),
                selected: selectedIds.contains(item.id),
                onSelected: (selected) {
                  final next = {...selectedIds};
                  if (selected) {
                    next.add(item.id);
                  } else {
                    next.remove(item.id);
                  }
                  onChanged(next);
                },
              ),
        ],
      ),
    );
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
