import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/utils/image_drop_zone.dart';
import '../../shared/utils/image_thumbnail.dart';
import '../../shared/utils/media_source.dart';

const _tabAccentColor = Colors.white;
const _batteryPhotoMaxDimension = 1200;
const _batteryPhotoJpegQuality = 76;
const _batteryPhotoFallbackMaxBytes = 1024 * 1024;
const _defaultBatteryPreviewAsset = 'assets/icons/battery.png';

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
        onDuplicate: (copiedBattery) =>
            ref.read(fleetProvider.notifier).addBattery(copiedBattery),
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
        SizedBox(
          width: double.infinity,
          child: Card(
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
        const gridSpacing = 12.0;
        const maxCardWidth = 351.0;
        const maxCardHeight = 416.0;
        final cardWidth =
            constraints.maxWidth >= (maxCardWidth * 2) + gridSpacing
                ? maxCardWidth
                : constraints.maxWidth;
        final desiredHeight = cardWidth >= maxCardWidth
            ? maxCardHeight
            : cardWidth.clamp(350.0, maxCardHeight).toDouble();

        return Wrap(
          spacing: gridSpacing,
          runSpacing: gridSpacing,
          children: [
            for (final battery in batteries)
              SizedBox(
                width: cardWidth,
                height: desiredHeight,
                child: _BatteryCard(
                  battery: battery,
                  aircraftNames: battery.aircraftIds
                      .map((id) => aircraftById[id]?.name)
                      .whereType<String>()
                      .toList(),
                  cycleWarningThreshold: cycleWarningThreshold,
                  onEdit: () => onEdit(battery),
                  onStatusChanged: (status) =>
                      onStatusChanged(battery.id, status),
                  onDelete: () => onDelete(battery.id),
                ),
              ),
          ],
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
        _StatusInfoTile(
          statusLabel: 'Akku-Anzahl total',
          batteries: fleet.batteries,
          emptyMessage: 'Keine Akkus vorhanden.',
          child: _SummaryTile(
            icon: Icons.battery_full_rounded,
            label: 'Akku-Anzahl total',
            value: '${fleet.batteries.length}',
            color: const Color(0xFF2563EB),
          ),
        ),
        _StatusInfoTile(
          statusLabel: 'Flug-ready',
          batteries: flightReadyBatteries,
          child: _SummaryTile(
            icon: Icons.bolt_rounded,
            label: 'Flug-ready',
            value: '${fleet.chargedBatteryCount}',
            color: const Color(0xFF16A34A),
          ),
        ),
        _StatusInfoTile(
          statusLabel: 'Lagerspannung',
          batteries: storageBatteries,
          child: _SummaryTile(
            icon: Icons.inventory_2_rounded,
            label: 'Lagerspannung',
            value: '$storageCount',
            color: const Color(0xFF2563EB),
          ),
        ),
        _StatusInfoTile(
          statusLabel: 'Leer geflogen',
          batteries: dischargedBatteries,
          child: _SummaryTile(
            icon: Icons.battery_alert_rounded,
            label: 'Leer geflogen',
            value: '$dischargedCount',
            color: const Color(0xFFEAB308),
          ),
        ),
        _StatusInfoTile(
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

class _StatusInfoTile extends StatelessWidget {
  final String statusLabel;
  final List<BatteryPack> batteries;
  final String emptyMessage;
  final Widget child;

  const _StatusInfoTile({
    required this.statusLabel,
    required this.batteries,
    required this.child,
    this.emptyMessage = 'Keine Akkus mit diesem Status vorhanden.',
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showAffectedBatteriesDialog(
          context,
          statusLabel: statusLabel,
          batteries: batteries,
          emptyMessage: emptyMessage,
        ),
        child: child,
      ),
    );
  }
}

Future<void> _showAffectedBatteriesDialog(
  BuildContext context, {
  required String statusLabel,
  required List<BatteryPack> batteries,
  required String emptyMessage,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Akkus: $statusLabel'),
        content: SizedBox(
          width: 420,
          child: batteries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    emptyMessage,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0;
                            index < batteries.length;
                            index++) ...[
                          _AffectedBatteryTile(battery: batteries[index]),
                          if (index < batteries.length - 1)
                            const Divider(height: 18),
                        ],
                      ],
                    ),
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
                'Akku-Nr. ${battery.inventoryNumber}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF06172E),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                battery.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${battery.cells}S ${battery.capacityMah} mAh - ${battery.dischargeRateLabel}',
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

class _BatteryVisualPreview extends StatelessWidget {
  final BatteryPack battery;
  final Color borderColor;

  const _BatteryVisualPreview({
    required this.battery,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final photoSource = battery.photoSource;

    return LayoutBuilder(
      builder: (context, constraints) {
        const previewHeight = 142.0;

        return Container(
          width: double.infinity,
          height: previewHeight,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              photoSource == null
                  ? Image.asset(
                      _defaultBatteryPreviewAsset,
                      fit: BoxFit.contain,
                    )
                  : Image(
                      image: mediaImageProvider(photoSource),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        _defaultBatteryPreviewAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Text(
                    battery.inventoryNumber.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BatteryStatusPreview extends StatelessWidget {
  final BatteryStatus status;
  final Color borderColor;

  const _BatteryStatusPreview({
    required this.status,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 66,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _statusIconAssetFor(status),
        fit: BoxFit.contain,
      ),
    );
  }
}

class _BatteryActionsMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final ValueChanged<BatteryStatus> onStatusChanged;
  final VoidCallback onDelete;

  const _BatteryActionsMenu({
    required this.onEdit,
    required this.onStatusChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Akkuaktionen',
      icon: const Icon(Icons.more_vert_rounded),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
    );
  }
}

class _BatteryTechnicalDetails extends StatelessWidget {
  final BatteryPack battery;
  final String weightLabel;

  const _BatteryTechnicalDetails({
    required this.battery,
    required this.weightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final mainDetails = [
      '${battery.cells}S',
      '${battery.capacityMah} mAh',
      battery.dischargeRateLabel,
    ].join(' - ');
    final secondaryDetails = [
      if (battery.manufacturer.isNotEmpty) battery.manufacturer,
      battery.chemistry,
      if (weightLabel.isNotEmpty) 'Gewicht $weightLabel',
    ].join(' - ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          battery.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          mainDetails,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          secondaryDetails,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
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
    final weightLabel = _weightLabel(battery);

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BatteryTechnicalDetails(
                    battery: battery,
                    weightLabel: weightLabel,
                  ),
                ),
                const SizedBox(width: 10),
                _BatteryStatusPreview(
                  status: battery.status,
                  borderColor: color.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 4),
                Align(
                  alignment: Alignment.topRight,
                  child: _BatteryActionsMenu(
                    onEdit: onEdit,
                    onStatusChanged: onStatusChanged,
                    onDelete: onDelete,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _BatteryVisualPreview(
              battery: battery,
              borderColor: color.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
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

  String _weightLabel(BatteryPack battery) {
    final value = battery.weightWithCable.trim();
    if (value.isEmpty) {
      return '';
    }
    final lower = value.toLowerCase();
    if (lower.contains('g') || lower.contains('kg')) {
      return value;
    }
    return '$value g';
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
          'Einsatz bei...',
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
  final ValueChanged<BatteryPack> onDuplicate;

  const _BatteryDialog({
    required this.aircraft,
    this.battery,
    required this.suggestedInventoryNumber,
    required this.onSubmit,
    required this.onDuplicate,
  });

  @override
  State<_BatteryDialog> createState() => _BatteryDialogState();
}

class _BatteryDialogState extends State<_BatteryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _label;
  late final TextEditingController _manufacturer;
  late final TextEditingController _chemistry;
  late final TextEditingController _cells;
  late final TextEditingController _capacity;
  late final TextEditingController _cRate;
  late final TextEditingController _weightWithCable;
  late final TextEditingController _dimensionsLxBxH;
  late final TextEditingController _chargeRateRecommendedMax;
  late final TextEditingController _cycles;
  late final TextEditingController _purchaseDate;
  late final TextEditingController _notes;
  late BatteryStatus _status;
  late Set<String> _aircraftIds;
  String? _photoSource;
  String? _photoThumbnailDataUri;
  String? _photoStoragePath;

  @override
  void initState() {
    super.initState();
    final battery = widget.battery;
    _label = TextEditingController(text: battery?.label ?? '');
    _manufacturer = TextEditingController(text: battery?.manufacturer ?? '');
    _chemistry = TextEditingController(text: battery?.chemistry ?? 'LiPo');
    _cells = TextEditingController(text: '${battery?.cells ?? 4}');
    _capacity = TextEditingController(text: '${battery?.capacityMah ?? 2200}');
    _cRate = TextEditingController(text: battery?.cRate ?? '30');
    _weightWithCable = TextEditingController(
      text: battery?.weightWithCable ?? '',
    );
    _dimensionsLxBxH = TextEditingController(
      text: battery?.dimensionsLxBxH ?? '',
    );
    _chargeRateRecommendedMax = TextEditingController(
      text: battery?.chargeRateRecommendedMax ?? '',
    );
    _cycles = TextEditingController(text: '${battery?.cycles ?? 0}');
    _purchaseDate = TextEditingController(
      text: DateFormat('dd.MM.yyyy').format(
        battery?.purchaseDate ?? DateTime.now(),
      ),
    );
    _notes = TextEditingController(text: battery?.notes ?? '');
    _status = battery?.status ?? BatteryStatus.storage;
    _aircraftIds = {...?battery?.aircraftIds};
    _photoSource = battery?.photoSource;
    _photoThumbnailDataUri = battery?.photoThumbnailDataUri;
    _photoStoragePath = battery?.photoStoragePath;
  }

  @override
  void dispose() {
    _label.dispose();
    _manufacturer.dispose();
    _chemistry.dispose();
    _cells.dispose();
    _capacity.dispose();
    _cRate.dispose();
    _weightWithCable.dispose();
    _dimensionsLxBxH.dispose();
    _chargeRateRecommendedMax.dispose();
    _cycles.dispose();
    _purchaseDate.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryNumber =
        widget.battery?.inventoryNumber ?? widget.suggestedInventoryNumber;
    final selectableAircraft = widget.aircraft
        .where(
          (aircraft) =>
              aircraft.status != AircraftStatus.destroyed ||
              _aircraftIds.contains(aircraft.id),
        )
        .toList();

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
                  SizedBox(
                    width: 532,
                    child: _BatteryPhotoPickerPanel(
                      photoSource: _photoSource,
                      onPick: _pickPhoto,
                      onDrop: _acceptDroppedPhoto,
                      onRemove: _removePhoto,
                    ),
                  ),
                  _TextField(controller: _label, label: 'Bezeichnung'),
                  _TextField(
                    controller: _manufacturer,
                    label: 'Hersteller',
                    isRequired: false,
                  ),
                  _TextField(controller: _chemistry, label: 'Chemie'),
                  _TextField(controller: _cells, label: 'Zellen'),
                  _TextField(controller: _capacity, label: 'Kapazitaet mAh'),
                  _TextField(
                    controller: _cRate,
                    label: 'Entladerate Dauer/Kurzzeitig',
                  ),
                  _TextField(
                    controller: _weightWithCable,
                    label: 'Gewicht inkl. Kabel/Stecker',
                    isRequired: false,
                  ),
                  _TextField(
                    controller: _dimensionsLxBxH,
                    label: 'Abmessungen (LxBxH)',
                    isRequired: false,
                  ),
                  _TextField(
                    controller: _chargeRateRecommendedMax,
                    label: 'Laderate empf/max',
                    isRequired: false,
                  ),
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
                      aircraft: selectableAircraft,
                      selectedIds: _aircraftIds,
                      emptyMessage: 'Keine aktiven Modelle vorhanden',
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
        if (widget.battery != null)
          OutlinedButton.icon(
            onPressed: _duplicate,
            icon: const Icon(Icons.content_copy_rounded),
            label: const Text('Kopie mit neuer Nr. anlegen'),
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
      _batteryFromForm(
        id: widget.battery?.id ?? const Uuid().v4(),
        inventoryNumber:
            widget.battery?.inventoryNumber ?? widget.suggestedInventoryNumber,
        lastUsed: widget.battery?.lastUsed ?? DateTime.now(),
      ),
    );
    Navigator.of(context).pop();
  }

  void _duplicate() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    widget.onDuplicate(
      _batteryFromForm(
        id: const Uuid().v4(),
        inventoryNumber: widget.suggestedInventoryNumber,
        lastUsed: DateTime.now(),
      ),
    );
    Navigator.of(context).pop();
  }

  BatteryPack _batteryFromForm({
    required String id,
    required int inventoryNumber,
    required DateTime lastUsed,
  }) {
    final photoSource = _photoSource?.trim();
    final hasPhoto = photoSource != null && photoSource.isNotEmpty;
    final embeddedPhoto = hasPhoto && photoSource.startsWith('data:');

    return BatteryPack(
      id: id,
      inventoryNumber: inventoryNumber,
      label: _label.text.trim(),
      manufacturer: _manufacturer.text.trim(),
      chemistry: _chemistry.text.trim(),
      cells: int.parse(_cells.text),
      capacityMah: int.parse(_capacity.text),
      cRate: _cRate.text.trim(),
      weightWithCable: _weightWithCable.text.trim(),
      dimensionsLxBxH: _dimensionsLxBxH.text.trim(),
      chargeRateRecommendedMax: _chargeRateRecommendedMax.text.trim(),
      chargePercent: _chargePercentForStatus(_status),
      cycles: int.parse(_cycles.text),
      status: _status,
      purchaseDate: _parseDate(_purchaseDate.text),
      lastUsed: lastUsed,
      assignedAircraftId: _aircraftIds.isEmpty ? '' : _aircraftIds.first,
      assignedAircraftIds: _aircraftIds.toList(),
      notes: _notes.text.trim().isEmpty
          ? 'Noch keine Akkunotizen hinterlegt.'
          : _notes.text.trim(),
      photoDataUri: embeddedPhoto ? photoSource : null,
      photoThumbnailDataUri: hasPhoto ? _photoThumbnailDataUri : null,
      photoStoragePath: !embeddedPhoto && hasPhoto ? _photoStoragePath : null,
      photoDownloadUrl: !embeddedPhoto && hasPhoto ? photoSource : null,
    );
  }

  Future<void> _pickPhoto() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: _batteryPhotoJpegQuality,
      maxWidth: _batteryPhotoMaxDimension.toDouble(),
      maxHeight: _batteryPhotoMaxDimension.toDouble(),
    );
    if (pickedImage == null) {
      return;
    }

    try {
      final bytes = await pickedImage.readAsBytes();
      await _storePhoto(bytes, pickedImage.name);
    } catch (_) {
      if (mounted) {
        await _showInputError(
          'Das Foto konnte leider nicht geladen werden. Bitte versuche ein anderes Bild.',
        );
      }
    }
  }

  Future<void> _acceptDroppedPhoto(DroppedImageFile file) async {
    await _storePhoto(file.bytes, file.name);
  }

  Future<void> _storePhoto(Uint8List bytes, String fileName) async {
    final dataUri = _optimizedBatteryPhotoDataUri(bytes, fileName);
    if (dataUri == null) {
      if (mounted) {
        await _showInputError(
          'Das Foto war zu gross und konnte nicht passend verkleinert werden.',
        );
      }
      return;
    }

    final thumbnailDataUri =
        createImageThumbnailDataUriFromDataUri(dataUri, maxSize: 128) ??
            createImageThumbnailDataUri(bytes, maxSize: 128);
    if (!mounted) {
      return;
    }
    setState(() {
      _photoSource = dataUri;
      _photoThumbnailDataUri = thumbnailDataUri;
      _photoStoragePath = null;
    });
  }

  void _removePhoto() {
    setState(() {
      _photoSource = null;
      _photoThumbnailDataUri = null;
      _photoStoragePath = null;
    });
  }

  Future<void> _showInputError(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Foto pruefen'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

class _BatteryPhotoPickerPanel extends StatefulWidget {
  final String? photoSource;
  final VoidCallback onPick;
  final ValueChanged<DroppedImageFile> onDrop;
  final VoidCallback onRemove;

  const _BatteryPhotoPickerPanel({
    required this.photoSource,
    required this.onPick,
    required this.onDrop,
    required this.onRemove,
  });

  @override
  State<_BatteryPhotoPickerPanel> createState() =>
      _BatteryPhotoPickerPanelState();
}

class _BatteryPhotoPickerPanelState extends State<_BatteryPhotoPickerPanel> {
  bool _isDragActive = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.photoSource?.trim();
    final hasPhoto = source != null && source.isNotEmpty;

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
          Container(
            width: 86,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isDragActive
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFFD8E8FF),
                width: _isDragActive ? 2 : 1,
              ),
              boxShadow: _isDragActive
                  ? const [
                      BoxShadow(
                        color: Color(0x330A84FF),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: ImageDropZone(
              onImageDropped: widget.onDrop,
              onDragActiveChanged: (active) {
                if (_isDragActive == active) {
                  return;
                }
                setState(() => _isDragActive = active);
              },
              child: hasPhoto
                  ? Image(
                      image: mediaImageProvider(source),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.battery_charging_full_rounded,
                        color: Color(0xFF0A84FF),
                      ),
                    )
                  : Image.asset(
                      _defaultBatteryPreviewAsset,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Akkufoto',
                  style: TextStyle(
                    color: Color(0xFF06172E),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  hasPhoto
                      ? 'Foto ist hinterlegt.'
                      : 'Noch kein Akkufoto hinterlegt.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onPick,
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text(hasPhoto ? 'Foto aendern' : 'Foto waehlen'),
                    ),
                    if (hasPhoto)
                      TextButton.icon(
                        onPressed: widget.onRemove,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Foto entfernen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AircraftMultiSelect extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final Set<String> selectedIds;
  final String emptyMessage;
  final ValueChanged<Set<String>> onChanged;

  const _AircraftMultiSelect({
    required this.aircraft,
    required this.selectedIds,
    this.emptyMessage = 'Keine Modelle vorhanden',
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Einsatz bei...'),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (aircraft.isEmpty)
            Text(
              emptyMessage,
              style: const TextStyle(color: Color(0xFF64748B)),
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
  final bool isRequired;

  const _TextField({
    required this.controller,
    required this.label,
    this.isRequired = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: isRequired
            ? (value) =>
                value == null || value.trim().isEmpty ? 'Pflichtfeld' : null
            : null,
      ),
    );
  }
}

String _batteryPhotoMimeTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

String? _optimizedBatteryPhotoDataUri(Uint8List bytes, String fileName) {
  final optimizedBytes = _resizeBatteryPhoto(bytes);
  if (optimizedBytes != null) {
    return 'data:image/jpeg;base64,${base64Encode(optimizedBytes)}';
  }

  if (bytes.lengthInBytes > _batteryPhotoFallbackMaxBytes) {
    return null;
  }

  final mimeType = _batteryPhotoMimeTypeForName(fileName);
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

Uint8List? _resizeBatteryPhoto(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    final oriented = img.bakeOrientation(decoded);
    final longestSide = math.max(oriented.width, oriented.height);
    final prepared = longestSide > _batteryPhotoMaxDimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? _batteryPhotoMaxDimension
                : null,
            height: oriented.height > oriented.width
                ? _batteryPhotoMaxDimension
                : null,
            interpolation: img.Interpolation.average,
          )
        : oriented;
    return Uint8List.fromList(
      img.encodeJpg(prepared, quality: _batteryPhotoJpegQuality),
    );
  } catch (_) {
    return null;
  }
}
