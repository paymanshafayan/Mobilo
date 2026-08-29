/// Persian (Farsi) helpers: digit conversion and shared UI strings.

const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

/// Converts the digits of [value] to Persian digits.
///
/// `faNum(15)` -> `۱۵`. Unknown values render as a question mark.
String faNum(int? value) {
  final String source = (value == null || value < 0) ? '?' : value.toString();
  return source
      .split('')
      .map((String c) {
        final int code = c.codeUnitAt(0);
        if (code >= 0x30 && code <= 0x39) {
          return _persianDigits[code - 0x30];
        }
        return c;
      })
      .join();
}

/// All user-visible strings (Persian).
class Strings {
  Strings._();

  static const String appName = 'Mobilo';
  static const String appTagline = 'نگهبان باتری شما';

  // Battery states.
  static const String charging = 'در حال شارژ';
  static const String discharging = 'در حال مصرف';
  static const String full = 'شارژ کامل';
  static const String notCharging = 'شارژر وصل نیست';
  static const String unknown = 'نامشخص';
  static const String batteryLevel = 'سطح باتری';

  // Low battery alert (<= 15 %).
  static const String lowBatteryTitle = 'باتری رو به اتمام است';
  static String lowBatteryBody(int level) =>
      'سطح باتری به ${faNum(level)}٪ رسیده است. لطفاً گوشی را به شارژ وصل کنید.';

  // Full battery alert (>= 95 %).
  static const String fullBatteryTitle = 'باتری شارژ کامل شد';
  static String fullBatteryBody(int level) =>
      'سطح باتری به ${faNum(level)}٪ رسید. برای حفظ عمر باتری، شارژر را جدا کنید.';

  // Background monitoring.
  static const String monitoring = 'نظارت پس‌زمینه';
  static const String monitoringOn = 'نظارت باتری فعال است';
  static const String monitoringOff = 'نظارت باتری غیرفعال است';
  static const String monitoringOnHint =
      'اپلیکیشن در پس‌زمینه سطح باتری را کنترل می‌کند.';
  static const String monitoringOffHint =
      'برای دریافت اخطارها در پس‌زمینه، نظارت را فعال کنید.';
  static const String startMonitoring = 'شروع نظارت';
  static const String stopMonitoring = 'توقف نظارت';

  // Thresholds.
  static const String thresholds = 'آستانه‌های اخطار';
  static const String thresholdLow = 'اخطار باتری کم: ۱۵٪';
  static const String thresholdFull = 'اخطار شارژ کامل: ۹۵٪';

  // About / how it works.
  static const String aboutTitle = 'چگونه کار می‌کند؟';
  static const String aboutLow =
      'هنگامی که باتری به ۱۵٪ می‌رسد و شارژر وصل نیست، اخطاری با صدا و لرزش نمایش داده می‌شود.';
  static const String aboutFull =
      'هنگامی که باتری به ۹۵٪ می‌رسد و گوشی در حال شارژ است، اخطاری نمایش داده می‌شود تا شارژر را جدا کنید.';
  static const String aboutLimitation =
      'توجه: هیچ اپلیکیشنی (نه در اندروید و نه در iOS) اجازه قطع فیزیکی شارژ توسط سیستم‌عامل را ندارد؛ Mobilo در لحظه رسیدن به ۹۵٪ شما را با اعلان و صدا خبر می‌دهد. برخی گوشی‌ها (مانند سامسونگ) تنظیمات داخلی «محدود کردن شارژ» را دارند.';
  static const String aboutAndroid =
      'در اندروید، یک سرویس پیش‌زمینه (Foreground Service) به صورت ۲۴ ساعته باتری را پایش می‌کند و اعلان‌ها را حتی هنگام بسته بودن اپلیکیشن ارسال می‌کند.';
  static const String aboutIos =
      'در iOS، محدودیت‌های اپل اجازه پایش دائمی در پس‌زمینه را نمی‌دهند؛ اپلیکیشن در حالت فعال به‌صورت زنده پایش می‌کند و در حالت پس‌زمینه بهترین تلاش (best-effort) با بیدار شدن‌های گاه‌به‌گاه سیستم را انجام می‌دهد.';
}
