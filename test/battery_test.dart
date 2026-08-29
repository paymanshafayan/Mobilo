import 'package:flutter_test/flutter_test.dart';
import 'package:mobilo/core/fa.dart';
import 'package:mobilo/services/battery_service.dart';

void main() {
  group('faNum (Persian digits)', () {
    test('converts ASCII digits to Persian digits', () {
      expect(faNum(0), '۰');
      expect(faNum(15), '۱۵');
      expect(faNum(95), '۹۵');
      expect(faNum(100), '۱۰۰');
    });

    test('null renders as a question mark', () {
      expect(faNum(null), '?');
    });
  });

  group('BatterySnapshot', () {
    test('isCharging reflects the trend', () {
      expect(
        const BatterySnapshot(level: 80, trend: BatteryTrend.charging)
            .isCharging,
        isTrue,
      );
      expect(
        const BatterySnapshot(level: 80, trend: BatteryTrend.discharging)
            .isCharging,
        isFalse,
      );
    });

    test('isFull is true at 100 % while charging', () {
      const BatterySnapshot snapshot =
          BatterySnapshot(level: 100, trend: BatteryTrend.charging);
      expect(snapshot.isFull, isTrue);
    });

    test('merge keeps previous values for missing parts', () {
      const BatterySnapshot base =
          BatterySnapshot(level: 60, trend: BatteryTrend.discharging);
      final BatterySnapshot merged = base.merge(level: 59);
      expect(merged.level, 59);
      expect(merged.trend, BatteryTrend.discharging);
    });
  });
}
