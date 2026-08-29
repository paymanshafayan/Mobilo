# سند هندآف — Mobilo (نگهبان باتری)

این سند برای **تحویل پروژه به توسعه‌دهندهٔ بعدی** نوشته شده است. با خواندن این فایل، باید بتوانی بدون کمک کسی پروژه را build، debug، شخصی‌سازی و توسعه بدهی.

---

## ۱. خلاصهٔ یک‌خطی

اپ Flutter (Android + iOS) که باتری را ۲۴ ساعته پایش می‌کند؛ در ۱۵٪ هشدار «به شارژ وصل کن» و در ۹۵٪ هشدار «شارژر را جدا کن» می‌دهد؛ هر هشدار **هر ۲ دقیقه تکرار** می‌شود تا کاربر **دکمهٔ دایره‌ای «انصراف» وسط صفحه** (یا اکشن «اسکیپ اعلان» روی نوتیفیکیشن) را بزند.

## ۲. شروع سریع (Environment)

```bash
# پیش‌نیاز: Flutter stable (پروژه با 3.47 ساخته شده؛ 3.35+ هم باید کار کند)
flutter --version
flutter pub get
flutter test          # testهای واحد (بدون نیاز به device)
flutter analyze       # بررسی استاتیک

# اجرا
flutter run                          # روی دستگاه/شبیه‌ساز متصل
flutter build apk --release          # خروجی: build/app/outputs/flutter-apk/app-release.apk
flutter build ipa --release --no-codesign   # خروجی: build/ios/ipa/Runner.ipa (روی macOS)
```

### نکات محیطی که ممکن است گیر کنی

| مشکل | راه‌حل |
|---|---|
| `flutter pub get` خطا می‌دهد | مطمئن شو `channel: stable` هست؛ versiosن‌های پلاگین در `pubspec.yaml` با caret (`^`) pin شده‌اند — اگر خطای سازگاری دیدی، `flutter pub upgrade --major-versions` بزن و کد را بر اساس breaking‌های new adapt کن |
| بیلد Android خطای gradle می‌دهد | این پروژه **Gradle 9.3.1 + AGP 9.1.0 + Kotlin 2.4.0 + JDK 17** می‌خواهد. `local.properties` را خودِ Flutter tool می‌سازد؛ اگر `gradlew` نبود، tool خودکار inject می‌کند (بیلد اول ممکن است چند دقیقه طول بکشد) |
| بیلد iOS «no signing certificate» | برای test: `--no-codesign`. برای اپ استور: در Xcode target `Runner` → Signing & Capabilities یک Development Team انتخاب کن (Bundle ID: `com.mobilo.mobilo`) |
| در iOS اعلان پس‌زمینه نمی‌آید | معمولاً به‌خاطر سیاست‌های اپل است (دست خودِ سیستم)؛ برای شانس بیشتر: گوشی روی شارژ + Wi-Fi + آسوده باشد و در Xcode capability **Push Notifications** فعال باشد |
| در شبیه‌ساز Android درصد باتری ثابت است | سطح باتری شبیه‌ساز با `adb shell dumpsys battery reset && adb shell dumpsys battery set level 15` و `... set status 5/charging` قابل دستکاری است (برای تست آستانه‌ها) |

## ۳. نقشهٔ کد — «چیزی که می‌خواهی را کجا پیدا کنم؟»

> ⚠️ **نسخهٔ پلاگین‌ها:** `battery_plus` **دقیقاً** `6.2.3` pin شده (نه caret) چون کد `battery_service.dart` با API این نسخه نوشته شده (استریم level حذف شده، `batteryLevel` non-nullable شده، `BatteryState.notCharging` به `connectedNotCharging` تغییر نام داده). اگر خواستی آپدیت کنی، اول سورس نسخهٔ جدید را بخوان و `battery_service.dart` را adapt کن. سورس رسمی: `fluttercommunity/plus_plugins` (پکیج `packages/battery_plus`).


| اگر بخواهی... | برو به... |
|---|---|
| آستانه‌های ۱۵٪ / ۹۵٪ را تغییر بدهی | `lib/services/alert_service.dart` (`lowThreshold`/`fullThreshold`) **و** `android/app/src/main/kotlin/.../BatteryGuardService.kt` (`LOW_THRESHOLD`/`FULL_THRESHOLD`) **و** `ios/Runner/AppDelegate.swift` (`lowThreshold`/`fullThreshold`). **هر سه لایه را با هم عوض کن** — منطق در سه جا به‌صورت آگاهانه mirror شده |
| دورهٔ تکرار ۲ دقیقه را تغییر بدهی | Dart: `AlertService.repeatInterval`؛ Kotlin: `ALERT_REPEAT_MS`؛ (iOS background تکرار دقیق ندارد — به بیدار شدن‌های اپل وابسته است) |
| متن/رنگ UI و رشته‌های فارسی | `lib/core/fa.dart` (کلاس `Strings`) |
| صفحهٔ اصلی و دکمهٔ انصراف | `lib/ui/home_screen.dart` — overlay در `_buildSkipOverlay` |
| منطق جلسات هشدار (Dart/iOS) | `lib/services/alert_service.dart` — `_onSnapshot` / `_beginSession` / `_onRepeat` / `dismissAlerts` |
| منطق جلسات هشدار (Android) | `BatteryGuardService.kt` — تابع `checkBattery()` (state-machine) |
| اعلان‌های Android (کانال، آیکون، اکشن‌ها) | `BatteryGuardService.kt` — `createChannels` / `showLowAlert` / `showFullAlert` / `buildServiceNotification` |
| بیدار شدن پس‌زمینهٔ iOS | `ios/Runner/AppDelegate.swift` — `performFetchWithCompletionHandler` |
| کانال‌های بین Dart و native | Dart: `lib/services/guard_channel.dart`؛ Android: `MainActivity.kt` |
| آیکون اعلان (Android) | `android/app/src/main/res/drawable/ic_stat_battery.xml` |
| آیکون اپ | Android: `res/mipmap-*/ic_launcher.png`؛ iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| نام اپ / Package / Bundle ID | `AndroidManifest.xml` + `android/app/build.gradle.kts` (`applicationId`) + `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`) |

## ۴. درونیات — چیزهایی که «چرا» مهم است

### چرا اندروید سرویس Kotlin دارد و از پلاگین background Dart استفاده نشده؟
سرویس‌های Dart در پس‌زمینه (مثل `flutter_background_service`) وابستگی به زنده ماندن engine دارند و API‌شان در نسخه‌ها لنگ می‌زند. سرویس بومی:
- بدون هیچ پلاگین third-party،
- مستقل از engine،
- با کنترل کامل روی نوتیفیکیشن‌ها و threading.
**هشدار:** اگر بخواهی منطق Android را به Dart بکشی، همهٔ رفتارهای `BatteryGuardService.kt` (poll، wake lock، تکرار ۲ دقیقه‌ای، watchdog) را باید جابجا کنی — یک‌شبه انجام نمی‌شود.

### چرا «جلسه» (session) داریم و نه فقط «فلگ هشدادیم/نه»؟
مطالعه‌های کاربری: کاربر باید **تکرار** ببیند تا واکنش نشان دهد؛ اما تکرار تا ابد آزاردهنده است. مدل session:
- شروع با اولین عبور از آستانه،
- تکرار هر ۲ دقیقه،
- پایان با **سه** مسیر: دکمهٔ انصراف، اکشن اسکیپ نوتیفیکیشن، رفع شرط (وصل/جدا شارژر).
`activeAlert` (`'low' | 'full' | null`) در هر سه لایه وجود دارد — **وقتی یکی را عوض می‌کنی، بقیه را هم چک کن.**

### محدودیت‌های start سرویس در Android 12+
کریست‌ها: `start()`/`stop()`/`dismissAlert()` از Dart **مستقیم** سرویس را نمی‌خواهند؛ یک Intent با action می‌فرستند (`startForegroundService`). دلیل: محدودیت‌های OS برای start FGS از background. **این pattern را نشکن.**

### EventSink و تِرَد
در `BatteryGuardService.kt`، `emitEvent` حتماً از طریق `mainHandler.post` اجرا می‌شود — EventSink Flutter خارج از تِرَد اصلی کرش می‌کند. اگر کد بومی اضافه می‌کنی، این قانون را به خاطر داشته باش.

### iOS: دو «نیمه» در تکرار
- foreground: Timer داخل Dart (دقیق ۲ دقیقه).
- background/suspend: فقط وقتی اپل بیدارمان کند (Background Fetch).
این دو با همان identifier اعلان تداخل نمی‌کنند (جایگزینی). انتظار نداشته باش در حالت suspend ریت ۲ دقیقه‌ای داشته باشیم — **در iOS ممکن نیست** بدون سرور.

## ۵. تست و QA

### سناریوهای تست اجباری
1. **حالت normal:** روشن کردن اپ → درصد فعلی درست + آیکون وضعیت صحیح.
2. **آستانهٔ ۱۵٪ (بدون شارژر):** a) اعلان با صدا/لرزش می‌آید؛ b) overlay دکمهٔ دایره‌ای وسط صفحه ظاهر می‌شود؛ c) بعد از ۲ دقیقه اعلان تکرار می‌شود؛ d) با زدن «انصراف» تکرار می‌ایستد؛ e) با وصل شارژر، خودبه‌خود خاتمه می‌یابد.
3. **آستانهٔ ۹۵٪ (با شارژر):** همان ۵ مرحله برای full.
4. **اپ بسته (Android):** سرویس در نوتیفیکیشن نوار وضعیت ماندگار است و درصد زنده دارد؛ با اکشن «توقف نظارت» تمام می‌شود؛ با ری‌بوت دوباره start می‌شود.
5. **iOS foreground:** مراحل ۲ و ۳؛ **iOS background:** گوشی بگذار روی شارژ تا ۹۵٪+ و قفل شود — اعلان باید (به فرصتِ اپل) بیاید.
6. **دستکاری باتری با adb** (شبیه‌ساز):
   ```bash
   adb shell dumpsys battery reset
   adb shell dumpsys battery set level 15     # low alert
   adb shell dumpsys battery set status 3     # AC charging → full-cycle
   adb shell dumpsys battery set level 96     # full alert (while charging)
   adb shell dumpsys battery set status 5     # unplugged
   ```

### تست‌های خودکار
`test/battery_test.dart` — تبدیل اعداد فارسی + رفتار `BatterySnapshot`. اجرای سریع، بدون device.

## ۶. ریلیز و دیپلوی

- نسخه: `pubspec.yaml` (`version: 1.0.0+1`) — build-name + build-number.
- **APK release** در حال حاضر با **debug key** امضا می‌شود (در `android/app/build.gradle.kts` کامنت TODO گذاشته شده). برای اپ استور:
  - key store بساز: `keytool -genkey -v -keystore ~/mobilo-upload.keystore -alias mobilo -keyalg RSA -keysize 2048 -validity 10000`
  - `android/key.properties` بساز (داخل .gitignore است) و بلوک `signingConfigs` در `build.gradle.kts` فعال کن.
- **IPA:** `flutter build ipa --release` با certificate فعال.
- **GitHub Actions:** workflow `.github/workflows/build-apk-ipa.yml` خروجی APK (ubuntu) و IPA بدون امضا (macos) را به‌عنوان artifact تولید می‌کند (در ریپو نگهداری می‌شود).

## ۷. TODO / ایده‌های بعدی (به ترتیح اولویت)

1. **تنظیم آستانه‌ها از UI** (slider) + ذخیره در `shared_preferences`/`secure_storage` — الان ثابت است.
2. **آمار:** تاریخچهٔ شارژ/مصرف + تخمین زمان تا خالی‌شدن (BatteryManager APIهای Android).
3. **APNs push برای iOS** — اگر بخواهیم تکرار دقیق ۲ دقیقه‌ای در background iOS داشته باشیم، فقط با سرور ممکن است (push scheduled).
4. **آیکون اختصاصی** (الان آیکون پیش‌فرض Flutter است).
5. **Light/Dark theme** — فعلاً فقط تیره.
6. **چندزبانه‌سازی** (الان فقط فارسی، با `intl`) اگر بازار هدف گسترش یابد.
7. **Widget صفحهٔ اصلی** (Android home screen / iOS widget) برای دیدن درصد بدون باز کردن اپ.

## ۸. سؤالات پرتکرار

**Q: چرا از `battery_plus` استفاده شده و نه `flutter_battery`؟**
`battery_plus` پلاگین رسمی (فامیل plus، نگهداری‌شده توسط fluttercommunity) است، در هر دو پلتفرم مستقر است و از SPM روی iOS هم پشتیبانی می‌کند (نسخهٔ 6.1 به بعد). نسخهٔ دقیق pin شده — دلیلش را ببخش بالا.

**Q: چرا نوتیفیکیشن سرویس `IMPORTANCE_LOW` است؟**
دائمی است و نباید آزاردهنده باشد؛ هشدارها روی کانال HIGH (صدا+لرزش) می‌روند.

**Q: اگر کاربر نوتیفیکیشن‌ها را کاملاً غیرفعال کند چه می‌شود؟**
اپ نمایش درصد و دکمهٔ انصراف را دارد؛ فقط هشدارهای push نمی‌آیند. در اولین اجرا اجازه درخواست می‌شود و در برگهٔ «چگونه کار می‌کند؟» توضیح داده شده.

**Q: Bundle ID / applicationId؟**
هر دو: `com.mobilo.mobilo`. برای ریلیز واقعی عوض کن (ساختار بالا را ببین).

## ۹. خلاصهٔ ریسک‌ها

| ریسک | Severity | تمیز |
|---|---|---|
| محدودیت پس‌زمینهٔ iOS | inherent (سیاست اپل) | مستندسازی شده؛ در UI و README |
| ۶ ساعت dataSync در Android 16 | متوسط | watchdog خودترمیم |
| بسته شدن سرویس توسط OEM battery savers | متوسط | watchdog + دکمهٔ شروع در UI |
| تغییر API پلاگین‌ها در آپدیت‌های major | کم | caret-pin شده؛ در build شکست می‌خورد نه در runtime |

— پایان سند —
