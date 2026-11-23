import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TravelTrackerApp());

class TravelTrackerApp extends StatelessWidget {
  const TravelTrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
  title: 'Trackley',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff146c94)),
          useMaterial3: true,
        ),
        home: const TrackerHome(),
      );
}

class DailyDistance {
  DailyDistance(this.date, this.meters);
  final DateTime date;
  double meters;

  Map<String, dynamic> toJson() => {'date': DateFormat('yyyy-MM-dd').format(date), 'meters': meters};
  static DailyDistance fromJson(Map<String, dynamic> json) => DailyDistance(DateTime.parse(json['date'] as String), (json['meters'] as num).toDouble());
}

class TrackerHome extends StatefulWidget {
  const TrackerHome({super.key});

  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> {
  static const _storageKey = 'daily_distances_v1';
  final List<DailyDistance> _days = [];
  StreamSubscription<Position>? _locationSubscription;
  Position? _lastPosition;
  bool _tracking = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDistances();
  }

  Future<void> _loadDistances() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final values = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _days.addAll(values.map(DailyDistance.fromJson));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveDistances() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_days.map((d) => d.toJson()).toList()));
  }

  DailyDistance _todayRecord() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return _days.firstWhere(
      (d) => d.date == day,
      orElse: () {
        final record = DailyDistance(day, 0);
        _days.add(record);
        return record;
      },
    );
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _lastPosition = null;
      if (mounted) setState(() => _tracking = false);
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _error = 'Turn on Location Services to track a trip.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission is required while a trip is running.');
      return;
    }

    setState(() {
      _tracking = true;
      _error = null;
    });
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(_onPosition, onError: (_) {
      if (mounted) setState(() => _error = 'Unable to read your location.');
    });
  }

  void _onPosition(Position position) {
    final previous = _lastPosition;
    _lastPosition = position;
    if (previous == null) return;
    final meters = Geolocator.distanceBetween(previous.latitude, previous.longitude, position.latitude, position.longitude);
    // Ignore GPS jitter and implausibly large jumps between readings.
    if (meters < 5 || meters > 1000) return;
    setState(() => _todayRecord().meters += meters);
    _saveDistances();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final now = DateTime.now();
    final today = _days.where((d) => d.date.year == now.year && d.date.month == now.month && d.date.day == now.day).fold<double>(0, (sum, d) => sum + d.meters);
    final monthDays = _days.where((d) => d.date.year == now.year && d.date.month == now.month).toList()..sort((a, b) => a.date.compareTo(b.date));
    final monthTotal = monthDays.fold<double>(0, (sum, d) => sum + d.meters);

    return Scaffold(
      appBar: AppBar(title: const Text('Trackley')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(DateFormat('EEEE, d MMMM').format(now), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _DistanceCard(label: 'Today', meters: today, active: _tracking),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(_tracking ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              label: Text(_tracking ? 'Stop tracking' : 'Start tracking'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: _tracking ? Colors.red.shade700 : null),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 32),
            Text(DateFormat('MMMM yyyy').format(now), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${_formatDistance(monthTotal)} total this month'),
            const SizedBox(height: 18),
            SizedBox(height: 210, child: _MonthlyChart(days: monthDays, month: now)),
            const SizedBox(height: 16),
            ...monthDays.reversed.map((d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route_outlined),
                  title: Text(DateFormat('EEE, d MMM').format(d.date)),
                  trailing: Text(_formatDistance(d.meters), style: const TextStyle(fontWeight: FontWeight.w600)),
                )),
          ],
        ),
      ),
    );
  }
}

class _DistanceCard extends StatelessWidget {
  const _DistanceCard({required this.label, required this.meters, required this.active});
  final String label;
  final double meters;
  final bool active;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active ? 'Trip in progress' : label),
            const SizedBox(height: 8),
            Text(_formatDistance(meters), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.days, required this.month});
  final List<DailyDistance> days;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final values = {for (final d in days) d.date.day: d.meters / 1000};
    final entries = List.generate(DateUtils.getDaysInMonth(month.year, month.month), (i) => FlSpot(i + 1.0, values[i + 1] ?? 0));
    final maxY = entries.fold<double>(1, (max, e) => e.y > max ? e.y : max) * 1.2;
    return LineChart(LineChartData(
      minX: 1, maxX: entries.length.toDouble(), minY: 0, maxY: maxY,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
      lineBarsData: [LineChartBarData(spots: entries, isCurved: true, color: Theme.of(context).colorScheme.primary, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Theme.of(context).colorScheme.primary.withOpacity(.12)))],
    ));
  }
}

String _formatDistance(double meters) => meters >= 1000 ? '${(meters / 1000).toStringAsFixed(2)} km' : '${meters.round()} m';

