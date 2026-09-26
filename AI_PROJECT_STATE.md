# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/04 (2026-09-26)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی: `1.0.7+7`
- پلتفرم هدف: **فقط اندروید** (وب/iOS خارج از محدوده)
- نوع پروژه: چت گروهی متصل به سوپرگروه تلگرام

## ۲. هدف پروژه

فراهم کردن یک اپلیکیشن اندروید اختصاصی برای گروه محدودی از کاربران،
که پیام‌ها و مدیای سوپرگروه تلگرام را در یک UI بومی و بدون نیاز به
باز کردن تلگرام به کاربران نشان دهد، با پشتیبانی کامل آفلاین، اعلان‌های
بومی FCM و پاسخ مستقیم از اعلان.

## ۳. مرحلهٔ فعلی

- **توسعهٔ فعال** روی محیط **staging**.
- ماژول مدیا (آپلود/دانلود/ذخیره‌سازی) هم اکنون بازطراحی و تأیید شد.
- آماده برای فاز بعدی توسعه.

## ۴. معماری فعلی

**کلاینت (Flutter):**
- تفکیک فیچر-محور: `auth`, `chat`, `media`, `notifications`, `core`, `update`
- مدیریت وضعیت: `ChangeNotifier` + `ListenableBuilder` (بدون Provider/Riverpod/Bloc)
- دیتابیس محلی: `sqflite` با DAO دست‌ساز (`AppDatabase`, `LocalChatDao`)
- همگام‌سازی: نشانگر ترتیبی (`sync_events` سرور + `sync_state` کلاینت)
- بلادرنگ: `WebSocket` → `Durable Object`
- مدیا: بر پایهٔ `file_id` تلگرام (بدون R2)
- پوش: FCM HTTP v1 + `flutter_local_notifications`

**سرور (Cloudflare Workers):**
- زبان: JavaScript ESM (بدون TypeScript)
- پایگاه داده: D1 (`chat-db` production، `chat-db-staging` staging)
- Realtime: Durable Object `ChatRoom`
- فایل‌ها: از طریق Telegram Bot API عبور می‌کنند
- احراز هویت: Zero-Trust، توکن نشست Bearer در D1

## ۵. محدودیت‌های مهم

- **R2 استفاده نمی‌شود** (به دلیل محدودیت کارت اعتباری در ایران).
  تمام مدیا از Telegram Bot API عبور می‌کند.
- سقف حجم هر آپلود: **۲۰ مگابایت** (مجموع در پیام چندفایلی).
- حداکثر پیوست در یک پیام: **۱۰**.
- Android فقط.
- جهت رابط: RTL (فارسی).

## ۶. محیط توسعه

- سیستم: Windows
- پوشهٔ ریشه: `C:\Users\Iranian\Documents\Temp\telegram-chat`
- Flutter SDK: **نیازمند مستندسازی** (کاربر باید `flutter --version` را ثبت کند)
- Gradle: 9.3.1
- Kotlin: 2.2.20
- Java: 17
- Android compileSdk: 36

## ۷. حالت کاری فعلی (Baseline)

- **Last verified build:** ✅ سرور روی staging مستقر شد، کلاینت روی دستگاه واقعی نصب و اجرا شد.
- **Last verified tests:** ✅ تمام ۷ سناریوی تست مدیا (چند عکس، پایداری پس از خروج، پست تکراری، چندفایلی، ویدیو، ویس، ترکیبی).
- **Known bug (blocking):** ندارد.

## ۸. باگ‌های رفع‌شدهٔ اخیر

| باگ | ریشهٔ اصلی | فایل‌های تغییر یافته |
|---|---|---|
| همه پیوست‌ها یک فایل نشان می‌دادند | نام‌گذاری بر اساس `fileName` (یکسان سمت سرور: `photo.jpg`) | normalizer/manager/local_storage |
| دکمهٔ دانلود پس از خروج برمی‌گشت | در cache-hit مسیر به DB ذخیره نمی‌شد | media_download_manager |
| پست تکراری هنگام آپلود | نبود idempotency و همزمانی optimistic + ACK | chat_repository + server |
| نوار پیشرفت پرش می‌کرد | ByteStream بدون گزارش پیشرفت | media_remote_service |

## ۹. تصمیمات معماری اخیر

**تصمیم:** نام‌گذاری فایل محلی بر اساس `attachment.id` (نه `fileName`)
- **دلیل:** جلوگیری از تصادم بین پیوست‌های مختلف
- **جایگزین‌های رد شده:** hash از `fileName + fileSize + createdAt` — پیچیدگی اضافه، و در موارد نادر (دقیقاً یکسان) هنوز تصادم ممکن است
- **نتیجه:** `{attachmentId}{ext}` — یکتا در سطح UUID سرور

**تصمیم:** دیتابیس محلی، آرایهٔ `attachments` جایگزین `attachment` شد
- **دلیل:** پشتیبانی از چند پیوست در یک پیام
- **سازگاری عقب‌رو:** getter `attachment` (first) باقی ماند

**تصمیم:** R2 کنار گذاشته شد
- **دلیل:** کاربر در ایران است و نیاز به کارت اعتباری بین‌المللی برای Cloudflare R2 وجود دارد
- **پیامد:** تمام مدیا از تلگرام رد می‌شود؛ محدودیت ۲۰MB تلگرام برای فایل‌های معمولی کافی است

## ۱۰. بدهی فنی شناخته‌شده

- **`TARGET_ARCHITECTURE.md`** هنوز از R2 حرف می‌زند و با واقعیت کد در تناقض است.
- **`schema.sql`** در ریشهٔ پروژه یک اسکیمای قدیمی و ناسازگار با migrations است. باید حذف یا آرشیو شود.
- **بدون تست خودکار:** `widget_test.dart` فقط placeholder دارد.
- **آلبوم تلگرام (Media Group):** اگر کاربر تلگرام ۳ عکس در یک آلبوم بفرستد، ۳ پیام جدا در اپ ساخته می‌شود.
- **الگوی `_ensureConnectedAndSynced()` در `build()`**: کار می‌کند اما جای زیبایی نیست.

## ۱۱. فایل‌های اخیراً تغییر یافته

**سرور:**
- `src/media/mediaController.js`

**کلاینت:**
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

## ۱۲. گام بعدی برنامه‌ریزی‌شده

- [ ] هم‌راستا کردن `TARGET_ARCHITECTURE.md` با واقعیت (حذف R2، ثبت Telegram-only)
- [ ] حذف یا آرشیو کردن `schema.sql` قدیمی از ریشه
- [ ] تعیین Flutter/Dart SDK دقیق و ثبت در این فایل
- [ ] افزودن گروه‌بندی آلبوم تلگرام (Media Group) — اختیاری
- [ ] افزودن تست‌های واحد برای `MediaLocalStorage` و `ChatRepository._mergeAttachmentsByIndex`

## ۱۳. فرضیات فعال

- کاربر تست: صاحب پروژه روی یک دستگاه اندروید واقعی.
- تعداد کاربران: محدود (گروه کوچک).
- یک ادمین (Telegram ID `122623127`) در `wrangler.toml`.

## ۱۴. قواعد کاری این پروژه

- فقط تغییرات کوچک و قابل بازگشت.
- پس از هر تغییر، `flutter analyze` باید پاک باشد.
- استقرار همیشه اول staging، سپس در صورت تأیید، production.
- R2 استفاده نمی‌شود.