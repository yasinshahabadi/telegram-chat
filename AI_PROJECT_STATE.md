# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/11 (2026-10-03)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در کد: **1.0.9+9**
- نسخهٔ منتشرشده روی GitHub: **v1.0.9**
- نسخهٔ بعدی برنامه‌ریزی‌شده: **1.0.10+10**
- پلتفرم هدف: **فقط اندروید**
- نوع پروژه: چت گروهی متصل به سوپرگروه تلگرام
- **ریپوی GitHub:** `yasinshahabadi/telegram-chat`
- **محیط استقرار فعلی:** `staging`

## ۲. هدف پروژه

اپلیکیشن اندروید اختصاصی برای گروه محدودی از کاربران، که پیام‌ها و مدیای
سوپرگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. مرحلهٔ فعلی

- **توسعهٔ فعال** روی محیط **staging**.
- ماژول مدیا، ریپلای، ری‌اکشن، حذف، read receipt، اتصال پایدار،
  divider نخوانده‌ها، و retry آپلود: **تأییدشده** (با احتیاط — به بخش
  «نقاط حساس» رجوع کنید).
- آماده برای فاز بعدی.

## ۴. معماری فعلی

**کلاینت (Flutter):**
- تفکیک فیچر-محور: `auth`, `chat`, `media`, `notifications`, `core`, `update`
- مدیریت وضعیت: `ChangeNotifier` + `ListenableBuilder`
- دیتابیس محلی: `sqflite` نسخهٔ **۳** با FK `ON DELETE CASCADE`
- همگام‌سازی: نشانگر ترتیبی + pending_actions + sync_events
- بلادرنگ: WebSocket + heartbeat (۲۵s ping / ۶۰s silence)
- مکانیزم catch-up: debounced sync روی reconnect + FCM foreground +
  app resume + timer هر ۹۰ ثانیه
- مدیا: بر پایهٔ `file_id` تلگرام (بدون R2)
- Storage داخلی: `MediaLocalStorage` با کلید `attachment.id`، LRU ۲۰۰MB

**سرور (Cloudflare Workers):**
- JavaScript ESM
- D1 + Durable Object `ChatRoom`
- Zero-Trust Session
- WebSocket heartbeat responder

## ۵. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت (مجموع چند فایل).
- حداکثر پیوست در یک پیام: ۱۰.
- Android فقط. RTL.
- FK cascade: پیام‌های با attachment، باید با UPDATE ذخیره شوند نه
  INSERT OR REPLACE (رجوع کنید به «تصمیمات معماری»).

## ۶. حالت کاری فعلی

- **Last verified build:** ✅ سرور staging + کلاینت روی دستگاه واقعی
- **Last verified release:** ✅ GitHub Release `v1.0.9`
- **Last verified tests:**
  - ماژول مدیا: ۷ سناریو
  - ماژول ریپلای: ۵ سناریو
  - ماژول ری‌اکشن + حذف: ۷ سناریو
  - heartbeat + reconnect sync: ✅
  - read receipt visibility: ✅
  - unread divider (force stop + resume): ✅
  - **media retry + edit caption: ✅ (این جلسه)**
  - **durable storage + cascade-delete fix: ✅ (فعلاً — به «نقاط حساس» رجوع کنید)**
- **Known blocking bug:** ندارد.

## ۷. دیتابیس محلی — تاریخچهٔ schema

| نسخه | تغییرات |
|---|---|
| v1 | ساخت اولیه |
| v2 | افزودن `messages.read_at` |
| v3 | افزودن ۵ ستون ریپلای مدیا به `messages` |

**بدون migration جدید در این جلسه.** `AppDatabase` هنوز v3 است.

## ۸. باگ‌های رفع‌شده (تاریخی)

### ماژول مدیا (جلسات پیشین)
- نام‌گذاری یکسان فایل‌ها → کلید بر اساس `attachment.id`
- دکمهٔ دانلود پس از خروج → تضمین ذخیره در DB
- پست تکراری هنگام آپلود → idempotency با `client_message_id`
- نوار پیشرفت پرش → progress stream واقعی

### ماژول ریپلای
- پیش‌نمایش بعد از restart می‌پرید → merge در sync
- Tap روی پیش‌نمایش کار نمی‌کرد → `Scrollable.ensureVisible`
- Thumbnail نبود → JOIN در سرور + widget جدید
- Overflow در picker ایموجی → SingleChildScrollView

### ماژول ری‌اکشن + حذف
- delete آفلاین گم می‌شد → enqueue قبل از send
- retry بعد از Force Stop نمی‌ماند → ذخیره در pending_actions
- sync پیام حذف‌شده را برمی‌گرداند → DAO guard

### جلسه (session-1)
- appVersion hardcoded → خواندن از PackageInfo
- کد مردهٔ `/api/messages` → حذف کامل
- Auto-scroll آزاردهنده → فقط وقتی نزدیک پایین + پیام جدید
- WebSocket گیر می‌کرد بدون اطلاع → heartbeat با ۲۵s/۶۰s
- پیام‌ها بعد از قطعی کوتاه نمی‌آمدند → sync در چند نقطه
- تیک خوانده‌شدن قبل از دیدن → mark-read فقط وقتی `_isNearBottom`
- پیام مدیا ناپدید می‌شد → ذخیرهٔ optimistic قبل از HTTP

### جلسه (divider)
- Divider فقط یک بار نمایش داده می‌شد → snapshot در open/resume
- اسکرول به پایین قبل از Divider → `ScrollController` با
  `initialScrollOffset` تازه
- شمارش پیام‌های قدیمی → snapshot قبل از `markAsRead`
- تیک خوانده‌نشدن تا لمس → شرط `_isNearBottom`
- Spinner کند → ۱.۳s → ۰.۵۵s

### جلسه (این session — retry + cascade)
| باگ | ریشه | راه‌حل |
|---|---|---|
| پس از ۹۰s sync، عکس دکمهٔ دانلود می‌داد | INSERT OR REPLACE روی messages → CASCADE DELETE attachments → local_path گم | UPDATE در صورت وجود ردیف؛ rename+move در صورت تغییر id |
| آپلود ناموفق، no retry | نبود مکانیزم retry | badge + دیالوگ ویرایش + retry با همان clientMessageId |
| icon ساعت می‌ماند (به‌جای قرمز) | `failUpload` فقط حافظه را تغییر می‌داد | `failUpload` async شد و DB را به‌روز می‌کند |
| فایل انتخاب‌شده در cache موقت پاک می‌شد | file_picker cache موقت | کپی به `MediaLocalStorage` قبل از HTTP |
| WS با آرایهٔ خالی پیوست‌ها پیام را پاک می‌کرد | `_mergeAttachmentsByIndex` آرایهٔ خالی برمی‌گرداند | اگر incoming خالی بود، existing حفظ می‌شود |
| فایل گم‌شده → حباب خالی | `Image.file` بدون `errorBuilder` | `errorBuilder` → placeholder با آیکون |

## ۹. فیچرهای افزوده‌شده (تاریخی)

- **مدیا:** پشتیبانی چند پیوست، نوار پیشرفت واقعی، کش LRU 200MB
- **ریپلای:** Swipe-to-Reply، Jump-to-Parent، Thumbnail، برچسب فارسی
- **ری‌اکشن:** چیپ + picker قابل اسکرول + همگام با تلگرام
- **حذف:** تأییدیه، optimistic، idempotent، آفلاین-safe
- **Update:** بررسی خودکار از GitHub Releases
- **Divider نخوانده‌ها:** snapshot + fast startup
- **Retry آپلود (این جلسه):**
  - badge قرمز «ارسال نشد» + دکمهٔ «تلاش دوباره»
  - دیالوگ ویرایش کپشن قبل از retry
  - کپی فایل به storage داخلی قبل از HTTP
  - idempotency با reuse همان `clientMessageId`

## ۱۰. تصمیمات معماری اخیر

**تصمیم:** نام فایل محلی بر اساس `attachment.id`
**تصمیم:** `attachments` آرایه‌ای، با getter سازگار `attachment`
**تصمیم:** R2 کنار گذاشته شد
**تصمیم:** اطلاعات ریپلای مدیا denormalize (۵ ستون)
**تصمیم:** retry هوشمند و آگاه از connection
**تصمیم:** delete idempotent در سرور
**تصمیم:** read receipt از طریق `sync_events`
**تصمیم:** heartbeat دوطرفه
**تصمیم:** optimistic media writes قبل از HTTP
**تصمیم:** mark-as-read فقط نزدیک پایین
**تصمیم:** Divider با `ScrollController` تازه
**تصمیم:** Snapshot ثابت per open/resume
**تصمیم:** `saveMessage` همیشه با UPDATE وقتی ردیف موجود است
- **دلیل:** جلوگیری از cascade-delete ناخواسته روی attachments
- **جایگزین‌های رد شده:** `INSERT OR IGNORE` + UPDATE دستی (پیچیده‌تر)
**تصمیم:** کپی فایل انتخابی به storage داخلی قبل از HTTP
- **دلیل:** فایل file_picker موقتی است و ممکن است پاک شود
**تصمیم:** retry با همان `clientMessageId`
- **دلیل:** idempotency در سرور — جلوگیری از پیام تکراری

## ۱۱. بدهی فنی

- **بدون تست خودکار** (فقط placeholder).
- **آلبوم تلگرام (Media Group):** هر عکس در آلبوم → پیام جدا.
- `_ensureConnectedAndSynced()` در `build()` — الگوی نازیبا.
- `/api/test-push` بدون احراز هویت (کاندید حذف).
- `_showNotificationDebugMenu` در build production نمایش داده می‌شود.
- `chat_repository.dart` در حال رشد است (~۳۵KB).
- **`ChatRoom.js` روی سرور هنوز از `INSERT` مستقیم استفاده می‌کند** —
  اگر روزی سرور اجازهٔ UPDATE پیام دهد، باید همان الگوی client را دنبال کند.

## ۱۲. فایل‌های اخیراً تغییر یافته (این جلسه)

**کلاینت (۵ فایل):**
- `mobile/lib/core/database/local_chat_dao.dart`
- `mobile/lib/features/chat/data/chat_repository.dart`
- `mobile/lib/features/chat/presentation/widgets/message_bubble.dart`
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`
- `mobile/lib/features/media/presentation/widgets/media_bubble_content.dart`

**سرور:** بدون تغییر در این جلسه.

## ۱۳. نقاط حساس (نظارت مداوم)

**⚠️ باگ cascade-delete فوراً حل شد ولی timing-sensitive است.**

لطفاً در استفادهٔ عادی ۱–۲ هفتهٔ آینده به این نشانه‌ها توجه کنید:

- دکمهٔ دانلود روی عکس‌های خودتان (آپلودشده) ظاهر شود
- پیام بعد از Force Stop دوباره بخواهد دانلود شود
- عکس در حباب خالی باشد ولی در تلگرام موجود باشد

**اگر هر کدام دیده شد:**
```powershell
adb shell run-as com.yasinshahabadi.guysgram sqlite3 /data/data/com.yasinshahabadi.guysgram/databases/telegram_chat_local_v2.db "SELECT id, message_id, local_path, is_downloaded FROM attachments ORDER BY created_at DESC LIMIT 10;"