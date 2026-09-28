# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/06 (2026-09-28)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در توسعه: **1.0.8+8** (منتشرشده روی GitHub)
- نسخهٔ بعدی برنامه‌ریزی‌شده: **1.0.9+9**
- پلتفرم هدف: **فقط اندروید**
- نوع پروژه: چت گروهی متصل به سوپرگروه تلگرام
- **ریپوی GitHub:** `yasinshahabadi/telegram-chat`
- **آخرین Release:** `v1.0.8`
- **محیط استقرار فعلی:** `staging` (تصمیم کاربر: production فعلاً استفاده نمی‌شود)

## ۲. هدف پروژه

اپلیکیشن اندروید اختصاصی برای گروه محدودی از کاربران، که پیام‌ها و مدیای
سوپرگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. مرحلهٔ فعلی

- **توسعهٔ فعال** روی محیط **staging**.
- ماژول مدیا، ریپلای، ری‌اکشن، حذف، read receipt، و اتصال پایدار: **تأیید شده**.
- آماده برای فاز بعدی (Divider نخوانده‌ها).

## ۴. معماری فعلی

**کلاینت (Flutter):**
- تفکیک فیچر-محور: `auth`, `chat`, `media`, `notifications`, `core`, `update`
- مدیریت وضعیت: `ChangeNotifier` + `ListenableBuilder`
- دیتابیس محلی: `sqflite` نسخهٔ **۳**
- همگام‌سازی: نشانگر ترتیبی + pending_actions + sync_events
- بلادرنگ: WebSocket + heartbeat (25s ping / 60s silence timeout)
- مکانیزم catch-up: debounced sync روی reconnect + FCM foreground + app resume + timer هر ۹۰ ثانیه
- مدیا: بر پایهٔ `file_id` تلگرام (بدون R2)

**سرور (Cloudflare Workers):**
- JavaScript ESM
- D1 + Durable Object `ChatRoom`
- Zero-Trust Session
- WebSocket heartbeat responder

## ۵. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت.
- حداکثر پیوست در یک پیام: ۱۰.
- Android فقط. RTL.

## ۶. حالت کاری فعلی

- **Last verified build:** ✅ سرور staging + کلاینت روی دستگاه واقعی
- **Last verified tests (session-1 + divider):**
  - heartbeat + reconnect sync: ✅
  - read receipt visibility: ✅
  - media upload persistence: ✅
  - unread divider (force stop + resume): ✅
  - mark-read only when near bottom: ✅
  - divider never repeats within session: ✅
  - fast startup (0.55s min): ✅
- **Known blocking bug:** ندارد.

## ۷. دیتابیس محلی — تاریخچهٔ schema

| نسخه | تغییرات |
|---|---|
| v1 | ساخت اولیه |
| v2 | افزودن `messages.read_at` |
| v3 | افزودن ۵ ستون ریپلای مدیا به `messages` |

**نکته:** برای تغییرات این جلسه، migration لازم نبود. read receipt از جدول `message_reads` سرور می‌آید و به `read_at` محلی map می‌شود.

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

### جلسهٔ جاری (session-1)
- **appVersion hardcoded** → خواندن از PackageInfo
- **کد مردهٔ `/api/messages`** → حذف کامل
- **Auto-scroll آزاردهنده** → فقط وقتی نزدیک پایین + پیام جدید
- **WebSocket گیر می‌کرد بدون اطلاع** → heartbeat با ۲۵s ping / ۶۰s silence
- **پیام‌ها بعد از قطعی کوتاه نمی‌آمدند** → sync روی reconnect/FCM/resume/timer
- **تیک خوانده‌شدن قبل از دیدن** → mark-read فقط وقتی `_isNearBottom`
- **پیام مدیا ناپدید می‌شد** → ذخیرهٔ optimistic در DB قبل از HTTP + حفظ در `loadLocalMessages`

### جلسه ۲ (این session)
| باگ | ریشه | راه‌حل |
|---|---|---|
| Divider فقط یک بار نمایش داده می‌شد | snapshot در حین session بازنشانی می‌شد | snapshot فقط در open/resume گرفته می‌شود |
| اسکرول به پایین قبل از Divider | ScrollController با offset=0 ساخته می‌شد | scrollController nullable + initialScrollOffset محاسبه‌شده |
| شمارش پیام‌های قدیمی | `_lastReadAt` زودتر از `_computeFirstUnread` به‌روز می‌شد | snapshot قبل از `markAsRead` |
| تیک خوانده‌نشدن تا لمس کاربر | `_maybeScheduleReadForVisibleMessages` فقط در اسکرول صدا زده می‌شد | شرط `_isNearBottom` در `_onChatUpdate` |
| تیک ناخواسته در حین session | Divider دوباره در `_onChatUpdate` فعال می‌شد | Divider فقط در open/resume |
| Spinner کند | 1.3s حداقل انتظار | 0.55s (settleDelay 400ms + reveal 150ms) |

## ۹. فیچرهای افزوده‌شده (تاریخی)

- **مدیا:** پشتیبانی چند پیوست، نوار پیشرفت واقعی، کش LRU 200MB
- **ریپلای:** Swipe-to-Reply، Jump-to-Parent، Thumbnail مدیا، برچسب فارسی
- **ری‌اکشن:** چیپ + picker قابل اسکرول + همگام با تلگرام
- **حذف:** تأییدیه، optimistic، idempotent، آفلاین-safe
- **Update:** بررسی خودکار از GitHub Releases

### Divider پیام‌های نخوانده
- Widget `UnreadDivider` با گرادیان افقی + برچسب فارسی + تعداد
- Snapshot لحظهٔ باز شدن/Resume
- پنجرهٔ داینامیک initial load: ۴۰۰ms + ۱.۲s تمدید + سقف ۴s
- ورود اول: `ScrollController` با `initialScrollOffset` (بدون flash پایین)
- Resume: اسکرول انیمیت‌شده با `ensureVisible` به snapshot
- تأخیر ۱۵۰ms بعد از بسته شدن پنجره، سپس نمایش
- Fade خودکار بعد از ۵ ثانیه
- Divider در همان session هرگز تکرار نمی‌شود
- Mark-read فقط وقتی کاربر نزدیک پایین است

## ۱۰. تصمیمات معماری اخیر

**تصمیم:** نام فایل محلی بر اساس `attachment.id` (نه fileName)
**تصمیم:** `attachments` آرایه‌ای، با getter سازگار `attachment`
**تصمیم:** R2 کنار گذاشته شد
**تصمیم:** اطلاعات ریپلای مدیا denormalize شده روی `messages` (۵ ستون)
**تصمیم:** retry هوشمند و آگاه از connection (نه exponential backoff)
**تصمیم:** delete idempotent در سرور
**تصمیم:** read receipt از طریق `sync_events` برای کاربران آفلاین
**تصمیم:** heartbeat دوطرفه (ping/pong) برای تشخیص قطعی پنهان
**تصمیم:** optimistic media writes قبل از HTTP (نه بعد)
**تصمیم:** mark-as-read فقط وقتی کاربر نزدیک پایین است
**تصمیم:** Divider نخوانده‌ها به‌جای `ListView` offset، با `ScrollController` تازه
- **دلیل:** جلوگیری از نمایش لحظه‌ای پایین لیست قبل از اسکرول به Divider
- **جایگزین‌های رد شده:** `jumpTo` بعد از اولین فریم (flash دیده می‌شد)

**تصمیم:** Snapshot ثابت per open/resume (نه پویا در حین session)
- **دلیل:** پیام‌های جدید در حین خواندن، Divider را جابه‌جا نکنند
- **الگو:** مطابق `noma_chat` / `stream_chat_flutter`

## ۱۱. بدهی فنی

- **بدون تست خودکار** (فقط placeholder).
- **آلبوم تلگرام (Media Group):** هر عکس در آلبوم → پیام جدا.
- `_ensureConnectedAndSynced()` در `build()` — الگوی کارآمد ولی زیبا نیست.
- **Divider نخوانده‌ها:** هنوز پیاده‌سازی نشده (جلسهٔ بعدی).
- `/api/test-push` بدون احراز هویت (کاندید حذف یا محافظت).
- `_showNotificationDebugMenu` در build production نمایش داده می‌شود.
- `messagesController.js` حذف شد (تأییدشده).
- `chat_repository.dart` در حال رشد است (~۳۵KB). در جلسه‌ای جداگانه می‌توان
  به فایل‌های کوچک‌تر تقسیم کرد (`read_receipts.dart`, `reactions.dart`, ...).

## ۱۲. فایل‌های اخیراً تغییر یافته (این جلسه)

**سرور:**
- `src/realtime/ChatRoom.js` (ping/pong + messages_read_batch)
- `src/index.js` (حذف route `/api/messages`)
- `src/chat/messagesController.js` (حذف شد)

**کلاینت:**
- `mobile/lib/features/auth/data/auth_remote_service.dart`
- `mobile/lib/features/chat/data/chat_websocket_client.dart`
- `mobile/lib/features/chat/data/chat_repository.dart`
- `mobile/lib/features/chat/data/sync_engine.dart`
- `mobile/lib/core/database/local_chat_dao.dart`
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`
- `mobile/lib/features/notifications/data/firebase_messaging_service.dart`
- `mobile/lib/main.dart`

## ۱۳. گام بعدی برنامه‌ریزی‌شده

**جلسه بعدی — پیشنهاد:**
- [ ] تست FCM در پس‌زمینه روی OEMهای مختلف (Xiaomi، Huawei)
- [ ] بستن `/api/test-push` (بدون احراز هویت)
- [ ] پنهان‌سازی پنل دیباگ در release build
- [ ] افزودن migrations به `[env.staging]` در wrangler.toml
- [ ] تعیین نسخهٔ Flutter/Dart دقیق
- [ ] گروه‌بندی آلبوم تلگرام (Media Group)
- [ ] تست واحد برای `LocalChatDao` و `SyncEngine`
- [ ] انتشار v1.0.9 با همه تغییرات این دو جلسه

**جلسه‌های بعدی (اولویت‌دار):**
- [ ] بررسی و بستن `/api/test-push`
- [ ] پنهان‌سازی پنل دیباگ در build production
- [ ] افزودن migrations به `[env.staging]` در wrangler.toml
- [ ] تعیین نسخهٔ Flutter/Dart دقیق
- [ ] بررسی FCM در پس‌زمینه روی OEMهای مختلف
- [ ] گروه‌بندی آلبوم تلگرام (Media Group)
- [ ] تست واحد برای بخش‌های حساس

**کنسل‌شده (تصمیم کاربر):**
- ~~گروه‌بندی اعلان‌ها + preview پیشرفته~~ (در جلسهٔ فعلی لغو شد)

## ۱۴. فرضیات فعال

- یک ادمین (Telegram ID `122623127`) در `wrangler.toml`.
- تعداد کاربران: محدود.
- جهت رابط: RTL (فارسی).
- محیط استقرار: `staging` تا اطلاع ثانوی.

## ۱۵. قواعد کاری این پروژه

- فقط تغییرات کوچک و قابل بازگشت.
- `flutter analyze` باید پاک باشد.
- استقرار: سرور اول، کلاینت بعد (برای تغییرات protocol).
- R2 استفاده نمی‌شود.
- تست روی دستگاه واقعی.
- پس از هر فاز، `AI_PROJECT_STATE.md` به‌روز می‌شود.