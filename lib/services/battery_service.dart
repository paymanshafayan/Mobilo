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

/// Singleton wrapper around `battery_plus` that exposes a single
/// [BatterySnapshot] stream to the UI.
///
/// Targeted at `battery_plus` **6.2.x**, whose API:
///  * has a state stream (`onBatteryStateChanged`) but **no level stream**,
///  * exposes a non-nullable `Future<int> batteryLevel`.
///
/// Because of that, the level is polled every [pollInterval] (lightweight
/// method-channel call) and re-read on every state change, so the UI always
/// gets a fresh merged snapshot.
class BatteryService {
  BatteryService._internal();

  static final BatteryService instance = BatteryService._internal();

  final Battery _battery = Battery();
  final StreamController<BatterySnapshot> _controller =
      StreamController<BatterySnapshot>.broadcast();

  /// How often the battery level is polled (6.2.x has no level stream).
  static const Duration pollInterval = Duration(seconds: 5);

  bool _started = false;
  BatterySnapshot? _last;
  Timer? _pollTimer;
  StreamSubscription<BatteryState>? _stateSub;

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
    _stateSub = _battery.onBatteryStateChanged.listen(_onState);
    _pollTimer = Timer.periodic(pollInterval, (_) => _readLevel());
    await _readAll();
  }

  Future<void> _readAll() async {
    int? level;
    BatteryState state;
    try {
      level = await _battery.batteryLevel;
    } catch (_) {
      level = null; // e.g. device without a battery
    }
    try {
      state = await _battery.batteryState;
    } catch (_) {
      state = BatteryState.unknown;
    }
    _emit(level, _mapState(state));
  }

  Future<void> _readLevel() async {
    int? level;
    try {
      level = await _battery.batteryLevel;
    } catch (_) {
      return; // keep the previous value
    }
    _emit(level, null);
  }

  void _onState(BatteryState state) {
    // State change (plug/unplug, full): emit the trend now and refresh
    // the level right away so the UI does not wait for the next poll.
    _emit(null, _mapState(state));
    _readLevel();
  }

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
      case BatteryState.connectedNotCharging:
        return BatteryTrend.notCharging;
      case BatteryState.unknown:
        return BatteryTrend.unknown;
    }
  }
}
