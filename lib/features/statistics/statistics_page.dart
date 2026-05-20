import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);
    final flightsThisMonth = _flightsInCurrentMonth(fleet.flights);
    final flightsPreviousMonth = _flightsInPreviousMonth(fleet.flights);
    final hoursThisMonth = _totalHours(flightsThisMonth);
    final hoursPreviousMonth = _totalHours(flightsPreviousMonth);
    final aircraftById = {
      for (final aircraft in fleet.aircraft) aircraft.id: aircraft,
    };
    final longestFlight = _longestFlight(fleet.flights);
    final longestFlightAircraft =
        longestFlight == null ? null : aircraftById[longestFlight.aircraftId];

    return AppScaffold(
      title: 'Statistiken',
      subtitle: 'Flugstunden, Starts und Einsatzbereitschaft auswerten.',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatTile(
              icon: Icons.flight_takeoff_rounded,
              label: 'Anzahl der Fluege',
              value: '${fleet.totalFlights}',
              helper: _percentChangeText(
                flightsThisMonth.length.toDouble(),
                flightsPreviousMonth.length.toDouble(),
              ),
            ),
            _StatTile(
              icon: Icons.timer_rounded,
              label: 'Gesamtflugzeit',
              value: fleet.totalHours.toStringAsFixed(1),
              helper: _percentChangeText(hoursThisMonth, hoursPreviousMonth),
            ),
            _StatTile(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Laengster Flug',
              value: longestFlight == null
                  ? '-'
                  : '${longestFlight.durationMinutes} min',
              helper: longestFlightAircraft?.name ?? 'Noch keine Fluege',
            ),
            _StatTile(
              icon: Icons.airplanemode_active_rounded,
              label: 'Vorhandene Modelle',
              value: '${fleet.aircraft.length}',
              helper: '${fleet.readyCount} einsatzfaehig',
            ),
            _StatTile(
              icon: Icons.battery_charging_full_rounded,
              label: 'Vorhandene Akkus',
              value: '${fleet.batteries.length}',
              helper: '${fleet.chargedBatteryCount} top',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _AircraftHoursChart(fleet: fleet),
            _TopModelsTable(
              aircraft: fleet.aircraft,
              flights: fleet.flights,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _FlightTimeBars(flights: fleet.flights),
        const SizedBox(height: 10),
        _CategoryUsageStats(
          aircraft: fleet.aircraft,
          flights: fleet.flights,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String helper;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 168, maxWidth: 218),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF0A84FF), size: 32),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: _numberTextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        helper,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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

class _AircraftHoursChart extends StatelessWidget {
  final FleetState fleet;

  const _AircraftHoursChart({required this.fleet});

  @override
  Widget build(BuildContext context) {
    final aircraftWithHours = [
      for (final aircraft in fleet.aircraft)
        if (aircraft.flightHours > 0) aircraft,
    ];
    final totalHours = aircraftWithHours.fold<double>(
      0,
      (sum, aircraft) => sum + aircraft.flightHours,
    );

    return SizedBox(
      width: 500,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Flugstunden je Modell',
                style: _sectionTitleStyle,
              ),
              const SizedBox(height: 22),
              if (aircraftWithHours.isEmpty)
                const Text(
                  'Noch keine Flugstunden vorhanden.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 188,
                      height: 188,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              centerSpaceRadius: 66,
                              sectionsSpace: 3,
                              sections: [
                                for (var i = 0;
                                    i < aircraftWithHours.length;
                                    i++)
                                  PieChartSectionData(
                                    value: aircraftWithHours[i].flightHours,
                                    color: _aircraftChartColor(i),
                                    title: '',
                                    radius: 44,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                totalHours.toStringAsFixed(1),
                                style: _numberTextStyle(
                                  color: const Color(0xFF06172E),
                                  fontSize: 23,
                                ),
                              ),
                              const Text(
                                'Flugstunden',
                                style: TextStyle(
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
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 236,
                      child: _AircraftHoursLegend(
                        aircraft: aircraftWithHours,
                        totalHours: totalHours,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AircraftHoursLegend extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final double totalHours;

  const _AircraftHoursLegend({
    required this.aircraft,
    required this.totalHours,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        for (var i = 0; i < aircraft.length; i++)
          _AircraftHoursLegendItem(
            color: _aircraftChartColor(i),
            name: aircraft[i].name,
            hours: aircraft[i].flightHours,
            percent: totalHours == 0
                ? 0
                : aircraft[i].flightHours / totalHours * 100,
          ),
      ],
    );
  }
}

class _AircraftHoursLegendItem extends StatelessWidget {
  final Color color;
  final String name;
  final double hours;
  final double percent;

  const _AircraftHoursLegendItem({
    required this.color,
    required this.name,
    required this.hours,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 176,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF06172E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${hours.toStringAsFixed(1)} h (${percent.toStringAsFixed(0)}%)',
            style: _numberTextStyle(
              color: const Color(0xFF475569),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum _FlightTimeRange {
  day('Tag'),
  week('Woche'),
  month('Monat'),
  year('Jahr');

  final String label;

  const _FlightTimeRange(this.label);
}

class _FlightTimeBars extends StatefulWidget {
  final List<FlightLogEntry> flights;

  const _FlightTimeBars({required this.flights});

  @override
  State<_FlightTimeBars> createState() => _FlightTimeBarsState();
}

class _FlightTimeBarsState extends State<_FlightTimeBars> {
  _FlightTimeRange _range = _FlightTimeRange.month;

  @override
  Widget build(BuildContext context) {
    final data = _buildFlightTimeData(widget.flights, _range);
    final maxHours = data.fold<double>(
      0,
      (max, item) => item.hours > max ? item.hours : max,
    );

    return SizedBox(
      width: 900,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.bar_chart_rounded,
                          color: Color(0xFF0A84FF),
                          size: 26,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Gesamt-Flugzeit (Stunden)',
                          style: _sectionTitleStyle,
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final range in _FlightTimeRange.values)
                        ChoiceChip(
                          label: Text(range.label),
                          selected: _range == range,
                          onSelected: (_) => setState(() => _range = range),
                          labelStyle: TextStyle(
                            color: _range == range
                                ? Colors.white
                                : const Color(0xFF334155),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                          selectedColor: const Color(0xFF0A84FF),
                          backgroundColor: const Color(0xFFE8EDF3),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 292,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FlightTimeAreaPainter(
                          points: data,
                          maxHours: maxHours <= 0 ? 1 : maxHours * 1.35,
                        ),
                      ),
                    ),
                    BarChart(
                      BarChartData(
                        maxY: maxHours <= 0 ? 1 : maxHours * 1.35,
                        barTouchData: BarTouchData(
                          enabled: false,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => Colors.transparent,
                            tooltipPadding: EdgeInsets.zero,
                            tooltipMargin: 4,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                '${rod.toY.toStringAsFixed(1)} h',
                                _numberTextStyle(
                                  color: const Color(0xFF06172E),
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: _chartInterval(maxHours),
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
                            axisNameSize: 24,
                            axisNameWidget: const Text(
                              'Stunden',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 48,
                              interval: _chartInterval(maxHours),
                              getTitlesWidget: (value, meta) => Text(
                                value.toStringAsFixed(value < 10 ? 1 : 0),
                                style: _numberTextStyle(
                                  color: const Color(0xFF64748B),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            axisNameSize: 28,
                            axisNameWidget: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _range.label,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 62,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= data.length) {
                                  return const SizedBox.shrink();
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    data[index].label,
                                    textAlign: TextAlign.center,
                                    style: _numberTextStyle(
                                      color: const Color(0xFF64748B),
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < data.length; i++)
                            BarChartGroupData(
                              x: i,
                              showingTooltipIndicators: const [0],
                              barRods: [
                                BarChartRodData(
                                  toY: data[i].hours,
                                  width: 22,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlightTimePoint {
  final String label;
  final double hours;

  const _FlightTimePoint({
    required this.label,
    required this.hours,
  });
}

class _FlightTimeAreaPainter extends CustomPainter {
  final List<_FlightTimePoint> points;
  final double maxHours;

  const _FlightTimeAreaPainter({
    required this.points,
    required this.maxHours,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || maxHours <= 0) {
      return;
    }

    final plot = Rect.fromLTWH(
      48,
      18,
      size.width - 60,
      size.height - 108,
    );
    final step = plot.width / (points.length - 1);
    final line = Path();

    for (var i = 0; i < points.length; i++) {
      final x = plot.left + step * i;
      final normalized = (points[i].hours / maxHours).clamp(0.0, 1.0);
      final y = plot.bottom - plot.height * normalized;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final area = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();

    final areaPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x330A84FF),
          Color(0x1A0A84FF),
        ],
      ).createShader(plot)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = const Color(0x990A84FF)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(area, areaPaint);
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(covariant _FlightTimeAreaPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.maxHours != maxHours;
  }
}

class _TopModelStats {
  final AircraftModel aircraft;
  final int flights;
  final int minutes;

  const _TopModelStats({
    required this.aircraft,
    required this.flights,
    required this.minutes,
  });

  double get hours => minutes / 60;
}

class _TopModelsTable extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final List<FlightLogEntry> flights;

  const _TopModelsTable({
    required this.aircraft,
    required this.flights,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      for (final model in aircraft)
        _TopModelStats(
          aircraft: model,
          flights:
              flights.where((flight) => flight.aircraftId == model.id).length,
          minutes: flights
              .where((flight) => flight.aircraftId == model.id)
              .fold<int>(0, (sum, flight) => sum + flight.durationMinutes),
        ),
    ]..sort((a, b) {
        final flightCompare = b.flights.compareTo(a.flights);
        if (flightCompare != 0) {
          return flightCompare;
        }
        return b.minutes.compareTo(a.minutes);
      });

    final visibleStats = stats.where((item) => item.flights > 0).take(5);

    return SizedBox(
      width: 390,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFF0A84FF),
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Top-Modelle',
                    style: _sectionTitleStyle,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 30,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 34,
                  horizontalMargin: 0,
                  columnSpacing: 10,
                  headingTextStyle: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                  dataTextStyle: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                  columns: const [
                    DataColumn(label: Text('Rang')),
                    DataColumn(label: Text('Modell')),
                    DataColumn(label: Text('Kategorie')),
                    DataColumn(label: Text('Flugzeit')),
                    DataColumn(label: Text('Fluege')),
                  ],
                  rows: [
                    for (final entry in visibleStats.indexed)
                      DataRow(
                        cells: [
                          DataCell(Text('${entry.$1 + 1}')),
                          DataCell(Text(entry.$2.aircraft.name)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _CategoryUsageIcon(
                                  category: entry.$2.aircraft.type,
                                  size: 24,
                                  imageHeight: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(entry.$2.aircraft.type),
                              ],
                            ),
                          ),
                          DataCell(
                            Text('${entry.$2.hours.toStringAsFixed(1)} h'),
                          ),
                          DataCell(Text('${entry.$2.flights}')),
                        ],
                      ),
                  ],
                ),
              ),
              if (visibleStats.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Noch keine Fluege vorhanden.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryUsageStats extends StatelessWidget {
  final List<AircraftModel> aircraft;
  final List<FlightLogEntry> flights;

  const _CategoryUsageStats({
    required this.aircraft,
    required this.flights,
  });

  @override
  Widget build(BuildContext context) {
    final aircraftById = {for (final model in aircraft) model.id: model};
    final statsByCategory = <String, _CategoryUsage>{};

    for (final flight in flights) {
      final category = aircraftById[flight.aircraftId]?.type ?? 'Unbekannt';
      final current = statsByCategory[category] ?? const _CategoryUsage();
      statsByCategory[category] = current.add(flight.durationMinutes);
    }

    final stats = statsByCategory.entries.toList()
      ..sort((a, b) {
        final minutesCompare = b.value.minutes.compareTo(a.value.minutes);
        if (minutesCompare != 0) {
          return minutesCompare;
        }
        return b.value.flights.compareTo(a.value.flights);
      });
    final totalFlights = stats.fold<int>(
      0,
      (sum, entry) => sum + entry.value.flights,
    );

    return SizedBox(
      width: 900,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.category_rounded,
                    color: Color(0xFF0A84FF),
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Flüge nach Typ',
                    style: _sectionTitleStyle,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (stats.isEmpty)
                const Text(
                  'Noch keine Kategorie-Daten vorhanden.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 230,
                      height: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              centerSpaceRadius: 68,
                              sectionsSpace: 3,
                              sections: [
                                for (var i = 0; i < stats.length; i++)
                                  PieChartSectionData(
                                    value: stats[i].value.flights.toDouble(),
                                    color: _categoryChartColor(i),
                                    title: '',
                                    radius: 48,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$totalFlights',
                                style: _numberTextStyle(
                                  color: const Color(0xFF06172E),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Text(
                                'Flüge',
                                style: TextStyle(
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
                    const SizedBox(width: 30),
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < stats.length; i++)
                            _CategoryUsageLegendItem(
                              color: _categoryChartColor(i),
                              category: stats[i].key,
                              usage: stats[i].value,
                              percent: totalFlights == 0
                                  ? 0
                                  : stats[i].value.flights / totalFlights * 100,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryUsage {
  final int flights;
  final int minutes;

  const _CategoryUsage({
    this.flights = 0,
    this.minutes = 0,
  });

  _CategoryUsage add(int durationMinutes) {
    return _CategoryUsage(
      flights: flights + 1,
      minutes: minutes + durationMinutes,
    );
  }

  double get hours => minutes / 60;
}

class _CategoryUsageLegendItem extends StatelessWidget {
  final Color color;
  final String category;
  final _CategoryUsage usage;
  final double percent;

  const _CategoryUsageLegendItem({
    required this.color,
    required this.category,
    required this.usage,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 9),
          _CategoryUsageIcon(category: category),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF06172E),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${usage.flights} (${percent.toStringAsFixed(0)}%)',
            style: _numberTextStyle(
              color: const Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryUsageIcon extends StatelessWidget {
  final String category;
  final double size;
  final double imageHeight;

  const _CategoryUsageIcon({
    required this.category,
    this.size = 38,
    this.imageHeight = 28,
  });

  @override
  Widget build(BuildContext context) {
    final asset = _categoryImageAsset(category);

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: asset == null
            ? Icon(
                _categoryIcon(category),
                color: const Color(0xFF0A84FF),
                size: imageHeight,
              )
            : Image.asset(
                asset,
                width: _categoryImageWidth(category, iconSize: size),
                height: imageHeight,
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}

List<_FlightTimePoint> _buildFlightTimeData(
  List<FlightLogEntry> flights,
  _FlightTimeRange range,
) {
  final now = DateTime.now();

  switch (range) {
    case _FlightTimeRange.day:
      return [
        for (var offset = 6; offset >= 0; offset--)
          _flightTimePoint(
            flights,
            DateTime(now.year, now.month, now.day).subtract(
              Duration(days: offset),
            ),
            DateTime(now.year, now.month, now.day).subtract(
              Duration(days: offset - 1),
            ),
            _dayLabel(
              DateTime(now.year, now.month, now.day).subtract(
                Duration(days: offset),
              ),
            ),
          ),
      ];
    case _FlightTimeRange.week:
      final startOfThisWeek = DateTime(
        now.year,
        now.month,
        now.day - now.weekday + 1,
      );
      return [
        for (var offset = 7; offset >= 0; offset--)
          _flightTimePoint(
            flights,
            startOfThisWeek.subtract(Duration(days: offset * 7)),
            startOfThisWeek.subtract(Duration(days: (offset - 1) * 7)),
            'KW ${_weekNumber(startOfThisWeek.subtract(Duration(days: offset * 7)))}',
          ),
      ];
    case _FlightTimeRange.month:
      return [
        for (var offset = 11; offset >= 0; offset--)
          _flightTimePoint(
            flights,
            DateTime(now.year, now.month - offset),
            DateTime(now.year, now.month - offset + 1),
            _monthLabel(DateTime(now.year, now.month - offset)),
          ),
      ];
    case _FlightTimeRange.year:
      return [
        for (var offset = 4; offset >= 0; offset--)
          _flightTimePoint(
            flights,
            DateTime(now.year - offset),
            DateTime(now.year - offset + 1),
            '${now.year - offset}',
          ),
      ];
  }
}

_FlightTimePoint _flightTimePoint(
  List<FlightLogEntry> flights,
  DateTime start,
  DateTime end,
  String label,
) {
  final minutes = flights
      .where(
          (flight) => !flight.date.isBefore(start) && flight.date.isBefore(end))
      .fold<int>(0, (sum, flight) => sum + flight.durationMinutes);
  return _FlightTimePoint(label: label, hours: minutes / 60);
}

String _dayLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month';
}

String _monthLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mrz',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];
  return months[date.month - 1];
}

List<FlightLogEntry> _flightsInCurrentMonth(List<FlightLogEntry> flights) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final nextMonthStart = DateTime(now.year, now.month + 1);

  return [
    for (final flight in flights)
      if (!flight.date.isBefore(monthStart) &&
          flight.date.isBefore(nextMonthStart))
        flight,
  ];
}

List<FlightLogEntry> _flightsInPreviousMonth(List<FlightLogEntry> flights) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final previousMonthStart = DateTime(now.year, now.month - 1);

  return [
    for (final flight in flights)
      if (!flight.date.isBefore(previousMonthStart) &&
          flight.date.isBefore(monthStart))
        flight,
  ];
}

double _totalHours(List<FlightLogEntry> flights) {
  final minutes = flights.fold<int>(
    0,
    (sum, flight) => sum + flight.durationMinutes,
  );
  return minutes / 60;
}

FlightLogEntry? _longestFlight(List<FlightLogEntry> flights) {
  if (flights.isEmpty) {
    return null;
  }

  return ([...flights]
        ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes)))
      .first;
}

String _percentChangeText(double current, double previous) {
  if (previous == 0 && current == 0) {
    return '0% zum Vormonat';
  }
  if (previous == 0) {
    return '+100% zum Vormonat';
  }

  final change = ((current - previous) / previous) * 100;
  final prefix = change > 0 ? '+' : '';
  return '$prefix${change.toStringAsFixed(0)}% zum Vormonat';
}

int _weekNumber(DateTime date) {
  final dayOfYear = int.parse(
    '${date.difference(DateTime(date.year)).inDays + 1}',
  );
  return ((dayOfYear - date.weekday + 10) / 7).floor();
}

double _chartInterval(double maxHours) {
  if (maxHours <= 2) {
    return 0.25;
  }
  if (maxHours <= 6) {
    return 0.5;
  }
  if (maxHours <= 12) {
    return 1;
  }
  if (maxHours <= 24) {
    return 2;
  }
  return 5;
}

TextStyle _numberTextStyle({
  required double fontSize,
  Color color = const Color(0xFF06172E),
  FontWeight fontWeight = FontWeight.w700,
}) {
  return TextStyle(
    color: color,
    fontFamily: 'Bahnschrift',
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontFeatures: const [FontFeature.tabularFigures()],
    letterSpacing: 0,
  );
}

const _sectionTitleStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w900,
);

String? _categoryImageAsset(String category) {
  if (_isKunstflugCategory(category)) {
    return 'assets/icons/kunstflug_icon.png';
  }
  if (_isElektroCategory(category)) {
    return 'assets/icons/motorflugz_icon.png';
  }
  if (_isSeglerCategory(category)) {
    return 'assets/icons/segler_icon.png';
  }
  if (_isScaleCategory(category)) {
    return 'assets/icons/scale_icon.png';
  }
  return null;
}

double _categoryImageWidth(String category, {double iconSize = 38}) {
  if (_isSeglerCategory(category)) {
    return iconSize * 0.84;
  }
  if (_isScaleCategory(category)) {
    return iconSize * 0.79;
  }
  return iconSize * 0.9;
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

Color _aircraftChartColor(int index) {
  const colors = [
    Color(0xFF0A84FF),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFDC2626),
    Color(0xFFF59E0B),
    Color(0xFF475569),
  ];

  return colors[index % colors.length];
}

Color _categoryChartColor(int index) {
  const colors = [
    Color(0xFF0A84FF),
    Color(0xFF2563EB),
    Color(0xFF0891B2),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFFDC2626),
    Color(0xFF475569),
  ];

  return colors[index % colors.length];
}
