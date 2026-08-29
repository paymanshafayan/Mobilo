import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

/// Coarse charging trend shown in the UI.
enum BatteryTrend { charging, discharging, full, notCharging, unknown }

/// A single battery reading: level in percent + charging trend.
class BatterySnapshot {
  const BatterySnapshot({required this.level, required this.trend});

  /// Battery level in percent (0-100). `null` when the platform
  /// cannot report it.
  final int? level;

  final BatteryTrend trend;

  bool get isCharging => trend == BatteryTrend.charging;

  bool get isFull =>
      trend == BatteryTrend.full ||
      (level != null && level! >= 95 && isCharging);

  BatterySnapshot merge({int? level, BatteryTrend? trend}) => BatterySnapshot(
        level: level ?? this.level,
        trend: trend ?? this.trend,
      );
}

/// Singleton wrapper around `battery_plus` that merges the level stream and
/// the state stream into a single [BatterySnapshot] stream.
class BatteryService {
  BatteryService._internal();

  static final BatteryService instance = BatteryService._internal();

  final Battery _battery = Battery();
  final StreamController<BatterySnapshot> _controller =
      StreamController<BatterySnapshot>.broadcast();

  bool _started = false;
  BatterySnapshot? _last;

  /// Broadcast stream of merged battery readings.
  Stream<BatterySnapshot> get snapshots => _controller.stream;

  /// The most recent reading (null until the first one arrives).
  BatterySnapshot? get last => _last;

  bool get isStarted => _started;

  /// Starts listening. Safe to call multiple times.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _battery.onBatteryLevelRead.listen(_onLevel);
    _battery.onBatteryStateChanged.listen(_onState);
    await _readOnce();
  }

  Future<void> _readOnce() async {
    int? level;
    BatteryState state;
    try {
      level = await _battery.batteryLevel;
      state = await _battery.batteryState;
    } catch (_) {
      // Plugin unavailable (e.g. unit tests) - stay silent.
      return;
    }
    _emit(level, _mapState(state));
  }

  void _onLevel(int? level) => _emit(level, null);

  void _onState(BatteryState state) => _emit(null, _mapState(state));

  void _emit(int? level, BatteryTrend? trend) {
    final BatterySnapshot next = BatterySnapshot(
      level: level ?? _last?.level,
      trend: trend ?? _last?.trend ?? BatteryTrend.unknown,
    );
    _last = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  BatteryTrend _mapState(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return BatteryTrend.charging;
      case BatteryState.discharging:
        return BatteryTrend.discharging;
      case BatteryState.full:
        return BatteryTrend.full;
      case BatteryState.notCharging:
        return BatteryTrend.notCharging;
      case BatteryState.unknown:
        return BatteryTrend.unknown;
    }
  }
}
