# سند هندآف — Mobilo (نگهبان باتری + دستیار مبینا)

این سند برای **تحویل پروژه به توسعه‌دهندهٔ بعدی** (یا یک سشن/چت جدید) نوشته شده است. با خواندن این فایل، باید بتوانی بدون کمک کسی پروژه را build، debug، شخصی‌سازی و توسعه بدهی.

---

## ۰. وضعیت فعلی (اولین چیزی که باید بخوانی)

**آخرین به‌روزرسانی: ۲۰۲۶-۰۸-۳۰ — هر دو job CI سبز است.**

- اپ Flutter (Android + iOS) با سه بخش: **نگهبان باتری** (هشدار ۱۵٪/۹۵٪ با تکرار ۲ دقیقه‌ای)، **دستیار AI** (چت/جستجوی وب/دانلود با Groq یا هر OpenAI-compatible)، و **مبینا** (گفتگوی زندهٔ صوتی + wake word دائمی + دستورات واقعی مثل «شماره مامان را بگیر»).
- بَرچ کار: `arena/01a04e34-mobilo` (PR شمارهٔ ۱ روی `paymanshafayan/Mobilo`)؛ در تاریخ بالا به `main` merge شد.
- CI (`.github/workflows/build-apk-ipa.yml`): `flutter test` (۲۶ تست) + build **APK release** + آرشیو **iOS Release بدون امضا** — هر دو سبز با آرتیفکت.

### ⚖️ قوانین دائمی کاربر (حتماً رعایت کن)

1. **قبل از هر کاری، تحقیق و بررسی روی وب:** APIها و راه‌کارها را فقط از حافظه ندان؛ آخرین مستندات رسمی و سورس نسخهٔ دقیق پلاگین را چک کن (بخش «دام‌ها» پایین پر از نمونه است — همه از تجربهٔ Runهای قرمز CI به‌دست آمدند).
2. **فایل workflow مالِ کاربر است:** هرگز `.github/workflows/*` را create/commit/push نکن (GitHub App اجازهٔ `workflows` ندارد → خطای «refusing to allow a GitHub App to create or update workflow»). نسخهٔ کامل YAML فقط در چت داده می‌شود و کاربر خودش اعمال می‌کند. این فایل در `.git/info/exclude` هم هست؛ اگر محلی تغییر کرد، از remote برگردان.
3. **پاسخ نهایی به فارسی** (اصطلاحات فنی انگلیسی آزاد است).
4. **بعد از هر کار تمام‌شده: commit + push** روی بَرچ سشن.
5. **اگر `git`/`gh` خطای احراز هویت داد** (مثلاً «GH_TOKEN is no longer valid»): از کاربر بخواه GitHub را در Arena reconnect کند؛ خودت دنبال توکن نگرد.

### ⚠️ نکته‌های محیطی سشن (سنباکس Arena)

- `/tmp` بین سشن‌ها **پاک می‌شود** (venvهای Python و اسکریپت‌های کمکی بازمی‌سازند: `python3 -m venv /tmp/tsenv2 && pip install tree-sitter tree-sitter-dart tree-sitter-kotlin`).
- ریپوی لوکال گاهی بین سشن‌ها **ریست** می‌شود (تاریخچه تا Initial commit). پیش از هر کار: `git fetch origin` و `git log --oneline -3` را چک کن؛ اگر بَرچ remote جلو رفته، کار جدید را **روی FETCH_HEAD** بساز (rebase) نه روی وضعیت قدیمی.
- `flutter` در سنباکس نصب نیست و دانلود SDK بلاک است — **کامپایل محلی Dart/Flutter ممکن نیست**. تکیه کن روی: (الف) CI به‌عنوان build truth، (ب) tree-sitter syntax check، (ج) شبیه‌سازی منطق با Python (مراقب تفاوت‌های semantics بین Dart و Python باش — همین‌جا چند بار جا خوردیم).

### 🗺️ داستان CI (چرا این‌همه کامیت fix داریم)

| فاز | چه گذشت |
|---|---|
| Battery app | CI سبز شد (هر دو job + ۳ آرتیفکت) |
| AI assistant | CI سبز شد |
| Mobina (پوش) | ۵ خطای compile در `flutter test` (API پلاگین‌ها) → fix شد |
| Mobina | ۴ تست runtime شکسته (SSE، wake word، TTS) → fix شد |
| Mobina | خطای `replaceAll` Dart (نه back-reference، نه تابع — فقط literal) → fix شد |
| build کامل | ۲ خطای UI Dart که `flutter test` هرگز ندیده بود (فایل‌های UI توسط هیچ تستی import نمی‌شوند) → fix شد |
| iOS | درک صحیح: دستگاه بدون Team نمی‌شود + Release شبیه‌ساز نیست → workflow روی `xcodebuild archive` مستقیم |
| build کامل | ۴ خطای Kotlin در `VoiceAssistantService.kt` (اولین کامپایل واقعی) → fix شد |
| **حاضر** | **هر دو job سبز ✅** |

### 🚀 قدم‌های بعدی پیشنهادی (برای سشن جدید)

1. **تست دستگاهی مبینا** (تنها ریسک باقی‌مانده): FGS + `SpeechRecognizer` روی ۲-۳ گوشی واقعی (OEMهای مختلف) — رفتار wake word، کشتن FGS توسط battery saver، و مسیر fallback.
2. آیتم‌های بخش ۷ (TODO) به ترتیب اولویت.
3. اگر Flutter تازه‌تر گرفت: هشدار KGP (`flutter_tts`/`speech_to_text` در نسخه‌های آینده باید Built-in Kotlin را support کنند) را چک کن.

---

## ۱. خلاصهٔ یک‌خطی

اپ Flutter (Android + iOS) با سه بخش: **(الف) نگهبان باتری** — ۲۴ ساعته پایش؛ در ۱۵٪ هشدار «به شارژ وصل کن» و در ۹۵٪ «شارژر را جدا کن»؛ هر هشدار **هر ۲ دقیقه تکرار** می‌شود تا کاربر **دکمهٔ دایره‌ای «انصراف» وسط صفحه** (یا اکشن «اسکیپ اعلان») را بزند. **(ب) دستیار AI** — چت با متن و صدا (streaming)، جستجوی وب با cite، دانلود فایل؛ پیش‌فرض Groq. **(ج) مبینا** — گفتگوی زندهٔ صوتی (مثل Gemini/ChatGPT) با wake word دائمی «مبینا» (در اندروید حتی با اپ بسته) و اجرای دستورات واقعی (شماره‌گیری مخاطب، جستجو، دانلود).

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

### تست‌های خودکار (۲۶ تست، بدون device)
- `test/battery_test.dart` — تبدیل اعداد فارسی + رفتار `BatterySnapshot`.
- `test/ai_client_test.dart` — `SseLineParser` (semantics رویداد SSE با خط خالی؛ chunkها ممکن است هرجایی شکسته شوند)، `AiClient.deltaContent`، `extractFileUrls`، `fileNameFromUrl`.
- `test/voice_assistant_test.dart` — `textAfterWakeWord` (فارسی + لاتین)، `ttsReadyText` (پاک‌کردن markdown/URL + truncation)، `MobinaIntent.parse` (JSON تمیز / داخل chatter / garbage→chat)، `faDigits`، تطبیق نام مخاطبین (normalization ی/یه، contains).

> ⚠️ `flutter test` فقط فایل‌هایی را کامپایل می‌کند که تست‌ها import می‌کنند — **فایل‌های UI (`lib/ui/*`) توسط هیچ تستی import نمی‌شوند** و اولین باری که کامپایل می‌شوند، مرحلهٔ build است. (این دقیقاً جایی بود که دو خطای UI در CI کشف شد.)

## ۶. ریلیز و دیپلوی

- نسخه: `pubspec.yaml` (`version: 1.0.0+1`) — build-name + build-number.
- **APK release** با کلید stable کارتی `android/app/mobilo-sideload.p12` (PKCS12، alias `mobilo`) امضا می‌شود — این کلید **همراه با ریپو کامیت شده** تا همه‌ی بیلدهای CI امضای یکسانی داشته باشند (قبلاً با debug key امضا می‌شد و چون هر runner CI یک debug keystore تازه با کلید تصادفی می‌سازد، نصب APK جدید روی نسخه‌ی نصب‌شده با خطای عمومی «App not installed» رد می‌شد — این دقیقاً مشکل اندروید ۹ کاربر بود). این کلید فقط برای sideload است؛ برای اپ استور:
  - key store بساز: `keytool -genkey -v -keystore ~/mobilo-upload.keystore -alias mobilo -keyalg RSA -keysize 2048 -validity 10000`
  - `android/key.properties` بساز (داخل .gitignore است) و بلوک `signingConfigs` در `build.gradle.kts` فعال کن.
- **IPA:** `flutter build ipa --release` با certificate فعال.
- **GitHub Actions:** workflow `.github/workflows/build-apk-ipa.yml` دو job دارد:
  - `build-apk` (ubuntu): خروجی `app-release.apk`
  - `build-ipa` (macos): خروجی **xcarchive بدون امضای دستگاه** (Release، همیشه در دسترس) + **IPA بدون امضا** (best-effort از طریق `-exportArchive`)

  > ⚠️ نکته‌های مهم (Flutter 3.47): (۱) `flutter build ipa --no-codesign` IPA تولید نمی‌کند (فقط xcarchive). (۲) `flutter build ios --no-codesign` برای **دستگاه** حتی با `--no-codesign` نیاز به **Development Team انتخاب‌شده** دارد (خودِ ابزار این را بررسی می‌کند) — در CI که حساب Apple نیست می‌افتد. (۳) بیلد **Release برای شبیه‌ساز اصلاً پشتیبانی نمی‌شود** («Release mode is not supported for simulators»؛ AOT فقط برای دستگاه است). به‌همین‌دلیل workflow اصلاً `flutter build ios` را اجرا نمی‌کند: بعد از `pod install` مستقیماً `xcodebuild archive -configuration Release -destination generic/platform=iOS` با `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` اجرا می‌شود — فازهای بیلد Flutter همچنان داخل xcodebuild (از طریق `xcode_backend.sh`) اجرا می‌شوند، پس کل target iOS در Release کامپایل می‌شود بدون هیچ Development Team.

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

## ۷. TODO / ایده‌های بعدی (به ترتیب اولویت)

1. **تست دستگاهی مبینا** — wake word روی OEMهای مختلف، فاصلهٔ کشتن FGS توسط battery savers، کیفیت `SpeechRecognizer` فارسی، و مسیر fallback به حلقهٔ Dart. (تنها ریسک بی‌تستِ باقی‌مانده.)
2. **تنظیم آستانه‌ها از UI** (slider) + ذخیره در `shared_preferences`/`secure_storage` — الان ثابت است.
3. **آمار:** تاریخچهٔ شارژ/مصرف + تخمین زمان تا خالی‌شدن (BatteryManager APIهای Android).
4. **APNs push برای iOS** — اگر بخواهیم تکرار دقیق ۲ دقیقه‌ای در background iOS داشته باشیم، فقط با سرور ممکن است (push scheduled).
5. **Light/Dark theme** — فعلاً فقط تیره.
6. **چندزبانه‌سازی** (الان فقط فارسی، با `intl`) اگر بازار هدف گسترش یابد.
7. **Widget صفحهٔ اصلی** (Android home screen / iOS widget) برای دیدن درصد بدون باز کردن اپ.

> ✅ انجام‌شده در مسیر: آیکون اختصاصی اپ (هر دو پلتفرم)، کل دستیار AI + مبینا، CI سبز هر دو job.

## ۸. سؤالات پرتکرار

**Q: چرا از `battery_plus` استفاده شده و نه `flutter_battery`؟**
`battery_plus` پلاگین رسمی (فامیل plus، نگهداری‌شده توسط fluttercommunity) است، در هر دو پلتفرم مستقر است و از SPM روی iOS هم پشتیبانی می‌کند (نسخهٔ 6.1 به بعد). نسخهٔ دقیق pin شده — دلیلش را ببخش بالا.

**Q: چرا نوتیفیکیشن سرویس `IMPORTANCE_LOW` است؟**
دائمی است و نباید آزاردهنده باشد؛ هشدارها روی کانال HIGH (صدا+لرزش) می‌روند.

**Q: اگر کاربر نوتیفیکیشن‌ها را کاملاً غیرفعال کند چه می‌شود؟**
اپ نمایش درصد و دکمهٔ انصراف را دارد؛ فقط هشدارهای push نمی‌آیند. در اولین اجرا اجازه درخواست می‌شود و در برگهٔ «چگونه کار می‌کند؟» توضیح داده شده.

**Q: Bundle ID / applicationId؟**
هر دو: `com.mobilo.mobilo`. برای ریلیز واقعی عوض کن (ساختار بالا را ببین).

## ۸.۵ دام‌های دور‌شده (درس‌های Runهای قرمز CI — حتماً بخوان)

همهٔ این‌ها با «دانش عمومی» رد نمی‌شدند؛ هرکدام با تحقیق روی مستندات/سورس رسمی حل شد:

| دام | حقیقت |
|---|---|
| `speech_to_text` 7.4.0: پارامتر `listen()` | `listenOptions:` است (نه `config` — در 7.5.0-beta تغییر کرده). **همیشه API را از سورس همان نسخهٔ پین‌شده بخوان** (شاهخ repo ممکن است جلوتر از نسخهٔ منتشرشده باشد)؛ release-commit نسخه را با `api.github.com/repos/<owner>/<repo>/commits?path=<pkg>/pubspec.yaml` پیدا کن |
| `SpeechRecognitionResult` | از کتابخانهٔ اصلی speech_to_text re-export نمی‌شود → `package:speech_to_text/speech_recognition_result.dart` + تایپ ساده (بدون پیشوند namespace) |
| `MethodChannel.setMethodCallHandler` و `Socket.destroy()` | هر دو `void` برمی‌گردانند — **`await` روی آن‌ها خطای کامپایل است** |
| `String.replaceAll` در Dart | **نه back-reference (`$1`) پشتیبانی می‌کند و نه overload تابعی** — فقط replacement literal. برای گروه‌بندی یا حذف، با چند replace literal زنجیره‌ای کار را بکن |
| `AppBar` | **constructor ثابت (const) ندارد** — `const Scaffold(appBar: AppBar())` هرگز کامپایل نمی‌شود |
| `TapGestureRecognizer` | از `flutter/material.dart` نمی‌آید — `import 'package:flutter/gestures.dart'` لازم است |
| Kotlin: `SpeechRecognizer` | متد `startListening(Intent)` است؛ `listen()` نام API پلاگین Dart است (با هم قاطی نشود) |
| Kotlin: `isNotEmpty` | **فانکشن** است: `s.isNotEmpty()` (نه `s.isNotEmpty`) |
| Kotlin: سکوت اعلان با `Notification.Builder` | `setSilent` فقط روی `NotificationCompat` (androidx) است؛ در فریمورک: `setSound(null)` |
| `Notification.CATEGORY_VOICE` | **وجود ندارد** (لیست رسمی: ALERT, CALL, EMAIL, ERROR, EVENT, LOCATION_SHARING, MESSAGE, MISSED_CALL, NAVIGATION, PROGRESS, PROMO, RECOMMENDATION, REMINDER, SERVICE, SOCIAL, STATUS, STOPWATCH, SYSTEM, TRANSPORT, VOICEMAIL, WORKOUT) |
| CI بدون حساب اپل: بیلد iOS | `flutter build ios/ipa --no-codesign` برای **دستگاه** حتی با `--no-codesign` Development Team می‌خواهد؛ **Release شبیه‌ساز اصلاً نیست** («Release mode is not supported for simulators»). راه درست: `pod install` + `xcodebuild archive -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (فازهای Flutter داخل xcodebuild همان‌طور اجرا می‌شوند) |
| `flutter test` ≠ build | فقط فایل‌های import‌شده توسط تست‌ها را کامپایل می‌کند؛ فایل‌های UI را build برای اولین بار می‌بیند. بنابراین سبز بودن تست یعنی build هم سبز نیست! |
| `flutter build ipa --no-codesign` در 3.47 | IPA تولید **نمی‌کند** (فقط xcarchive) — برای IPA از `xcodebuild -exportArchive` |
| بَرچ لوکال بین سشن‌ها | ممکن است ریست شده باشد — همیشه قبل از commit/push: `git fetch` + مقایسه با remote؛ در صورت دایورژ، rebase روی remote (فقط بعد از اطمینان که محتوای لوکال ⊇ remote) |
| شبیه‌سازی منطق با Python | semantics متفاوت است! (مثلاً `re.sub` در Python back-reference دارد ولی `replaceAll` Dart نه). شبیه‌سازی را دقیقاً با همان semantics زبانی هدف بنویس |
| احراز هویت GitHub | GH_TOKEN می‌تواند وسط سشن expire کند → از کاربر بخواه reconnect کند (قانون ۵) |

## ۹. خلاصهٔ ریسک‌ها

| ریسک | Severity | تمیز |
|---|---|---|
| محدودیت پس‌زمینهٔ iOS | inherent (سیاست اپل) | مستندسازی شده؛ در UI و README |
| ۶ ساعت dataSync در Android 16 | متوسط | watchdog خودترمیم |
| بسته شدن سرویس توسط OEM battery savers | متوسط | watchdog + دکمهٔ شروع در UI |
| `flutter_local_notifications` desugaring می‌خواهد | رفع‌شده | `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring(desugar_jdk_libs)` در `android/app/build.gradle.kts` — اگر AGP نسخهٔ بالاتر خواست، فقط عدد نسخهٔ desugar_jdk_libs را بالا ببر |
| `flutter_local_notifications` SPM ندارد | کم (فعلاً فقط WARNING) | در 3.47 build فقط هشدار می‌دهد و آن پلاگین با CocoaPods build می‌شود؛ در نسخه‌های آیندهٔ Flutter خطای سفت می‌شود — باید منتظر آپدیت پلاگین بمانیم
| VoiceAssistantService (Kotlin، SpeechRecognizer در FGS) | متوسط | **کامپایل در CI تأیید شده** (۴ خطای API در ۲۰۲۶-۰۸-۳۰ fix شد — جزئیات در بخش ۸.۵). باقی‌مانده: رفتار دستگاهی — روی OEMهای ضعیف‌تر شناسا ممکن است نداشتن → fallback خودکار به حلقهٔ Dart (status ok=false). تست دستگاهی حتماً
| flutter_contacts 2.3.1 (API v2) | کم | دقیقاً pin؛ کد با API `FlutterContacts.*` نسخهٔ 2.x نوشته شده (نسخهٔ 1.x کلاس `Contacts` دارد — مختلط نکن)
| بسته‌های AI (speech_to_text, flutter_tts, share_plus, url_launcher, path_provider, shared_preferences) | کم | همه دقیقاً pin شده‌اند و با API این نسخه‌ها نوشته شده‌اند؛ در جدول ۳ راهنمای pin/آپدیت مثل battery_plus صادق است
| تغییر آیکون‌ها در نسخه‌های Flutter | کم | `Icons.battery_horiz` در 3.47 حذف شده و با `battery_std` جایگزین شد؛ اگر خطای `Member not found: Icons.x` دیدی، `packages/flutter/lib/src/material/icons.dart` در Flutter خودت را چک کن |
| تغییر API پلاگین‌ها در آپدیت‌های major | کم | caret-pin شده؛ در build شکست می‌خورد نه در runtime |

— پایان سند —
