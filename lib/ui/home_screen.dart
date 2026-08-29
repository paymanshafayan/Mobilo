import 'dart:async';

import 'package:flutter/material.dart';

import '../core/fa.dart';
import '../services/alert_service.dart';
import '../services/battery_service.dart';
import '../services/guard_channel.dart';
import 'about_sheet.dart';
import 'battery_gauge.dart';

/// Main screen: live battery gauge, state, alerts and monitoring controls.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GuardChannel _guard = GuardChannel.instance;
  final ValueNotifier<bool> _serviceRunning = ValueNotifier<bool>(false);
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  @override
  void initState() {
    super.initState();
    _refreshServiceState();
    _eventSub = _guard.events.listen(_onServiceEvent);
  }

  void _onServiceEvent(Map<String, dynamic> event) {
    // Receiving an event proves the native service is alive.
    if (event.isNotEmpty && !_serviceRunning.value) {
      _serviceRunning.value = true;
    }
  }

  Future<void> _refreshServiceState() async {
    final bool running = await _guard.isRunning();
    if (mounted) {
      _serviceRunning.value = running;
    }
  }

  Future<void> _toggleService() async {
    if (_serviceRunning.value) {
      await _guard.stop();
    } else {
      await _guard.start();
    }
    await _refreshServiceState();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _serviceRunning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.appName),
            Text(
              Strings.appTagline,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: Strings.aboutTitle,
            icon: const Icon(Icons.info_outline),
            onPressed: () => AboutSheet.show(context),
          ),
        ],
      ),
      body: StreamBuilder<BatterySnapshot>(
        stream: BatteryService.instance.snapshots,
        initialData: BatteryService.instance.last,
        builder: (context, snapshot) {
          final BatterySnapshot battery = snapshot.data ??
              const BatterySnapshot(
                level: null,
                trend: BatteryTrend.unknown,
              );
          final Widget? alert = _alertCard(context, battery);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGauge(context, battery),
                const SizedBox(height: 24),
                _buildStatusCard(context, battery),
                if (alert != null) ...[
                  const SizedBox(height: 12),
                  alert,
                ],
                const SizedBox(height: 12),
                _buildMonitoringCard(context),
                const SizedBox(height: 12),
                _buildThresholdsCard(context),
                const SizedBox(height: 12),
                _buildAboutButton(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGauge(BuildContext context, BatterySnapshot battery) {
    final int? level = battery.level;
    final double fraction =
        level == null ? 0.0 : (level / 100).clamp(0.0, 1.0).toDouble();
    final Color color = _gaugeColor(context, battery);

    return Center(
      child: BatteryGauge(
        fraction: fraction,
        color: color,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _stateIcon(battery),
              size: 42,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              level == null ? '—' : '${faNum(level)}٪',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            Text(
              Strings.batteryLevel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _gaugeColor(BuildContext context, BatterySnapshot battery) {
    final int? level = battery.level;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (battery.isCharging || battery.isFull) {
      return const Color(0xFF34A853);
    }
    if (level != null && level <= AlertService.lowThreshold) {
      return const Color(0xFFE53935);
    }
    return scheme.primary;
  }

  IconData _stateIcon(BatterySnapshot battery) {
    switch (battery.trend) {
      case BatteryTrend.charging:
        return Icons.battery_charging_full;
      case BatteryTrend.full:
        return Icons.battery_full;
      case BatteryTrend.discharging:
        return Icons.battery_horiz;
      case BatteryTrend.notCharging:
        return Icons.battery_unknown;
      case BatteryTrend.unknown:
        return Icons.battery_unknown;
    }
  }

  Widget _buildStatusCard(BuildContext context, BatterySnapshot battery) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String text = switch (battery.trend) {
      BatteryTrend.charging => Strings.charging,
      BatteryTrend.full => Strings.full,
      BatteryTrend.discharging => Strings.discharging,
      BatteryTrend.notCharging => Strings.notCharging,
      BatteryTrend.unknown => Strings.unknown,
    };
    return Card(
      color: _gaugeColor(context, battery).withOpacity(0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              _stateIcon(battery),
              color: _gaugeColor(context, battery),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (battery.level != null)
              Text(
                '${faNum(battery.level)}٪',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Returns the alert card when a threshold is crossed, otherwise null.
  Widget? _alertCard(BuildContext context, BatterySnapshot battery) {
    final int? level = battery.level;
    if (level == null) {
      return null;
    }
    if (level <= AlertService.lowThreshold && !battery.isCharging) {
      return _thresholdCard(
        context,
        color: const Color(0xFFE53935),
        icon: Icons.warning_amber_rounded,
        title: Strings.lowBatteryTitle,
        body: Strings.lowBatteryBody(level),
      );
    }
    if (battery.isCharging && level >= AlertService.fullThreshold) {
      return _thresholdCard(
        context,
        color: const Color(0xFF34A853),
        icon: Icons.battery_full_rounded,
        title: Strings.fullBatteryTitle,
        body: Strings.fullBatteryBody(level),
      );
    }
    return null;
  }

  Widget _thresholdCard(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringCard(BuildContext context) {
    if (!_guard.isAndroid) {
      return _simpleCard(
        context,
        icon: Icons.notifications_active_outlined,
        title: Strings.monitoring,
        body: Strings.aboutIos,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _serviceRunning,
      builder: (context, running, _) {
        final Color accent =
            running ? const Color(0xFF34A853) : const Color(0xFFE53935);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  running
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: accent,
                  size: 34,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Strings.monitoring,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        running
                            ? Strings.monitoringOnHint
                            : Strings.monitoringOffHint,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _toggleService,
                  icon: Icon(
                    running ? Icons.stop_circle : Icons.play_circle,
                  ),
                  label: Text(
                    running
                        ? Strings.stopMonitoring
                        : Strings.startMonitoring,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _simpleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                Text(
                  Strings.thresholds,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE53935)),
                const SizedBox(width: 8),
                Text(Strings.thresholdLow),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.battery_full, color: Color(0xFF34A853)),
                const SizedBox(width: 8),
                Text(Strings.thresholdFull),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => AboutSheet.show(context),
      icon: const Icon(Icons.help_outline),
      label: const Text(Strings.aboutTitle),
    );
  }
}
