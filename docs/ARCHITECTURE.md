# سند معماری — Mobilo (نگهبان باتری)

نسخه: ۱٫۱ | تاریخ: ۱۴۰۵/۰۶/۰۷ | پشته: Flutter 3.47 (stable) + Android (Kotlin) + iOS (Swift)

---

## ۱. نمای کلی

Mobilo یک اپلیکیشن پایش باتری است که:

1. در هر لحظه سطح باتری و وضعیت شارژ را نمایش می‌دهد.
2. وقتی باتری به **۱۵٪** برسد و شارژر وصل نباشد، **جلسهٔ هشدار «low»** را شروع می‌کند.
3. وقتی باتری به **۹۵٪** برسد و گوشی در حال شارژ باشد، **جلسهٔ هشدار «full»** را شروع می‌کند.
4. هر جلسهٔ هشدار **اعلان را هر ۲ دقیقه تکرار می‌کند** تا زمانی که کاربر آن را **انصراف** دهد (دکمهٔ دایره‌ای وسط صفحه، اکشن «اسکیپ اعلان» روی نوتیفیکیشن، یا رفع خودکار شرط: وصل/جدا شدن شارژر).

> **محدودیت سخت‌افزاری:** هیچ اپلیکیشنی اجازهٔ قطع فیزیکی شارژ را ندارد (مهندسی سیستم‌عامل). رفتار موردنظر با «تکرار اعلان تا انصراف» نزدیک‌ترین معادل ممکن پیاده شده است.

## ۲. معماری بصری

```
┌────────────────────────────── Flutter (Dart) ──────────────────────────────┐
│                                                                             │
│  main.dart ──► AlertService.init/requestPermissions                         │
│           └──► GuardChannel (Android: start service)                        │
│           └──► AlertService.start() ──► BatteryService (battery_plus)       │
│                                                                             │
│  HomeScreen ── StreamBuilder(BatteryService.snapshots)                      │
│            └─► ValueListenable: serviceRunning / activeAlert                │
│            └─► دکمهٔ دایره‌ای «انصراف» ─► GuardChannel.dismissAlert()        │
│                                      └► AlertService.dismissAlerts()        │
└───────────────┬───────────────────────────────────────────┬─────────────────┘
                │ MethodChannel + EventChannel              │ (iOS فقط)
┌───────────────▼──────────────────────────────┐  ┌─────────▼────────────────┐
│  Android (Kotlin)                             │  │  iOS (Swift)             │
│  BatteryGuardService (Foreground Service)     │  │  AppDelegate             │
│   • پایش هر ۳۰ ثانیه + receiver شارژر       │  │   • performFetch...      │
│   • machine: low/full session + تکرار ۲دقیقه  │  │   • Background Fetch     │
│   • نوتیفیکیشن‌ها (service + alerts)          │  │   • UNUserNotification   │
│   • BootReceiver + Watchdog (آلارم inexact)   │  │   (best-effort پس‌زمینه)│
└───────────────────────────────────────────────┘  └──────────────────────────┘
```

## ۳. اجزا

### ۳.۱ Dart (بخش مشترک)

| فایل | مسئولیت |
|---|---|
| `lib/main.dart` | شروع: init اعلان‌ها، درخواست اجازه، start سرویس اندروید، start حلقهٔ آرتینگ |
| `lib/app.dart` | `MaterialApp` — تم تیره + `Directionality.rtl` برای کل UI |
| `lib/core/fa.dart` | تبدیل اعداد به فارسی (`faNum`) + تمام رشته‌های UI (`Strings`) |
| `lib/services/battery_service.dart` | Singleton روی `battery_plus` **6.2.3**: استریم `onBatteryStateChanged` + پولینگ ۵ ثانیه‌ای سطح (در 6.2.x استریم level وجود ندارد) را به یک `Stream<BatterySnapshot>` broadcast تبدیل می‌کند |
| `lib/services/guard_channel.dart` | پلی به کد بومی اندروید: `start/stop/isRunning/getActiveAlert/dismissAlert` + استریم رویدادها |
| `lib/services/alert_service.dart` | state-machine جلسات هشدار در **iOS** (تکرار ۲ دقیقه‌ای با `Timer`) + `ValueNotifier<String?> activeAlert` برای UI |
| `lib/ui/home_screen.dart` | صفحهٔ اصلی: گیج، کارت‌ها، کنترل نظارت، **overlay دکمهٔ انصراف** |
| `lib/ui/battery_gauge.dart` | `CustomPainter` حلقهٔ درصد |
| `lib/ui/about_sheet.dart` | برگهٔ توضیح رفتار و محدودیت‌ها |

### ۳.۲ Android (Kotlin)

| فایل | مسئولیت |
|---|---|
| `MainActivity.kt` | ثبت MethodChannel (`mobilo/battery_guard`) و EventChannel (`mobilo/battery_guard/events`) |
| `BatteryGuardService.kt` | **قلب سیستم**: Foreground Service با نوتیفیکیشن دائمی؛ poll ۳۰ ثانیه‌ای + receiver روی `POWER_CONNECTED/DISCONNECTED`؛ state-machine هشدارها؛ تکرار ۲ دقیقه‌ای؛ ساخت/به‌روزرسانی همهٔ نوتیفیکیشن‌ها |
| `BatteryGuardBootReceiver.kt` | ری‌استارت سرویس بعد از `BOOT_COMPLETED` |
| `BatteryGuardWatchdog.kt` | آلارم inexact تکرارشونده (هر ۳۰ دقیقه): اگر سیستم سرویس را بسته باشد (مثل محدودیت ۶ ساعتهٔ Android 16 یا Doze) دوباره روشن می‌کند |

### ۳.۳ iOS (Swift)

| فایل | مسئولیت |
|---|---|
| `AppDelegate.swift` | درخواست اجازهٔ اعلان + `registerForRemoteNotifications` + `performFetchWithCompletionHandler`: در هر بیدار شدن پس‌زمینه، اگر شرط هشدار هنوز برقرار است، اعلان را دوباره پست می‌کند (نصف «تکرار تا انصراف» در حالت suspend) |
| `Info.plist` | `UIBackgroundModes: [fetch]` |

## ۴. State Machine جلسات هشدار

```
                 ┌──────────────┐
        شروع ───►│   idle       │◄────────────────────────────┐
                 └──────┬───────┘                             │
        level≤15 و      │        level≥95 و                    │
        !charging       │        charging                      │
                        ▼                                       │
              ┌──────────────────┐        dismiss/رفع شرط       │
              │ low-session      │─────────────────────────────►│
              │  notify (2 min)  │                              │
              └──────────────────┘        (charging=true)       │
                        │                                       │
                        └───────────────────────────────────────┘
              ┌──────────────────┐        (unplugged / dismiss)
              │ full-session     │────────────────────────────► idle
              │  notify (2 min)  │
              └──────────────────┘
```

قوانین (در هر سه لایهٔ Dart/Kotlin/Swift یکسان):

| رویداد | اثر |
|---|---|
| شرط low برقرار شد و session فعال نیست | `activeAlert='low'`، اعلان فوری، شروع تکرار هر ۲ دقیقه |
| session فعال است و ≥۲ دقیقه از آخرین اعلان گذشته | تکرار اعلان (همان id → جایگزینی) |
| session فعال است و شرط برطرف شد (وصل شارژر برای low / جدا شدن برای full) | `activeAlert=null`، حذف اعلان‌ها |
| `dismiss` (دکمهٔ انصراف / اکشن اسکیپ / channel) | `activeAlert=null`، حذف اعلان‌ها |

## ۵. جریان داده و threading

### Android
- **Poll thread** (`mobilo-battery-guard`, daemon): هر ۳۰ ثانیه `checkBattery()`؛ قبل از هر چک یک `PARTIAL_WAKE_LOCK` کوتاه (۵ ثانیه)؛ زمان‌بندی تکرار ۲ دقیقه‌ای هم در همین حلقه چک می‌شود (دقت ±۳۰ ثانیه).
- **`checkBattery()`**: `@Synchronized` — تنها محل تغییر `activeAlert/lastAlertPost/lastLevel`.
- **EventSink**: فقط روی **platform (main) thread** از طریق `Handler(mainLooper).post` صدا زده می‌شود (قانون Flutter engine).
- **NotificationManager**: فراخوانی از poll thread مجاز است (IPC).
- **MethodChannel**: `start/stop/dismissAlert` کد را در **نیتِنت سرویس** (`ACTION_STOP`, `ACTION_DISMISS_ALERT`) تبدیل می‌کند تا از مسیر رسمی `startForegroundService` عبور کند (محدودیت‌های اندروید ۱۲+ برای start سرویس از background را دور می‌زند).
- **watchdog**: `AlarmManager.setInexactRepeating(ELAPSED_REALTIME, 30min)` — بدون نیاز به `SCHEDULE_EXACT_ALARM`.

### iOS
- **Foreground**: `battery_plus` (Dart) → `AlertService._onSnapshot` → `Timer(2min)` برای تکرار.
- **Background**: اپ suspend می‌شود (Timer Dart هم خواب می‌ماند)؛ `performFetch...` در هر بیدار شدن، شرط را چک و در صورت برقراری اعلان پست می‌کند. زمان‌بندی بیدار شدن دست اپل است (معمولاً هنگام شارژ + آسودگی + Wi-Fi).

## ۶. کانال‌های بین‌لایه

```
MethodChannel  mobilo/battery_guard
  Dart ──►  start | stop | isRunning | getActiveAlert | dismissAlert
EventChannel   mobilo/battery_guard/events
  Kotlin ──► { level: Int, charging: Boolean, active: "low"|"full"|"" }
              (هر تغییری در level/charging/active)
```

## ۷. نوتیفیکیشن‌ها (Android)

| id | کانال | ویژگی |
|---|---|---|
| 1001 | `battery_guard_service` (LOW) | دائمی (ongoing)، درصد زنده، اکشن‌های «باز کردن» و «توقف نظارت» |
| 2001 | `battery_guard_alerts` (HIGH، صدا+لرزش) | هشدار باتری کم؛ اکشن «اسکیپ اعلان» |
| 2002 | `battery_guard_alerts` | هشدار شارژ کامل؛ اکشن «اسکیپ اعلان» |

## ۸. اجازه‌ها

| اجازه | پلتفرم | استفاده |
|---|---|---|
| `POST_NOTIFICATIONS` | Android 13+ | اعلان‌ها (درخواست در اولین اجرا توسط `flutter_local_notifications`) |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` | Android | سرویس ۲۴ ساعته |
| `WAKE_LOCK` | Android | چک‌های ۳۰ ثانیه‌ای دقیق‌تر (lock کوتاه) |
| `RECEIVE_BOOT_COMPLETED` | Android | ری‌استارت بعد از ری‌بوت |
| اعلان (UNUserNotificationCenter) | iOS | اعلان‌های محلی |
| Background Mode `fetch` | iOS | بیدار شدن‌های پس‌زمینه |

## ۹. تصمیمات کلیدی معماری

1. **سرویس بومی (Kotlin) به‌جای plugin Dart برای پس‌زمینهٔ اندروید** — وابستگی صفر به API ناپایدار پلاگین‌های third-party؛ پایداری بالاتر در برابر OEMها؛ امکان ۲۴ ساعته بدون engine Dart.
2. **یک منبع حقیقت برای هشدار در هر پلتفرم** — اندروید: فقط سرویس بومی (جلوگیری از اعلان دوتایی)؛ iOS: فقط Dart foreground + Swift background (دوتایی فقط در لحظهٔ transition فعال/غیرفعال که با همان id اعلان بی‌خطر است).
3. **حالت‌های «جلسه» به‌جای «فلگ تکی»** — `activeAlert` به‌عنوان state نام‌دار، تکرار، dismiss و خودرفع را با یک مدل واحد توضیح می‌دهد.
4. **Action-based کنترل سرویس** (PendingIntent + startForegroundService) به‌جای مرجع استاتیک — مطابق محدودیت‌های start FGS در Android 12/14/16.
5. **watchdog inexact** — خودترمیمی بدون اجازه‌های خاص؛ در مواردی که OS start از background را مسدود کند، UI وضعیت «خاموش» را نشان می‌دهد و کاربر با یک tap روشن می‌کند.

## ۱۰. محدودیت‌های شناخته‌شده

| موضوع | جزئیات |
|---|---|
| قطع فیزیکی شارژ | غیرممکن برای اپ third-party (هر دو پلتفرم) |
| پس‌زمینهٔ iOS | زمان‌بندی بیدار شدن‌ها دست اپل است؛ تضمین ۲ دقیقه‌ای در حالت suspend وجود ندارد |
| Android 16 | سرویس `dataSync` محدودیت ۶ ساعته دارد؛ watchdog خرابی را می‌پوشاند |
| OEM battery savers | ممکن است سرویس/آلارم را محدود کنند (مخصوصاً در بازار چین) |
| دقت تکرار در اندروید | ±۳۰ ثانیه (منبع زمان‌بندی، حلقهٔ poll است) |
