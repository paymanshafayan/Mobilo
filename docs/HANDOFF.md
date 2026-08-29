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

> ⚠️ **نسخهٔ پلاگین‌ها:** `battery_plus` **دقیقاً** `7.1.1` pin شده (نه caret) چون کد `battery_service.dart` با API این نسخه نوشته شده (استریم level حذف شده، `batteryLevel` non-nullable شده، `BatteryState.notCharging` به `connectedNotCharging` تغییر نام داده). نسخهٔ 7.x برای build با AGP 9 ضروری است: در AGP 9 پلاگین Kotlin Gradle Plugin را apply نمی‌کند (مقرض Built-in Kotlin). API Dart در 7.x با 6.2.x یکسان است. اگر خواستی آپدیت کنی، اول سورس نسخهٔ جدید را بخوان. سورس رسمی: `fluttercommunity/plus_plugins` (پکیج `packages/battery_plus`).


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
| **چت هوش مصنوعی (UI)** | `lib/ui/chat_screen.dart` — استریم، وویس، TTS، چیپ‌های دانلود |
| **تنظیمات / انتخاب مدل** | `lib/ui/settings_screen.dart` — `SettingsScreen` + `ModelSettingsScreen` |
| **تنظیمات AI (مدل + ذخیره)** | `lib/core/ai_settings.dart` — `AiSettings` / `AiProviderDef` / `SectionConfig` |
| **کلاینت API (SSE + جستجو)** | `lib/services/ai_client.dart` — `AiClient` / `SseLineParser` / `WebSearchService` / `chatSystemPrompt` |
| **دانلود فایل** | `lib/services/download_service.dart` — `extractFileUrls` / `DownloadService` |
| **کلید API در build** | `String.fromEnvironment('GROQ_API_KEY')` — در CI: `--dart-define=GROQ_API_KEY=${{ secrets.GROQ_API_KEY }}` (workflow)؛ محلی: `flutter run --dart-define=GROQ_API_KEY=...` |
| **مبینا (مغز دستیار صوتی)** | `lib/services/voice_assistant.dart` — حلقهٔ wake، `_handleCommand`، `_liveLoop`، `_speak` (gate کامل TTS) |
| **مبینا (گوش‌دادن پس‌زمینهٔ اندروید)** | `android/.../VoiceAssistantService.kt` — microphone FGS + SpeechRecognizer + pendingCommand |
| **مبینا (گوشهٔ گفتگوی زنده)** | `lib/ui/voice_chat_sheet.dart` |
| **مبینا (مخاطبین + شماره‌گیری)** | `lib/services/contacts_service.dart` — `lookup`/`normalizeName` (تست‌شده) + `dial` |
| **تنظیمات مبینا** | `lib/ui/settings_screen.dart` — کارت «دستیار صوتی مبینا» (wake، TTS، مجوز مخاطبین) |

### ۴.۱ هوش مصنوعی — نکاتی که «چرا» مهم است

- **چرا کلاینت دست‌ساز با `dart:io` به‌جای SDK (مثل groq/dart_openai)؟** صفر وابستگی اضافی، API سازگار با OpenAI برای همه پرووایدها یکسان است، و SSE parsing خودش یک تابع خالص قابل تست است (`SseLineParser` در `test/ai_client_test.dart`).
- **چرا `groq/compound` برای جستجو؟** جستجوی وب به‌صورت درون‌ساخته دارد (یک request = جستجو + پاسخ + cite)؛ پارامتر `compound_custom.tools.enabled_tools` در `WebSearchService` آن را صریح‌کرد.
- **چرا `/no_think` در system prompt چت؟** مدل Qwen3 پیش‌فرض «با استدلال داخلی» پاسخ می‌دهد (کندتر)؛ با `/no_think` رفتار چت سریع و عادی می‌شود. در مدل‌های بی‌اثر است.
- **نکتهٔ امنیتی:** کلید `--dart-define` در داخل APK/IPA قابل استخراج است. secret ریپو `GROQ_API_KEY` فقط برای buildهای CI استفاده می‌شود؛ اگر کاربر کلید خودش را در Settings وارد کند، آن فقط روی دستگاه می‌ماند.
- **افزودن بخش جدید به مدل‌ها** (مثلاً «خلاصه‌ساز»): یک section id در `AiSettings.defaults()` + یک `_SectionCard` در `ModelSettingsScreen` + سرویس‌تان همان `AiClient.complete/chatStream` را با آن section صدا بزند. همین.

### ۴.۲ مبینا — نکاتی که «چرا» مهم است

- **چرا FGS بومی برای wake word به‌جای پلاگین؟** هیچ پلاگین مستقری «گوش‌دادن دائمی با اپ بسته» را نمی‌دهد؛ `SpeechRecognizer` داخل سرویس پیش‌زمینه‌ی `microphone` استاندارد اندروید است (همان‌طور که اپ‌های assistant واقعی کار می‌کنند). FGS فقط بیداری/گرفتن دستور را می‌کند؛ اجرا با Dart است.
- **چرا نیت‌ها JSON هستند (نه function-calling)؟** برای سازگاری با هر پرووایدر OpenAI-compatible: Groq با `response_format: json_object` (اسکیم حتماً باید در prompt باشد) و بقیه فقط با prompt + parser شل (`MobinaIntent.parse` — تست‌شده).
- **چرا دو موتور گوش‌دادن؟** محدودیت iOS (هیچ پس‌زمینه‌ای) + FGS اندروید (همیشه). قانون: هر لحظه فقط یک شناسا؛ `suspendForChatMic`/`resumeAfterChatMic` و شروع/پایان گفتگوی زنده این تعادل را نگه می‌دارند.
- **ریسک اصلی این بخش:** رفتار `SpeechRecognizer` روی OEMهای مختلف (برخی گوشی‌ها شناسا قوی ندارند) — در آن حالت خودکار به حلقهٔ Dart fallback می‌شود (status ok=false).
- **محدودیت صادقانه:** در iOS wake word فقط با اپ باز؛ در اندروید، اگر کاربر اپ را از memory کشد (swipe)، FGS و همه‌چیز می‌میرد (بازگشت با boot receiver فقط برای سرویس باتری است — برای مبینا فعلاً تعریف نشده).


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
- **GitHub Actions:** workflow `.github/workflows/build-apk-ipa.yml` دو job دارد:
  - `build-apk` (ubuntu): خروجی `app-release.apk`
  - `build-ipa` (macos): خروجی **IPA بدون امضا** + **xcarchive**

  > ⚠️ نکتهٔ مهم (Flutter 3.47): `flutter build ipa --no-codesign` دیگر **IPA تولید نمی‌کند** (فقط xcarchive). به‌همین‌دلیل workflow مستقیماً `xcodebuild archive` + `xcodebuild -exportArchive` با `CODE_SIGNING_ALLOWED=NO` اجرا می‌کند — نیازی به Development Team ندارد. IPA خروجی **بدون امضا** است.

### ساخت IPA امضادار (برای نصب روی دستگاه / اپ استور)

**روش محلی (ساده‌ترین):**
```bash
# روی مک خودت، با Xcode لاگین به Apple ID
# 1) pbxproj: ios/Runner.xcodeproj → Runner → Signing & Capabilities → Development Team را انتخاب کن
flutter build ipa --release        # خروجی: build/ios/ipa/Runner.ipa
```

**روش CI (با secrets):** در GitHub → Settings → Secrets این ۳ مورد را بساز:
- `APPLE_CERTIFICATE` — محتوای base64 فایل `.p12`
- `APPLE_CERTIFICATE_PASSWORD` — رمز همان p12
- `APPLE_PROVISIONING_PROFILE` — محتوای base64 فایل `.mobileprovision`

و این job را به workflow اضافه کن (قبل از هر build، `DEVELOPMENT_TEAM` (10 رقمی) را هم در pbxproj ست کن):
```yaml
  build-ipa-signed:
    name: iOS IPA (signed)
    if: ${{ secrets.APPLE_CERTIFICATE != '' }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - uses: apple-actions/import-codesign-certs-action@v3
        with:
          p12-file-base64: ${{ secrets.APPLE_CERTIFICATE }}
          p12-password: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          keychain-name: build-keys
          keychain-password: build-keys-pass
      - uses: apple-actions/import-codesign-mobile-provision-profile-action@v3
        with:
          mobileprovision-profile-base64: ${{ secrets.APPLE_PROVISIONING_PROFILE }}
      - run: flutter build ipa --release
      - uses: actions/upload-artifact@v4
        with:
          name: mobilo-ipa-signed
          path: build/ios/ipa/Runner.ipa
          if-no-files-found: error
```

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
| `flutter_local_notifications` desugaring می‌خواهد | رفع‌شده | `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring(desugar_jdk_libs)` در `android/app/build.gradle.kts` — اگر AGP نسخهٔ بالاتر خواست، فقط عدد نسخهٔ desugar_jdk_libs را بالا ببر |
| `flutter_local_notifications` SPM ندارد | کم (فعلاً فقط WARNING) | در 3.47 build فقط هشدار می‌دهد و آن پلاگین با CocoaPods build می‌شود؛ در نسخه‌های آیندهٔ Flutter خطای سفت می‌شود — باید منتظر آپدیت پلاگین بمانیم
| VoiceAssistantService (Kotlin، SpeechRecognizer در FGS) | متوسط | روی OEMهای ضعیف‌تر شناسا ممکن است نداشتن → fallback خودکار به حلقهٔ Dart (status ok=false). تست دستگاهی حتماً
| flutter_contacts 2.3.1 (API v2) | کم | دقیقاً pin؛ کد با API `FlutterContacts.*` نسخهٔ 2.x نوشته شده (نسخهٔ 1.x کلاس `Contacts` دارد — مختلط نکن)
| بسته‌های AI (speech_to_text, flutter_tts, share_plus, url_launcher, path_provider, shared_preferences) | کم | همه دقیقاً pin شده‌اند و با API این نسخه‌ها نوشته شده‌اند؛ در جدول ۳ راهنمای pin/آپدیت مثل battery_plus صادق است
| تغییر آیکون‌ها در نسخه‌های Flutter | کم | `Icons.battery_horiz` در 3.47 حذف شده و با `battery_std` جایگزین شد؛ اگر خطای `Member not found: Icons.x` دیدی، `packages/flutter/lib/src/material/icons.dart` در Flutter خودت را چک کن |
| تغییر API پلاگین‌ها در آپدیت‌های major | کم | caret-pin شده؛ در build شکست می‌خورد نه در runtime |

— پایان سند —
