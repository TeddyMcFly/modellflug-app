import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

const _repairFilterKey = '__repair__';

class ModelsPage extends ConsumerStatefulWidget {
  final String? initialSelectedAircraftId;

  const ModelsPage({
    super.key,
    this.initialSelectedAircraftId,
  });

  @override
  ConsumerState<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends ConsumerState<ModelsPage> {
  String? _selectedAircraftId;
  String? _selectedCategoryFilter;

  @override
  void initState() {
    super.initState();
    _selectedAircraftId = widget.initialSelectedAircraftId;
  }

  @override
  void didUpdateWidget(covariant ModelsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSelectedAircraftId !=
        widget.initialSelectedAircraftId) {
      _selectedAircraftId = widget.initialSelectedAircraftId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    final aircraft = fleet.aircraft;
    final visibleAircraft = _filteredAircraft(aircraft);
    final selectedAircraft =
        visibleAircraft.isEmpty ? null : _selectedAircraft(visibleAircraft);

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
            if (isWide) {
              return SizedBox(
                height: 1040,
                child: Column(
                  children: [
                    _CategoryFilterPanel(
                      selectedCategory: _selectedCategoryFilter,
                      onSelected: _selectCategoryFilter,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 300,
                            child: _AircraftInventoryList(
                              aircraft: visibleAircraft,
                              totalAircraftCount: aircraft.length,
                              selectedId: selectedAircraft?.id,
                              selectedCategory: _selectedCategoryFilter,
                              onSelected: _selectAircraft,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Flexible(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 620),
                                child: selectedAircraft == null
                                    ? _NoModelsInCategory(
                                        category: _selectedCategoryFilter,
                                      )
                                    : _AircraftDetails(
                                        aircraft: selectedAircraft,
                                        batteries: fleet.batteries,
                                        onEdit: () => _showAircraftDialog(
                                            context,
                                            aircraft: selectedAircraft),
                                        onDelete: () => _confirmDelete(
                                            context, selectedAircraft),
                                        onStartFlight: () => _showFlightTimer(
                                            context, selectedAircraft),
                                        onStatusChanged: (status) => ref
                                            .read(fleetProvider.notifier)
                                            .updateStatus(
                                                selectedAircraft.id, status),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                _CategoryFilterPanel(
                  selectedCategory: _selectedCategoryFilter,
                  onSelected: _selectCategoryFilter,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 390,
                  child: _AircraftInventoryList(
                    aircraft: visibleAircraft,
                    totalAircraftCount: aircraft.length,
                    selectedId: selectedAircraft?.id,
                    selectedCategory: _selectedCategoryFilter,
                    onSelected: _selectAircraft,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 1180,
                  child: selectedAircraft == null
                      ? _NoModelsInCategory(category: _selectedCategoryFilter)
                      : _AircraftDetails(
                          aircraft: selectedAircraft,
                          batteries: fleet.batteries,
                          onEdit: () => _showAircraftDialog(
                            context,
                            aircraft: selectedAircraft,
                          ),
                          onDelete: () =>
                              _confirmDelete(context, selectedAircraft),
                          onStartFlight: () =>
                              _showFlightTimer(context, selectedAircraft),
                          onStatusChanged: (status) => ref
                              .read(fleetProvider.notifier)
                              .updateStatus(selectedAircraft.id, status),
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

  List<AircraftModel> _filteredAircraft(List<AircraftModel> aircraft) {
    final filter = _selectedCategoryFilter;
    if (filter == null) {
      return aircraft;
    }
    if (_isRepairFilter(filter)) {
      return [
        for (final item in aircraft)
          if (item.status == AircraftStatus.maintenance) item,
      ];
    }
    return [
      for (final item in aircraft)
        if (normalizeAircraftCategory(item.type) == filter) item,
    ];
  }

  void _selectCategoryFilter(String? category) {
    final aircraft = ref.read(fleetProvider).aircraft;
    final nextCategory = category == _selectedCategoryFilter ? null : category;
    final nextAircraft = nextCategory == null
        ? aircraft
        : _isRepairFilter(nextCategory)
            ? [
                for (final item in aircraft)
                  if (item.status == AircraftStatus.maintenance) item,
              ]
            : [
                for (final item in aircraft)
                  if (normalizeAircraftCategory(item.type) == nextCategory)
                    item,
              ];

    setState(() {
      _selectedCategoryFilter = nextCategory;
      if (nextAircraft.isEmpty) {
        _selectedAircraftId = null;
      } else if (!nextAircraft.any((item) => item.id == _selectedAircraftId)) {
        _selectedAircraftId = nextAircraft.first.id;
      }
    });
  }

  void _showAircraftDialog(BuildContext context, {AircraftModel? aircraft}) {
    final editingAircraft = aircraft;
    showDialog<void>(
      context: context,
      builder: (context) => _AircraftDialog(
        aircraft: editingAircraft,
        transmitterOptions: ref.read(fleetProvider).pilotProfile.transmitters,
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

  Future<void> _showFlightTimer(
    BuildContext context,
    AircraftModel aircraft,
  ) async {
    final pilotProfile = ref.read(fleetProvider).pilotProfile;
    final result = await showDialog<_FlightTimerResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FlightTimerDialog(
        aircraft: aircraft,
        homeAirfield: pilotProfile.homeAirfield,
        flightAreas: pilotProfile.flightAreas,
      ),
    );

    if (result == null || result.elapsed.inSeconds <= 0) {
      return;
    }

    final durationMinutes =
        (result.elapsed.inSeconds / 60).ceil().clamp(1, 999).toInt();
    ref.read(fleetProvider.notifier).addFlight(
          FlightLogEntry(
            id: const Uuid().v4(),
            aircraftId: aircraft.id,
            date: result.startedAt,
            location: result.location,
            durationMinutes: durationMinutes,
            batteryPacks: 1,
            pilot: pilotProfile.name,
            notes: 'Automatisch per Flugtimer gespeichert.',
          ),
        );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Flug mit ${aircraft.name} gespeichert: $durationMinutes min.',
        ),
      ),
    );
  }
}

class _AircraftInventoryList extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final int totalAircraftCount;
  final String? selectedId;
  final String? selectedCategory;
  final ValueChanged<String> onSelected;

  const _AircraftInventoryList({
    required this.aircraft,
    required this.totalAircraftCount,
    required this.selectedId,
    required this.selectedCategory,
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
                  selectedCategory == null
                      ? '$totalAircraftCount'
                      : '${aircraft.length}/$totalAircraftCount',
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
              child: aircraft.isEmpty
                  ? _EmptyCategorySelection(category: selectedCategory)
                  : ListView.separated(
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

class _CategoryFilterPanel extends StatelessWidget {
  final String? selectedCategory;
  final ValueChanged<String?> onSelected;

  const _CategoryFilterPanel({
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
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
              const Icon(
                Icons.category_rounded,
                color: Color(0xFF0A84FF),
                size: 17,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Kategorien zur Auswahl',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selectedCategory != null)
                TextButton(
                  onPressed: () => onSelected(null),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Alle'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: aircraftCategoryOptions.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == aircraftCategoryOptions.length) {
                  return _RepairFilterButton(
                    selected: _isRepairFilter(selectedCategory),
                    onTap: () => onSelected(_repairFilterKey),
                  );
                }
                final category = aircraftCategoryOptions[index];
                return _CategoryFilterButton(
                  category: category,
                  selected: category == selectedCategory,
                  onTap: () => onSelected(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RepairFilterButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _RepairFilterButton({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Reparatur',
      child: Material(
        color: selected ? const Color(0xFFFFEDD5) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xFFEA580C)
                    : const Color(0xFFE2E8F0),
                width: selected ? 2 : 1,
              ),
            ),
            child: const Center(
              child: SizedBox.square(
                dimension: 60,
                child: Icon(
                  Icons.build_circle_rounded,
                  color: Color(0xFFEA580C),
                  size: 54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterButton extends StatelessWidget {
  final String category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryFilterButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: category,
      child: Material(
        color: selected ? const Color(0xFFE0F2FE) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFFE2E8F0),
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: _ModelCategoryIcon(category: category),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelCategoryIcon extends StatelessWidget {
  final String category;

  const _ModelCategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final asset = _modelCategoryIconAsset(category);
    if (asset != null) {
      return Image.asset(
        asset,
        width: 60,
        height: 60,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      );
    }

    return Icon(
      _modelCategoryFallbackIcon(category),
      color: const Color(0xFF0A84FF),
      size: 42,
    );
  }
}

class _EmptyCategorySelection extends StatelessWidget {
  final String? category;

  const _EmptyCategorySelection({required this.category});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          category == null
              ? 'Noch keine Modelle vorhanden.'
              : _isRepairFilter(category)
                  ? 'Keine reparaturbeduerftigen Modelle.'
                  : 'Keine Modelle in dieser Kategorie.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _NoModelsInCategory extends StatelessWidget {
  final String? category;

  const _NoModelsInCategory({required this.category});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isRepairFilter(category))
                const Icon(
                  Icons.build_circle_rounded,
                  color: Color(0xFFEA580C),
                  size: 60,
                )
              else if (category != null)
                _ModelCategoryIcon(category: category!),
              const SizedBox(height: 16),
              Text(
                category == null
                    ? 'Kein Modell ausgewaehlt.'
                    : _isRepairFilter(category)
                        ? 'Keine reparaturbeduerftigen Modelle vorhanden.'
                        : 'Keine Modelle in $category vorhanden.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 16,
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
  final List<BatteryPack> batteries;
  final ValueChanged<AircraftStatus> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStartFlight;

  const _AircraftDetails({
    required this.aircraft,
    required this.batteries,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onStartFlight,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy');
    final assignedBatteries = batteries
        .where((battery) => battery.aircraftIds.contains(aircraft.id))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

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
                    _AircraftPhotoCarousel(aircraft: aircraft),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: 20,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                height: 36,
                child: FilledButton.icon(
                  onPressed: onStartFlight,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                  label: const Text('Flug starten'),
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
                  if (aircraft.status == AircraftStatus.maintenance) ...[
                    _InfoPanel(
                      title: 'Reparatur',
                      icon: Icons.build_circle_rounded,
                      iconColor: const Color(0xFFEA580C),
                      children: [
                        Text(
                          _repairInfo(aircraft),
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  _InfoPanel(
                    title: 'Fliegt am besten mit folgenden Akkus...',
                    icon: Icons.battery_charging_full_rounded,
                    iconColor: const Color(0xFF16A34A),
                    children: [
                      _BestBatteryList(batteries: assignedBatteries),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _InfoPanel(
                    title: 'Notizen',
                    icon: Icons.notes_rounded,
                    children: [
                      Text(
                        aircraft.notes,
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

String _repairInfo(AircraftModel aircraft) {
  if (aircraft.repairNotes.trim().isNotEmpty) {
    return aircraft.repairNotes.trim();
  }
  final trimmed = aircraft.notes.trim();
  if (trimmed.startsWith('Reparatur:')) {
    final firstLine = trimmed.split('\n').first;
    return firstLine.replaceFirst('Reparatur:', '').trim();
  }
  return 'Noch keine Reparaturhinweise hinterlegt.';
}

class _BestBatteryList extends StatelessWidget {
  final List<BatteryPack> batteries;

  const _BestBatteryList({required this.batteries});

  @override
  Widget build(BuildContext context) {
    if (batteries.isEmpty) {
      return const Text(
        'Noch keine Akkus fuer dieses Modell ausgewaehlt.',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final battery in batteries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 7, right: 9),
                  decoration: BoxDecoration(
                    color: _batteryStatusColor(battery.status),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    _batteryDescription(battery),
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _batteryDescription(BatteryPack battery) {
    final manufacturer = battery.manufacturer.trim();
    final name = [
      if (manufacturer.isNotEmpty) manufacturer,
      battery.label,
    ].join(' ');
    return '$name - ${battery.chemistry} ${battery.cells}S, '
        '${battery.capacityMah} mAh, ${battery.cRate}C, '
        '${battery.status.label}';
  }

  Color _batteryStatusColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.charged => const Color(0xFF16A34A),
      BatteryStatus.storage => const Color(0xFF0A84FF),
      BatteryStatus.discharged => const Color(0xFFEAB308),
      BatteryStatus.service => const Color(0xFFEF4444),
    };
  }
}

class _AircraftPhoto extends StatelessWidget {
  final AircraftModel aircraft;
  final double? width;
  final double? height;

  const _AircraftPhoto({
    required this.aircraft,
    this.width,
    this.height,
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
                fit: BoxFit.cover,
                alignment: _photoAlignment(aircraft),
                filterQuality: FilterQuality.high,
              )
            : Image.memory(
                _bytesFromDataUri(photoDataUri),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  'assets/splash/landing_page.png',
                  fit: BoxFit.cover,
                  alignment: _photoAlignment(aircraft),
                  filterQuality: FilterQuality.high,
                ),
              ),
      ),
    );
  }
}

class _AircraftPhotoCarousel extends StatefulWidget {
  final AircraftModel aircraft;

  const _AircraftPhotoCarousel({required this.aircraft});

  @override
  State<_AircraftPhotoCarousel> createState() => _AircraftPhotoCarouselState();
}

class _AircraftPhotoCarouselState extends State<_AircraftPhotoCarousel> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _AircraftPhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aircraft.id != widget.aircraft.id) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.aircraft.photos;
    final hasMultiplePhotos = photos.length > 1;
    final safeIndex = photos.isEmpty ? 0 : _index.clamp(0, photos.length - 1);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (photos.isEmpty)
          Image.asset(
            'assets/splash/landing_page.png',
            fit: BoxFit.cover,
            alignment: _photoAlignment(widget.aircraft),
            filterQuality: FilterQuality.high,
          )
        else
          Image.memory(
            _bytesFromDataUri(photos[safeIndex]),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        if (hasMultiplePhotos) ...[
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: _PhotoArrowButton(
              icon: Icons.chevron_left_rounded,
              onTap: () => setState(
                () => _index = (_index - 1 + photos.length) % photos.length,
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: _PhotoArrowButton(
              icon: Icons.chevron_right_rounded,
              onTap: () =>
                  setState(() => _index = (_index + 1) % photos.length),
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PhotoArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class _FlightTimerResult {
  final DateTime startedAt;
  final Duration elapsed;
  final String location;

  const _FlightTimerResult({
    required this.startedAt,
    required this.elapsed,
    required this.location,
  });
}

class _FlightTimerDialog extends StatefulWidget {
  final AircraftModel aircraft;
  final String homeAirfield;
  final List<String> flightAreas;

  const _FlightTimerDialog({
    required this.aircraft,
    required this.homeAirfield,
    required this.flightAreas,
  });

  @override
  State<_FlightTimerDialog> createState() => _FlightTimerDialogState();
}

class _FlightTimerDialogState extends State<_FlightTimerDialog> {
  static const double _panelWidth = 640;
  static const double _panelHeight = 871;

  DateTime? _startedAt;
  DateTime? _lastTickAt;
  Duration _elapsed = Duration.zero;
  final ValueNotifier<Duration> _elapsedNotifier = ValueNotifier(Duration.zero);
  final TextEditingController _customLocationController =
      TextEditingController();
  String? _selectedHomeLocation;
  Timer? _timer;
  bool _paused = false;
  bool _customLocation = false;

  String get _selectedLocation {
    final home = _selectedHomeLocation?.trim() ?? widget.homeAirfield.trim();
    if (_customLocation) {
      final custom = _customLocationController.text.trim();
      return custom.isEmpty
          ? (home.isEmpty ? 'Eigener Startplatz' : home)
          : custom;
    }
    return home.isEmpty ? 'Heimatflugplatz' : home;
  }

  @override
  void initState() {
    super.initState();
    _selectedHomeLocation = _availableHomeLocations.first;
    _customLocationController.addListener(_syncCustomLocationPreview);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsedNotifier.dispose();
    _customLocationController.removeListener(_syncCustomLocationPreview);
    _customLocationController.dispose();
    super.dispose();
  }

  void _syncCustomLocationPreview() {
    if (mounted && _customLocation) {
      setState(() {});
    }
  }

  List<String> get _availableHomeLocations {
    final values = <String>[
      widget.homeAirfield.trim(),
      for (final area in widget.flightAreas) area.trim(),
    ].where((area) => area.isNotEmpty).toSet().toList();
    return values.isEmpty ? ['Heimatflugplatz'] : values;
  }

  @override
  Widget build(BuildContext context) {
    final photoDataUri =
        widget.aircraft.photos.isEmpty ? null : widget.aircraft.photos.first;
    final running = _startedAt != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = MediaQuery.sizeOf(context);
          final constraintWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : double.infinity;
          final constraintHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;
          final availableWidth = math.min(constraintWidth, viewport.width - 36);
          final availableHeight =
              math.min(constraintHeight, viewport.height - 24);
          final scale = math
              .min(
                math.min(math.max(280.0, availableWidth), _panelWidth) /
                    _panelWidth,
                math.min(math.max(420.0, availableHeight), _panelHeight) /
                    _panelHeight,
              )
              .toDouble();

          return SizedBox(
            width: _panelWidth * scale,
            height: _panelHeight * scale,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: _panelWidth,
                height: _panelHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/widgets/timer_bg.jpg',
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 30,
                      top: 123,
                      width: 329,
                      height: 183,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: photoDataUri == null
                            ? Image.asset(
                                'assets/splash/landing_page.png',
                                fit: BoxFit.cover,
                                alignment: _photoAlignment(widget.aircraft),
                                filterQuality: FilterQuality.high,
                              )
                            : Image.memory(
                                _bytesFromDataUri(photoDataUri),
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                    if (!running)
                      Positioned(
                        right: 28,
                        top: 18,
                        child: IconButton(
                          tooltip: 'Schliessen',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFFF4F1DE),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.26),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 55,
                      top: 537,
                      width: 88,
                      height: 88,
                      child: _PanelStatusLight(active: running && !_paused),
                    ),
                    Positioned(
                      left: 187,
                      top: 436,
                      width: 277,
                      height: 277,
                      child: _CockpitTimerGauge(
                        elapsedListenable: _elapsedNotifier,
                        running: running && !_paused,
                        paused: _paused,
                      ),
                    ),
                    Positioned(
                      left: 42,
                      top: 361,
                      width: 102,
                      height: 44,
                      child: _CockpitButton(
                        label: 'Reset',
                        icon: Icons.restart_alt_rounded,
                        onPressed: _resetTimer,
                        accent: const Color(0xFF93C5FD),
                      ),
                    ),
                    Positioned(
                      left: 201,
                      top: 361,
                      width: 102,
                      height: 44,
                      child: _CockpitButton(
                        label: 'Verwerfen',
                        icon: Icons.delete_outline_rounded,
                        onPressed: _discardFlight,
                        accent: const Color(0xFFFCA5A5),
                        compact: true,
                      ),
                    ),
                    Positioned(
                      left: 351,
                      top: 361,
                      width: 102,
                      height: 44,
                      child: _CockpitButton(
                        label: 'Start',
                        icon: Icons.play_arrow_rounded,
                        onPressed: running ? null : _startTimer,
                        accent: const Color(0xFF38BDF8),
                      ),
                    ),
                    Positioned(
                      left: 508,
                      top: 361,
                      width: 102,
                      height: 44,
                      child: _CockpitButton(
                        label: _paused ? 'Weiter' : 'Pause',
                        icon: _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        onPressed: running ? _togglePause : null,
                        accent: const Color(0xFFFACC15),
                      ),
                    ),
                    Positioned(
                      left: 508,
                      top: 461,
                      width: 102,
                      height: 44,
                      child: _CockpitButton(
                        label: 'Beenden',
                        icon: Icons.stop_rounded,
                        onPressed: running ? _finishFlight : null,
                        accent: const Color(0xFF22C55E),
                        compact: true,
                      ),
                    ),
                    Positioned(
                      left: 86,
                      top: 758,
                      width: 470,
                      child: _FlightLocationSelector(
                        homeAirfield: widget.homeAirfield,
                        flightAreas: _availableHomeLocations,
                        selectedHomeLocation: _selectedHomeLocation ??
                            _availableHomeLocations.first,
                        customLocation: _customLocation,
                        controller: _customLocationController,
                        onHomeLocationChanged: (location) =>
                            setState(() => _selectedHomeLocation = location),
                        onModeChanged: (custom) =>
                            setState(() => _customLocation = custom),
                      ),
                    ),
                    Positioned(
                      left: 376,
                      top: 132,
                      width: 222,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.aircraft.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF4F1DE),
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1.02,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.aircraft.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD6B98C),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${widget.aircraft.registration}\n${widget.aircraft.flightHours.toStringAsFixed(1)} h gesamt',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFF4F1DE)
                                  .withValues(alpha: 0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    final now = DateTime.now();
    setState(() {
      _startedAt = now;
      _lastTickAt = now;
      _paused = false;
      _elapsed = Duration.zero;
      _elapsedNotifier.value = _elapsed;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || _paused) {
        return;
      }
      final now = DateTime.now();
      final previous = _lastTickAt ?? now;
      _elapsed += now.difference(previous);
      _lastTickAt = now;
      _elapsedNotifier.value = _elapsed;
    });
  }

  void _resetTimer() {
    final now = DateTime.now();
    setState(() {
      _elapsed = Duration.zero;
      _elapsedNotifier.value = _elapsed;
      if (_startedAt != null) {
        _startedAt = now;
        _lastTickAt = now;
      }
    });
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        _lastTickAt = DateTime.now();
        _paused = false;
      } else {
        _paused = true;
      }
    });
  }

  void _finishFlight() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }

    Navigator.of(context).pop(
      _FlightTimerResult(
        startedAt: startedAt,
        elapsed: _elapsed,
        location: _selectedLocation,
      ),
    );
  }

  void _discardFlight() {
    Navigator.of(context).pop();
  }
}

class _FlightLocationSelector extends StatelessWidget {
  final String homeAirfield;
  final List<String> flightAreas;
  final String selectedHomeLocation;
  final bool customLocation;
  final TextEditingController controller;
  final ValueChanged<String> onHomeLocationChanged;
  final ValueChanged<bool> onModeChanged;

  const _FlightLocationSelector({
    required this.homeAirfield,
    required this.flightAreas,
    required this.selectedHomeLocation,
    required this.customLocation,
    required this.controller,
    required this.onHomeLocationChanged,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final homeOptions = flightAreas.isEmpty
        ? [
            homeAirfield.trim().isEmpty
                ? 'Heimatflugplatz'
                : homeAirfield.trim(),
          ]
        : flightAreas;
    final selectedHome = homeOptions.contains(selectedHomeLocation)
        ? selectedHomeLocation
        : homeOptions.first;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD6B98C).withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StartPlaceOptionField(
              selected: !customLocation,
              label: 'Heimatflugplatz',
              value: selectedHome,
              options: homeOptions,
              onOptionChanged: onHomeLocationChanged,
              readOnly: true,
              onSelected: () => onModeChanged(false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StartPlaceOptionField(
              selected: customLocation,
              label: 'Anderer Startplatz',
              value: null,
              controller: controller,
              readOnly: false,
              onSelected: () => onModeChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartPlaceOptionField extends StatelessWidget {
  final bool selected;
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String>? onOptionChanged;
  final TextEditingController? controller;
  final bool readOnly;
  final VoidCallback onSelected;

  const _StartPlaceOptionField({
    required this.selected,
    required this.label,
    required this.value,
    this.options = const [],
    this.onOptionChanged,
    this.controller,
    required this.readOnly,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const fillColor = Color(0xFF0D0C0A);
    const textColor = Color(0xFFF4F1DE);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1E1A14)
              : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF22C55E).withValues(alpha: 0.82)
                : const Color(0xFFD6B98C).withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF8A7A63),
                  width: 2,
                ),
                color: selected
                    ? const Color(0xFF16A34A)
                    : Colors.black.withValues(alpha: 0.25),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFF22C55E).withValues(alpha: 0.58),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFEFFFEF),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: readOnly && options.isNotEmpty
                  ? DropdownButtonFormField<String>(
                      initialValue:
                          options.contains(value) ? value : options.first,
                      items: [
                        for (final option in options)
                          DropdownMenuItem(
                            value: option,
                            child: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: selected
                          ? (location) {
                              if (location != null) {
                                onOptionChanged?.call(location);
                              }
                            }
                          : null,
                      decoration: _startPlaceDecoration(
                        label: label,
                        hint: value,
                        fillColor: fillColor,
                        textColor: textColor,
                      ),
                      dropdownColor: const Color(0xFF16120E),
                      style: const TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    )
                  : TextField(
                      controller: controller,
                      readOnly: readOnly,
                      enabled: selected || readOnly,
                      onTap: onSelected,
                      style: const TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                      decoration: _startPlaceDecoration(
                        label: label,
                        hint: readOnly ? value : 'Startplatz eintragen',
                        fillColor: fillColor,
                        textColor: textColor,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _startPlaceDecoration({
  required String label,
  required String? hint,
  required Color fillColor,
  required Color textColor,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      color: Color(0xFFE6D3B1),
      fontSize: 12,
      fontWeight: FontWeight.w900,
    ),
    hintText: hint,
    hintStyle: TextStyle(
      color: textColor.withValues(alpha: 0.92),
      fontWeight: FontWeight.w800,
    ),
    isDense: true,
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 10,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: const Color(0xFFD6B98C).withValues(alpha: 0.18),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: const Color(0xFFD6B98C).withValues(alpha: 0.18),
      ),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: const Color(0xFFD6B98C).withValues(alpha: 0.18),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE6D3B1)),
    ),
  );
}

class _CockpitTimerGauge extends StatelessWidget {
  final ValueListenable<Duration> elapsedListenable;
  final bool running;
  final bool paused;

  const _CockpitTimerGauge({
    required this.elapsedListenable,
    required this.running,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(
        const Duration(milliseconds: 33),
        (tick) => tick,
      ),
      builder: (context, snapshot) {
        return CustomPaint(
          painter: _CockpitTimerGaugePainter(
            elapsed: elapsedListenable.value,
            localTime: DateTime.now(),
            running: running,
            paused: paused,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

String _formatCockpitElapsed(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

class _PanelStatusLight extends StatefulWidget {
  final bool active;

  const _PanelStatusLight({required this.active});

  @override
  State<_PanelStatusLight> createState() => _PanelStatusLightState();
}

class _PanelStatusLightState extends State<_PanelStatusLight> {
  Timer? _blinkTimer;
  bool _bright = true;

  @override
  void initState() {
    super.initState();
    _syncBlinkTimer();
  }

  @override
  void didUpdateWidget(covariant _PanelStatusLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncBlinkTimer();
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _syncBlinkTimer() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _bright = true;
    if (!widget.active) {
      return;
    }
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
      if (mounted) {
        setState(() => _bright = !_bright);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.active ? const Color(0xFF22C55E) : const Color(0xFF14532D);
    final opacity = widget.active && !_bright ? 0.38 : 1.0;

    return Center(
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.active
                    ? const Color(0xFFE5FFE9)
                    : const Color(0xFF4ADE80).withValues(alpha: 0.46),
                color,
                Colors.transparent,
              ],
            ),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.9),
                      blurRadius: 24,
                      spreadRadius: 7,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class _CockpitButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color accent;
  final bool compact;

  const _CockpitButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF090807),
            Color(0xFF342A21),
            Color(0xFF050505),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFD6B98C).withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.60),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: const Color(0xFFC46D3C).withValues(alpha: 0.12),
            blurRadius: 5,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: enabled
                    ? [
                        const Color(0xFF181512),
                        const Color(0xFF2B241D),
                        const Color(0xFF070707),
                      ]
                    : [
                        const Color(0xFF11100E),
                        const Color(0xFF080807),
                      ],
              ),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: 0.58)
                    : const Color(0xFF2A2722),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.70),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                  spreadRadius: -1,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.02),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled ? accent : const Color(0xFF64748B),
                  size: compact ? 14 : 17,
                ),
                SizedBox(width: compact ? 5 : 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF64748B),
                      fontSize: compact ? 10.5 : 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CockpitTimerGaugePainter extends CustomPainter {
  final Duration elapsed;
  final DateTime localTime;
  final bool running;
  final bool paused;

  const _CockpitTimerGaugePainter({
    required this.elapsed,
    required this.localTime,
    required this.running,
    required this.paused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 7);
    final radius = size.shortestSide / 2;
    final faceRadius = radius * 0.71;

    final seconds = localTime.second + localTime.millisecond / 1000;
    final minutes = localTime.minute + seconds / 60;
    final hours = localTime.hour.remainder(12) + minutes / 60;
    final secondsAngle = -math.pi / 2 + seconds / 60 * math.pi * 2;
    final minutesAngle = -math.pi / 2 + minutes / 60 * math.pi * 2;
    final hoursAngle = -math.pi / 2 + hours / 12 * math.pi * 2;

    _drawStilettoHand(
      canvas,
      center,
      angle: hoursAngle,
      length: faceRadius * 0.52,
      width: 9.4,
      color: const Color(0xFFF4F1DE),
      shadowColor: Colors.black.withValues(alpha: 0.74),
      tailLength: 9,
    );
    _drawStilettoHand(
      canvas,
      center,
      angle: minutesAngle,
      length: faceRadius * 0.86,
      width: 6.5,
      color: const Color(0xFFF4F1DE),
      shadowColor: Colors.black.withValues(alpha: 0.74),
      tailLength: 10,
    );
    _drawNeedleHand(
      canvas,
      center,
      angle: secondsAngle,
      length: faceRadius * 0.93,
      color: const Color(0xFFF4F1DE),
      tailLength: 28,
    );

    final hubPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF333333), Color(0xFF111111), Color(0xFF050505)],
      ).createShader(Rect.fromCircle(center: center, radius: 14));
    canvas.drawCircle(center, 14, hubPaint);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF4F1DE).withValues(alpha: 0.18),
    );
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF0A0A0A));

    final timerEngaged = running || paused;
    final elapsedBox = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, size.height - 9),
        width: 194,
        height: 42,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      elapsedBox,
      Paint()
        ..color = Colors.black.withValues(alpha: timerEngaged ? 0.84 : 0.34),
    );
    canvas.drawRRect(
      elapsedBox,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color =
            (timerEngaged ? const Color(0xFFEF4444) : const Color(0xFFF4F1DE))
                .withValues(alpha: timerEngaged ? 0.42 : 0.08),
    );
    _drawGaugeText(
      canvas,
      _formatCockpitElapsed(elapsed),
      Offset(center.dx, size.height - 9),
      fontSize: 22,
      color: timerEngaged
          ? const Color(0xFFFF3B30)
          : const Color(0xFFF4F1DE).withValues(alpha: 0.36),
      fontWeight: FontWeight.w900,
    );
  }

  @override
  bool shouldRepaint(covariant _CockpitTimerGaugePainter oldDelegate) {
    return oldDelegate.elapsed != elapsed ||
        oldDelegate.localTime.millisecond != localTime.millisecond ||
        oldDelegate.localTime.second != localTime.second ||
        oldDelegate.running != running ||
        oldDelegate.paused != paused;
  }
}

void _drawGaugeText(
  Canvas canvas,
  String text,
  Offset center, {
  required double fontSize,
  required Color color,
  FontWeight fontWeight = FontWeight.w900,
  double letterSpacing = 0,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontFamily: 'Bahnschrift',
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();

  painter.paint(
    canvas,
    Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
  );
}

void _drawStilettoHand(
  Canvas canvas,
  Offset center, {
  required double angle,
  required double length,
  required double width,
  required Color color,
  required Color shadowColor,
  required double tailLength,
}) {
  final direction = Offset(math.cos(angle), math.sin(angle));
  final normal = Offset(-direction.dy, direction.dx);
  final tip = center + direction * length;
  final tail = center - direction * tailLength;
  final shoulder = center + direction * 14;
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      shoulder.dx + normal.dx * width,
      shoulder.dy + normal.dy * width,
    )
    ..lineTo(center.dx + normal.dx * (width * 0.48),
        center.dy + normal.dy * (width * 0.48))
    ..lineTo(tail.dx, tail.dy)
    ..lineTo(center.dx - normal.dx * (width * 0.48),
        center.dy - normal.dy * (width * 0.48))
    ..lineTo(
      shoulder.dx - normal.dx * width,
      shoulder.dy - normal.dy * width,
    )
    ..close();

  canvas.drawShadow(path, shadowColor, 4, false);
  canvas.drawPath(path, Paint()..color = color);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF0A0A0A).withValues(alpha: 0.46),
  );
}

void _drawNeedleHand(
  Canvas canvas,
  Offset center, {
  required double angle,
  required double length,
  required Color color,
  required double tailLength,
}) {
  final direction = Offset(math.cos(angle), math.sin(angle));
  final tip = center + direction * length;
  final tail = center - direction * tailLength;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round;

  canvas.drawLine(tail, tip, paint);
  canvas.drawCircle(tip, 2.1, Paint()..color = color);
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
      ('Ausstattung', _aircraftFeaturesLabel(aircraft.featureOptions)),
      ('Hersteller', aircraft.manufacturer),
      ('Spannweite', '${aircraft.wingspanMeters.toStringAsFixed(2)} m'),
      ('Laenge', '${aircraft.lengthMeters.toStringAsFixed(2)} m'),
      ('Gewicht', '${aircraft.weightKg.toStringAsFixed(1)} kg'),
      ('Sender', _fallback(aircraft.transmitter)),
      ('Sender-Speicherplatz', _fallback(aircraft.transmitterMemorySlot)),
      ('Antrieb', _fallback(aircraft.drive)),
      ('Empfaenger', _fallback(aircraft.receiver)),
      ('Propeller', _fallback(aircraft.propeller)),
      ('Material\nRumpf/Flaeche', _fallback(aircraft.materialFuselageWing)),
      ('Tragflaechen-\nbelastung', _fallback(aircraft.wingLoading)),
      ('Servos', _fallback(aircraft.servos)),
      ('Kaufdatum', formatter.format(aircraft.purchaseDate)),
      ('Akku-Typ', _batteryCellsLabel(aircraft.batteryCells)),
      ('Fluege', '${aircraft.totalFlights}'),
      ('Flugzeit', '${aircraft.flightHours.toStringAsFixed(1)} h'),
      ('Status', aircraft.status.label),
    ];

    return _InfoPanel(
      title: 'Modelldaten',
      icon: Icons.fact_check_rounded,
      iconSize: 18,
      iconColor: const Color(0xFF38BDF8),
      framed: false,
      children: [
        Table(
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
      ],
    );
  }

  String _fallback(String value) {
    return value.trim().isEmpty ? '-' : value.trim();
  }
}

String _batteryCellsLabel(List<int> cells) {
  final normalized = {
    for (final cell in cells) cell.clamp(1, 6),
  }.toList()
    ..sort();
  return normalized.map((cell) => '${cell}S').join(', ');
}

String _aircraftFeaturesLabel(List<String> features) {
  if (features.isEmpty) {
    return 'Keine Angabe';
  }
  return features.join(', ');
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
          fontWeight: isLabel ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final bool framed;
  final List<Widget> children;

  const _InfoPanel({
    required this.title,
    required this.icon,
    this.iconSize = 24,
    this.iconColor = const Color(0xFF0A84FF),
    this.framed = true,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: framed ? const EdgeInsets.all(16) : EdgeInsets.zero,
      decoration: framed
          ? BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: iconSize),
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
  final List<String> transmitterOptions;
  final ValueChanged<AircraftModel> onSubmit;

  const _AircraftDialog({
    this.aircraft,
    required this.transmitterOptions,
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
  final _transmitter = TextEditingController();
  final _transmitterMemorySlot = TextEditingController();
  final _receiver = TextEditingController();
  final _propeller = TextEditingController();
  final _materialFuselageWing = TextEditingController();
  final _wingLoading = TextEditingController();
  final _servos = TextEditingController();
  final _purchaseDate = TextEditingController(
    text: DateFormat('dd.MM.yyyy').format(DateTime.now()),
  );
  final _drive = TextEditingController();
  final _notes = TextEditingController();
  final _repairNotes = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<String> _photoDataUris = [];
  AircraftStatus _status = AircraftStatus.ready;
  String _type = _aircraftTypes.first;
  String _selectedTransmitter = '';
  final Set<int> _batteryCells = {2};
  final Set<String> _featureOptions = {};

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
    _transmitter.text = aircraft.transmitter;
    _selectedTransmitter = aircraft.transmitter;
    _transmitterMemorySlot.text = aircraft.transmitterMemorySlot;
    _receiver.text = aircraft.receiver;
    _propeller.text = aircraft.propeller;
    _materialFuselageWing.text = aircraft.materialFuselageWing;
    _wingLoading.text = aircraft.wingLoading;
    _servos.text = aircraft.servos;
    _purchaseDate.text = DateFormat('dd.MM.yyyy').format(aircraft.purchaseDate);
    _drive.text = aircraft.drive;
    _batteryCells
      ..clear()
      ..addAll(aircraft.batteryCells.map((cell) => cell.clamp(1, 6)));
    _featureOptions
      ..clear()
      ..addAll(aircraft.featureOptions);
    _notes.text = aircraft.notes;
    _repairNotes.text = aircraft.repairNotes;
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
    _transmitter.dispose();
    _transmitterMemorySlot.dispose();
    _receiver.dispose();
    _propeller.dispose();
    _materialFuselageWing.dispose();
    _wingLoading.dispose();
    _servos.dispose();
    _purchaseDate.dispose();
    _drive.dispose();
    _notes.dispose();
    _repairNotes.dispose();
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
                    style: _aircraftDialogInputStyle,
                    decoration: const InputDecoration(
                      labelText: 'Kategorie',
                      labelStyle: _aircraftDialogLabelStyle,
                    ),
                    items: [
                      for (final type in _aircraftTypes)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? _type),
                  ),
                ),
                _TextField(controller: _manufacturer, label: 'Hersteller'),
                _TextField(controller: _wingspan, label: 'Spannweite m'),
                _TextField(controller: _length, label: 'Laenge m'),
                _TextField(controller: _weight, label: 'Gewicht kg'),
                _buildTransmitterInput(),
                _TextField(
                  controller: _transmitterMemorySlot,
                  label: 'Sender-Speicherplatz',
                  requiredField: false,
                ),
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
                  controller: _materialFuselageWing,
                  label: 'Material Rumpf/Flaeche',
                  requiredField: false,
                ),
                _TextField(
                  controller: _wingLoading,
                  label: 'Tragflaechenbelastung',
                  requiredField: false,
                ),
                _TextField(
                  controller: _servos,
                  label: 'Servos',
                  requiredField: false,
                ),
                _TextField(
                  controller: _purchaseDate,
                  label: 'Kaufdatum TT.MM.JJJJ',
                ),
                SizedBox(
                  width: 532,
                  child: _BatteryCellsMultiSelect(
                    selectedCells: _batteryCells,
                    onChanged: (cell, selected) {
                      setState(() {
                        if (selected) {
                          _batteryCells.add(cell);
                        } else if (_batteryCells.length > 1) {
                          _batteryCells.remove(cell);
                        }
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 532,
                  child: _AircraftFeaturesMultiSelect(
                    selectedFeatures: _featureOptions,
                    onChanged: (feature, selected) {
                      setState(() {
                        if (selected) {
                          _featureOptions.add(feature);
                        } else {
                          _featureOptions.remove(feature);
                        }
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<AircraftStatus>(
                    initialValue: _status,
                    style: _aircraftDialogInputStyle,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      labelStyle: _aircraftDialogLabelStyle,
                    ),
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
                if (_status == AircraftStatus.maintenance)
                  SizedBox(
                    width: 532,
                    child: TextFormField(
                      controller: _repairNotes,
                      minLines: 2,
                      maxLines: 3,
                      style: _aircraftDialogInputStyle,
                      decoration: const InputDecoration(
                        labelText: 'Was muss repariert werden?',
                        labelStyle: _aircraftDialogLabelStyle,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 532,
                  child: TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    style: _aircraftDialogInputStyle,
                    decoration: const InputDecoration(
                      labelText: 'Notizen',
                      labelStyle: _aircraftDialogLabelStyle,
                    ),
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

  Widget _buildTransmitterInput() {
    final options = _availableTransmitters();
    if (options.isEmpty) {
      return _TextField(
        controller: _transmitter,
        label: 'Sender',
        requiredField: false,
      );
    }

    final value =
        options.contains(_selectedTransmitter) ? _selectedTransmitter : '';

    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        style: _aircraftDialogInputStyle,
        decoration: const InputDecoration(
          labelText: 'Sender',
          labelStyle: _aircraftDialogLabelStyle,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Kein Sender')),
          for (final transmitter in options)
            DropdownMenuItem(value: transmitter, child: Text(transmitter)),
        ],
        onChanged: (value) {
          final selected = value ?? '';
          setState(() {
            _selectedTransmitter = selected;
            _transmitter.text = selected;
          });
        },
      ),
    );
  }

  List<String> _availableTransmitters() {
    final values = <String>{
      for (final transmitter in widget.transmitterOptions)
        if (transmitter.trim().isNotEmpty) transmitter.trim(),
      if (_transmitter.text.trim().isNotEmpty) _transmitter.text.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
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
    final notesText = _notes.text.trim();
    final repairText = _repairNotes.text.trim();
    widget.onSubmit(
      AircraftModel(
        id: existing?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        type: _type,
        manufacturer: _manufacturer.text.trim(),
        registration: existing?.registration ?? '',
        wingspanMeters: double.parse(_wingspan.text.replaceAll(',', '.')),
        lengthMeters: double.parse(_length.text.replaceAll(',', '.')),
        weightKg: double.parse(_weight.text.replaceAll(',', '.')),
        transmitter: _transmitter.text.trim(),
        transmitterMemorySlot: _transmitterMemorySlot.text.trim(),
        receiver: _receiver.text.trim(),
        propeller: _propeller.text.trim(),
        materialFuselageWing: _materialFuselageWing.text.trim(),
        wingLoading: _wingLoading.text.trim(),
        recommendedDriveBattery: existing?.recommendedDriveBattery ?? '',
        servos: _servos.text.trim(),
        purchaseDate: purchaseDate,
        drive: _drive.text.trim(),
        batteryCount: (_batteryCells.toList()..sort()).first,
        batteryCellOptions: List.unmodifiable(_batteryCells.toList()..sort()),
        featureOptions: List.unmodifiable([
          for (final feature in aircraftFeatureOptions)
            if (_featureOptions.contains(feature)) feature,
        ]),
        totalFlights: existing?.totalFlights ?? 0,
        flightHours: existing?.flightHours ?? 0,
        status: _status,
        lastService: existing?.lastService ?? now,
        nextService: existing?.nextService ?? now.add(const Duration(days: 60)),
        notes: notesText.isEmpty ? 'Noch keine Notizen hinterlegt.' : notesText,
        repairNotes: repairText,
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

class _BatteryCellsMultiSelect extends StatelessWidget {
  final Set<int> selectedCells;
  final void Function(int cell, bool selected) onChanged;

  const _BatteryCellsMultiSelect({
    required this.selectedCells,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Akku-Typ',
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var cell = 1; cell <= 6; cell++)
            FilterChip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              label: Text('${cell}S'),
              selected: selectedCells.contains(cell),
              onSelected: (selected) => onChanged(cell, selected),
              selectedColor: const Color(0xFFDCEEFF),
              checkmarkColor: const Color(0xFF0A84FF),
              labelStyle: TextStyle(
                color: selectedCells.contains(cell)
                    ? const Color(0xFF075985)
                    : const Color(0xFF334155),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _AircraftFeaturesMultiSelect extends StatelessWidget {
  final Set<String> selectedFeatures;
  final void Function(String feature, bool selected) onChanged;

  const _AircraftFeaturesMultiSelect({
    required this.selectedFeatures,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Ausstattung',
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final feature in aircraftFeatureOptions)
            FilterChip(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              label: Text(feature),
              selected: selectedFeatures.contains(feature),
              onSelected: (selected) => onChanged(feature, selected),
              selectedColor: const Color(0xFFDCEEFF),
              checkmarkColor: const Color(0xFF0A84FF),
              labelStyle: TextStyle(
                color: selectedFeatures.contains(feature)
                    ? const Color(0xFF075985)
                    : const Color(0xFF334155),
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
        style: _aircraftDialogInputStyle,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: _aircraftDialogLabelStyle,
        ),
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

const _aircraftDialogInputStyle = TextStyle(
  color: Color(0xFF06172E),
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

const _aircraftDialogLabelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

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

const _aircraftTypes = aircraftCategoryOptions;

String _normalizeAircraftType(String value) {
  return normalizeAircraftCategory(value);
}

bool _isRepairFilter(String? value) {
  return value == _repairFilterKey;
}

String? _modelCategoryIconAsset(String category) {
  final value = category.toLowerCase();
  if (value.contains('drohne') ||
      value.contains('drone') ||
      value.contains('multi') ||
      value.contains('quad')) {
    return 'assets/icons/drohne_60.png';
  }
  if (value.contains('hubschrauber') || value.contains('heli')) {
    return 'assets/icons/hubschrauber_60.png';
  }
  if (value.contains('jet')) {
    return 'assets/icons/jet_60.png';
  }
  if (value.contains('kunst')) {
    return 'assets/icons/kunstflug_60.png';
  }
  if (value.contains('paragleiter') || value.contains('para')) {
    return 'assets/icons/paragleiter_60.png';
  }
  if (value.contains('scale')) {
    return 'assets/icons/scale_60.png';
  }
  if (value.contains('segler') || value.contains('segelflug')) {
    return 'assets/icons/segler_60.png';
  }
  if (value.contains('slowflyer')) {
    return 'assets/icons/slowflyer_60.png';
  }
  if (value.contains('sonstige')) {
    return 'assets/icons/sonstige_60.png';
  }
  return null;
}

IconData _modelCategoryFallbackIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('nurfl')) {
    return Icons.change_history_rounded;
  }
  if (value.contains('trainer')) {
    return Icons.school_rounded;
  }
  return Icons.airplanemode_active_rounded;
}

Alignment _photoAlignment(AircraftModel aircraft) {
  final id = aircraft.id.toLowerCase();
  final type = aircraft.type.toLowerCase();

  if (id.contains('quad') || type.contains('multi')) {
    return const Alignment(0.88, -0.30);
  }
  if (id.contains('asw') ||
      type.contains('segler') ||
      type.contains('segelflug')) {
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
