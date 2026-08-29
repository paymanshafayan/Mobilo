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

/// Converts the ASCII digits of any string (e.g. a phone number) to
/// Persian digits, leaving everything else untouched.
String faDigits(String value) {
  return value
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
  static const String notCharging = 'شارژر وصل است — در حال شارژ نیست';
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

  // Circular dismiss button + repetition hint.
  static const String skipAlert = 'انصراف';
  static const String alertRepeatHint =
      'تا فشردن دکمه‌ی «انصراف»، اعلان هر ۲ دقیقه تکرار می‌شود';
  static const String lowAlertHeader = 'باتری کم است — به شارژ وصل کنید';
  static const String fullAlertHeader = 'شارژ کامل شد — شارژر را جدا کنید';

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

  // ------------------------------------------------------------------
  // AI assistant (chat + web search + downloads) — Mobina (مبینا)
  // ------------------------------------------------------------------
  static const String mobinaName = 'مبینا';
  static const String chatTitle = 'مبینا';
  static const String chatHint = 'پرسش خود را بنویسید یا روی میکروفون بزنید…';
  static const String chatSearchHint = 'موضوع جستجو در وب را بنویسید…';
  static const String chatSearchMode = 'جستجوی وب';
  static const String chatWelcome = 'سلام! من مبینا هستم. چطور می‌توانم کمکتان کنم؟';
  static const String chatWelcomeSub =
      'با مبینا می‌توانید با متن یا صدا گفتگو کنید، در وب جستجو کنید و فایل‌های مرتبط را دانلود کنید. کافی است بگویید «مبینا» تا بیدار شود!';
  static const String chatSend = 'ارسال';
  static const String chatStop = 'توقف';
  static const String chatNew = 'گفتگوی جدید';
  static const String speakReply = 'پخش پاسخ';
  static const String micListening = 'در حال گوش دادن…';
  static const String micUnavailable = 'شناسایی گفتار در دسترس نیست.';
  static const String ttsError = 'پخش صدا در دسترس نیست';
  static const String suggestBatteryTips = 'نکات مهم برای عمر بیشتر باتری';
  static const String suggestSearch = 'جستجو: آخرین اخبار فناوری باتری';
  static const String fileDownload = 'دانلود';
  static const String fileDone = 'دانلود شد';
  static const String fileShare = 'اشتراک‌گذاری';

  // Settings.
  static const String settingsTitle = 'تنظیمات';
  static const String settingsModel = 'مدل هوش مصنوعی';
  static const String settingsSection = 'بخش';
  static const String settingsSectionChat = 'بخش چت';
  static const String settingsSectionSearch = 'بخش جستجوی وب';
  static const String settingsProvider = 'پرووایدر';
  static const String settingsModelName = 'مدل';
  static const String settingsProviders = 'پرووایدها';
  static const String settingsAddProvider = 'افزودن پرووایدر (سازگار با OpenAI)';
  static const String settingsAddProviderShort = 'افزودن پرووایدر';
  static const String settingsEditProvider = 'ویرایش پرووایدر';
  static const String settingsDelete = 'حذف';
  static const String settingsDeleteConfirm = 'حذف پرووایدر';
  static const String settingsProviderName = 'نام';
  static const String settingsProviderBaseUrl = 'آدرس API (base URL)';
  static const String settingsProviderKey = 'کلید API';
  static const String settingsProviderModels = 'مدل‌ها (با ویرگول جدا کنید)';
  static const String settingsNoKey = 'کلید API تنظیم نشده است';
  static const String settingsKeySet = 'کلید API تنظیم شده است';
  static const String settingsKeyFromBuild =
      'کلید از نسخهٔ build (GROQ_API_KEY) خوانده می‌شود؛ برای تغییر، آن را اینجا وارد کنید';
  static const String settingsReadAloud = 'خواندن پاسخ با صدا';
  static const String settingsReadAloudSub =
      'پاسخ‌های دستیار را می‌توانید با دکمهٔ بلندگو بخوانید؛ با این گزینه صدا آماده می‌ماند';
  static const String settingsPrivacy = 'حریم خصوصی';
  static const String settingsPrivacyText =
      'تنظیمات، کلیدهای API و گفتگوها فقط روی همین دستگاه ذخیره می‌شوند. درخواست‌ها مستقیم از گوشی شما به پرووایدر انتخابی ارسال می‌شود و از سرورهای Mobilo عبور نمی‌کند.';
  static const String save = 'ذخیره';
  static const String cancel = 'انصراف';

  // Mobina: voice assistant (live voice chat + wake word + commands).
  static const String voiceChat = 'گفتگوی زندهٔ صوتی';
  static const String voiceChatHint =
      'بگویید و مبینا جواب می‌دهد؛ برای قطع دکمهٔ × را بزنید';
  static const String voiceListening = 'مبینا گوش می‌دهد…';
  static const String voiceCapturing = 'مبینا: بفرمایید، در حال شنیدن دستور';
  static const String voiceThinking = 'در حال فکر کردن…';
  static const String voiceSpeaking = 'در حال صحبت کردن…';
  static const String voiceIdle = 'آماده';
  static const String voiceListeningHint = 'هر لحظه می‌توانید صحبت کنید';
  static const String mobinaWakeBar =
      'مبینا گوش می‌دهد — برای بیدار کردنش بگویید «مبینا»';
  static const String mobinaCapturingBar =
      'مبینا: بفرمایید! در حال شنیدن دستور شماست…';
  static const String settingsVoiceTitle = 'دستیار صوتی مبینا';
  static const String settingsWakeWord = 'گوش دادن مداوم برای «مبینا»';
  static const String settingsWakeWordSub =
      'در اندروید حتی با اپ بسته هم کار می‌کند (سرویس پیش‌زمینه)؛ در iOS فقط وقتی اپ باز باشد';
  static const String settingsVoiceTts = 'پاسخ‌های صوتی مبینا';
  static const String settingsVoiceTtsSub =
      'نتیجهٔ دستورات صوتی را مبینا با صدا اعلام می‌کند';
  static const String settingsContacts = 'مجوز مخاطبین';
  static const String settingsContactsGranted = 'فعال';
  static const String settingsContactsDenied = 'غیرفعال — برای فعال‌کردن بزنید';
  static const String settingsContactsNone = 'هنوز درخواست نشده — برای فعال‌کردن بزنید';
  static const String settingsVoiceExample =
      'مثال: «مبینا، شماره‌ی مامان را بگیر» — مبینا مخاطب را پیدا کرده و شماره‌گیری می‌کند';
}
