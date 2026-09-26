# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/04 (2026-09-26)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی: `1.0.7+7`
- پلتفرم هدف: **فقط اندروید**
- نوع پروژه: چت گروهی متصل به سوپرگروه تلگرام

## ۲. هدف پروژه

اپلیکیشن اندروید اختصاصی برای گروه محدودی از کاربران، که پیام‌ها و مدیای
سوپرگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. مرحلهٔ فعلی

- **توسعهٔ فعال** روی محیط **staging**.
- ماژول مدیا + ریپلای با پشتیبانی کامل مدیا: **تأیید شد**.
- آماده برای فاز بعدی.

## ۴. معماری فعلی

**کلاینت (Flutter):**
- تفکیک فیچر-محور: `auth`, `chat`, `media`, `notifications`, `core`, `update`
- مدیریت وضعیت: `ChangeNotifier` + `ListenableBuilder`
- دیتابیس محلی: `sqflite` نسخهٔ **۳**
- همگام‌سازی: نشانگر ترتیبی (`sync_events` سرور + `sync_state` کلاینت)
- بلادرنگ: `WebSocket` → `Durable Object`
- مدیا: بر پایهٔ `file_id` تلگرام (بدون R2)

**سرور (Cloudflare Workers):**
- JavaScript ESM
- D1 + Durable Object `ChatRoom`
- احراز هویت Zero-Trust

## ۵. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری در ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت.
- حداکثر پیوست در یک پیام: ۱۰.
- Android فقط. RTL.

## ۶. حالت کاری فعلی

- **Last verified build:** ✅ سرور staging + کلاینت روی دستگاه واقعی.
- **Last verified tests:**
  - ماژول مدیا: ۷ سناریو پاس
  - ماژول ریپلای: ۵ سناریو پاس
- **Known blocking bug:** ندارد.

## ۷. دیتابیس محلی — تاریخچهٔ schema

| نسخه | تغییرات |
|---|---|
| v1 | ساخت اولیه: messages, attachments, reactions, pending_actions, sync_state |
| v2 | افزودن `messages.read_at` |
| v3 | افزودن ۵ ستون ریپلای مدیا به `messages`: `reply_to_media_type`, `reply_to_attachment_id`, `reply_to_telegram_file_id`, `reply_to_file_name`, `reply_to_duration` |

## ۸. باگ‌های رفع‌شده

### ماژول مدیا
| باگ | ریشه | فایل‌های تغییر یافته |
|---|---|---|
| همه پیوست‌ها یک فایل نشان می‌دادند | نام‌گذاری بر اساس fileName (یکسان: photo.jpg) | local_storage/manager/remote_service |
| دکمهٔ دانلود پس از خروج برمی‌گشت | cache-hit مسیر را در DB ذخیره نمی‌کرد | media_download_manager |
| پست تکراری هنگام آپلود | نبود idempotency | chat_repository + server |
| نوار پیشرفت پرش می‌کرد | ByteStream بدون گزارش | media_remote_service |

### ماژول ریپلای
| باگ | ریشه | راه‌حل |
|---|---|---|
| پیش‌نمایش بعد از restart می‌پرید | sync جایگزینی کورکورانه می‌کرد | merge در sync_engine + payload غنی سرور |
| tap روی پیش‌نمایش کار نمی‌کرد | پیاده‌سازی نشده بود | GlobalKey + Scrollable.ensureVisible + highlight |
| thumbnail مدیا نبود | پیاده‌سازی نشده بود | ReplyThumbnail widget + JOIN در سرور |

## ۹. فیچرهای افزوده‌شده

### ماژول مدیا
- پشتیبانی چند پیوست در یک پیام (گرید ۲ ستونه)
- نوار پیشرفت واقعی از stream

### ماژول ریپلای
- **Swipe-to-Reply** (کشیدن چپ→راست) با فیدبک لمسی
- **Jump-to-Parent** با هایلایت کهربایی ~۱.۵ ثانیه
- **Preview پایدار** پس از Force Stop و روی دستگاه‌های دیگر
- **Thumbnail مدیا** در پیش‌نمایش (کش → شبکه → آیکون)
- **برچسب فارسی** نوع مدیا: عکس / ویدیو / پیام صوتی / صدا / فایل
- **زنجیرهٔ ریپلای** (A → B → C) کاملاً پیمایش‌پذیر

## ۱۰. تصمیمات معماری اخیر

**تصمیم:** نام‌گذاری فایل محلی بر اساس `attachment.id` (نه fileName)
- **جایگزین‌های رد شده:** hash از fileName+size+createdAt
- **نتیجه:** `{attachmentId}{ext}`

**تصمیم:** دیتابیس محلی، آرایهٔ `attachments` جایگزین `attachment` شد
- **سازگاری عقب‌رو:** getter `attachment` (first)

**تصمیم:** R2 کنار گذاشته شد (محدودیت کارت اعتباری)

**تصمیم:** اطلاعات ریپلای مدیا روی خود پیام denormalize شد
- **دلیل:** اجتناب از JOIN در زمان render روی کلاینت
- **هزینه:** ۵ ستون اضافی؛ در عوض هر پیام بدون query اضافی رندر می‌شود

## ۱۱. بدهی فنی

- `Guides/TARGET_ARCHITECTURE.md` — **اصلاح شد** در این فاز.
- `.gitignore` — **اصلاح شد** (migrations tracked).
- **بدون تست خودکار** (فقط placeholder در widget_test.dart).
- **آلبوم تلگرام (Media Group):** هر عکس در آلبوم یک پیام جدا می‌سازد.
- `_ensureConnectedAndSynced()` در `build()` — الگوی کارآمد ولی زیبا نیست.
- **`sync_engine.dart` merge پیچیده شده:** اگر ستون جدیدی اضافه شود، باید این فایل هم به‌روز شود. در آینده می‌توان به یک متد `mergeFrom` روی مدل منتقل کرد.

## ۱۲. فایل‌های اخیراً تغییر یافته

### فاز «رفع باگ‌های مدیا + چند پیوست»
- `src/media/mediaController.js`
- `mobile/lib/features/chat/domain/models/chat_message_model.dart`
- `mobile/lib/features/chat/data/chat_repository.dart`
- `mobile/lib/features/chat/data/sync_engine.dart`
- `mobile/lib/features/media/data/media_local_storage.dart`
- `mobile/lib/features/media/data/media_remote_service.dart`
- `mobile/lib/features/media/data/media_download_manager.dart`
- `mobile/lib/features/media/presentation/widgets/media_bubble_content.dart`
- `mobile/lib/features/chat/presentation/widgets/message_bubble.dart`
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`
- `mobile/lib/main.dart`

### فاز «ریپلای کامل»
- `src/realtime/ChatRoom.js`
- `src/telegram/normalizer.js`
- `src/media/mediaController.js`
- `mobile/lib/core/database/app_database.dart`
- `mobile/lib/core/database/local_chat_dao.dart`
- `mobile/lib/features/chat/domain/models/chat_message_model.dart`
- `mobile/lib/features/chat/data/sync_engine.dart`
- `mobile/lib/features/chat/data/chat_repository.dart`
- `mobile/lib/features/chat/presentation/widgets/reply_thumbnail.dart` **(جدید)**
- `mobile/lib/features/chat/presentation/widgets/swipe_to_reply.dart` **(جدید در فاز قبل)**
- `mobile/lib/features/chat/presentation/widgets/message_bubble.dart`
- `mobile/lib/features/chat/presentation/widgets/chat_input_bar.dart`
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`

### پاک‌سازی‌ها
- `schema.sql` (حذف شد)
- `.gitignore` (اصلاح: migrations tracked)
- `Guides/TARGET_ARCHITECTURE.md` (هم‌راستا با واقعیت)

## ۱۳. گام بعدی برنامه‌ریزی‌شده

- [ ] تعیین و ثبت نسخهٔ Flutter/Dart دقیق در این فایل
- [ ] تصمیم درباره گروه‌بندی آلبوم تلگرام (Media Group)
- [ ] افزودن تست واحد برای `MediaLocalStorage`, `ChatRepository._mergeAttachmentsByIndex`, `SyncEngine._applyEventToLocalDatabase`
- [ ] بررسی FCM در پس‌زمینه (تست روی گوشی‌های مختلف OEM)
- [ ] افزودن سیستم ری‌اکشن در UI (server دارد، UI ندارد)
- [ ] بهبود `_ensureConnectedAndSynced` (نقل به مکانی خارج از build)

## ۱۴. فرضیات فعال

- یک ادمین (Telegram ID `122623127`) در `wrangler.toml`.
- تعداد کاربران: محدود.
- جهت رابط: RTL (فارسی).

## ۱۵. قواعد کاری این پروژه

- فقط تغییرات کوچک و قابل بازگشت.
- پس از هر تغییر، `flutter analyze` باید پاک باشد.
- استقرار: اول staging، سپس در صورت تأیید production.
- R2 استفاده نمی‌شود.
- تست روی دستگاه واقعی، نه شبیه‌ساز.