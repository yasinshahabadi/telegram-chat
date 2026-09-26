# معماری هدف پروژه گایزگرام (نسخه ۲ - کاملاً اختصاصی اندروید)
# TARGET ARCHITECTURE SPECIFICATION (v2 - Android Only)

> **آخرین بازبینی:** 1405/07/04 (2026-09-26)
>
> **تغییرات این بازبینی نسبت به نسخه قبلی:**
> - **حذف کامل R2** (به دلیل محدودیت دسترسی جغرافیایی). تمام مدیا از Telegram Bot API عبور می‌کند.
> - تصحیح زبان بک‌اند به **JavaScript ESM** (نه TypeScript).
> - تصحیح کتابخانه دیتابیس محلی به **sqflite** (نه Drift).
> - هم‌راستا کردن ساختار پوشه‌های کلاینت با واقعیت کد.

## ۱. نمای کلی سیستم و جریان داده (System Overview)
- **پلتفرم کلاینت:** منحصراً سیستم‌عامل اندروید توسعه‌یافته با Flutter.
- **بک‌اند:** Cloudflare Workers (JavaScript ESM، بدون TypeScript).
- **پایگاه داده رابطه‌ای سرور:** Cloudflare D1 با جدول‌های نرمال، ایندکس‌های بهینه و مایگریشن‌های نسخه‌دار عددی در `migrations/0001_*` و بعد.
- **لایه بلادرنگ زنده:** Cloudflare Durable Objects با استفاده از WebSocket Hibernation API (`ctx.acceptWebSocket`) جهت کمینه‌سازی هزینه و مصرف منابع.
- **ذخیره‌سازی چندرسانه‌ای:** **Telegram Bot API** به‌عنوان منبع اصلی مدیا.
  - آپلود کلاینت → ورکر → Telegram → ذخیرهٔ `telegram_file_id` در D1.
  - دانلود کلاینت → ورکر → `getFile` تلگرام → استریم مستقیم به کلاینت.
  - **R2 استفاده نمی‌شود.** این تصمیم به دلیل عدم دسترسی به کارت اعتباری بین‌المللی در ایران گرفته شده است. کد `mediaController.js` با Telegram-only سازگار است.
  - محدودیت عملی: هر فایل حداکثر ۲۰ مگابایت (سقف دانلود Telegram Bot API).
  - حداکثر ۱۰ پیوست در یک پیام.
- **سیستم پیام‌رسانی تلگرام:** اتصال امن وب‌هوک و Bot API به سوپرگروه اختصاصی تلگرام.
- **سیستم اعلان‌ها (Push Notifications):** Firebase Cloud Messaging (FCM) HTTP v1 با اولویت بالا، آیکون سفارشی، و قابلیت پاسخ مستقیم از نوتیفیکیشن (Direct Reply / RemoteInput).

## ۲. امنیت بدون اعتماد (Zero-Trust Security Model)
۱. **اعتبارسنجی وب‌هوک تلگرام:**
   - تمام درخواست‌های ورودی به `/api/telegram-webhook` باید هدر `X-Telegram-Bot-Api-Secret-Token` را همراه داشته باشند.
   - هر درخواستی که فاقد سکرت توکن معتبر باشد بلافاصله با کد ۴۰۳ رد می‌شود.
۲. **عدم اعتماد به هویت کلاینت (No Client-Side Identity Trust):**
   - کلاینت هرگز `userId`، نقش کاربری (`role`)، یا وضعیت ادمین بودن را برای سرور تعیین نمی‌کند.
   - هویت صرفاً از توکن نشست معتبر (Session Bearer Token) استخراج می‌شود.
۳. **مدیریت نشست و دستگاه‌ها (Sessions & Devices):**
   - هر کاربر می‌تواند چندین دستگاه ثبت‌شده در جدول `devices` داشته باشد.
   - توکن‌های نشست دارای زمان انقضا (`expires_at`) و قابلیت ابطال آنی (`revoked_at`) هستند.
۴. **احراز هویت وب‌سوکت:**
   - ارتقای اتصال به وب‌سوکت در اندپوینت `/api/ws` مستلزم ارسال توکن نشست معتبر در هدر یا کوئری است.

## ۳. معماری آفلاین و موتور همگام‌سازی (Offline-First & Sync Engine)
۱. **پایگاه داده محلی کلاینت:**
   - SQLite بومی از طریق پکیج `sqflite` (جداول محلی: `messages`, `attachments`, `reactions`, `pending_actions`, `sync_state`).
   - نمایش فوری پیام‌ها از روی دیتابیس محلی، بدون معطلی برای پاسخ شبکه.
۲. **شناسه یکتای سمت کلاینت (Idempotency Key):**
   - هر پیام خروجی کلاینت دارای یک `client_message_id` با فرمت UUIDv4 است.
   - در صورت قطع اینترنت و تلاش‌های مجدد (Retry)، سرور پیام تکراری ثبت نخواهد کرد.
۳. **نشانگر سرور (Sequential Server Cursor):**
   - تمام رویدادها در جدول `sync_events` با یک `cursor` ترتیبی فزاینده ثبت می‌شوند.
   - کلاینت پس از اتصال مجدد، با ارسال `last_cursor` رویدادهای از دست رفته را واکشی می‌کند.

## ۴. استراتژی دوگانه سوکت و نوتیفیکیشن (WebSocket + FCM)
- **حالت Foreground:** ارتباط بلادرنگ سوکت با سرور فعال است؛ پیام‌ها آنی دریافت و در دیتابیس محلی ذخیره می‌شوند.
- **حالت Background / Terminated:**
  - هیچ سرویس فورگراند برای باز نگه داشتن سوکت اجرا نمی‌شود.
  - سرور با تشخیص عدم حضور سوکت، یک FCM Data Message با اولویت بالا ارسال می‌کند.
  - اپ اعلان بومی را نمایش می‌دهد و امکان پاسخ سریع (Direct Reply) بدون باز کردن اپ را فراهم می‌سازد.

## ۵. معماری ماژولار کلاینت فلاتر
ساختار واقعی پوشه `mobile/lib/`:

- `config.dart`: پیکربندی آدرس سرور و بات‌یوزرنیم.
- `main.dart`: راه‌اندازی، تزریق وابستگی، مدیریت چرخه عمر اپ.
- `core/`:
  - `core/database/`: `app_database.dart`, `local_chat_dao.dart`
  - `core/network/`: `network_monitor.dart`
  - `core/update/`: `update_service.dart`, `update_dialog.dart`
- `features/auth/`:
  - `data/`: `auth_local_storage.dart`, `auth_remote_service.dart`, `auth_repository.dart`
  - `domain/models/`: `auth_user.dart`
  - `presentation/screens/`: `login_screen.dart`, `pending_approval_screen.dart`
- `features/chat/`:
  - `data/`: `chat_repository.dart`, `chat_websocket_client.dart`, `sync_engine.dart`
  - `domain/models/`: `chat_message_model.dart`
  - `presentation/screens/`: `chat_screen.dart`
  - `presentation/widgets/`: `chat_input_bar.dart`, `message_bubble.dart`, `user_avatar.dart`
- `features/media/`:
  - `data/`: `media_download_manager.dart`, `media_local_storage.dart`, `media_remote_service.dart`, `voice_record_service.dart`
  - `domain/models/`: `media_attachment_model.dart`
  - `presentation/screens/`: `media_viewer_screen.dart`, `video_player_screen.dart`, `storage_settings_screen.dart`
  - `presentation/widgets/`: `media_bubble_content.dart`
- `features/notifications/`:
  - `data/`: `firebase_messaging_service.dart`, `notification_service.dart`

> **توجه:** پوشه‌های `app/` و `features/sync/` که در نسخه اول این سند ذکر شده بودند، در کد واقعی وجود ندارند. مسئولیت‌های آن‌ها به `main.dart` و `features/chat/data/sync_engine.dart` منتقل شده است.

## ۶. تصمیمات ردشده (برای مرجع آینده)
- **Cloudflare R2:** به دلیل نیاز به کارت اعتباری بین‌المللی برای استفاده، رد شد. Telegram به‌عنوان ذخیره‌ساز اصلی انتخاب شد.
- **Drift (ORM):** به نفع `sqflite` رد شد — پیچیدگی code generation برای این اندازه پروژه توجیه نداشت.
- **TypeScript:** به نفع JavaScript ESM رد شد — جلوگیری از پیچیدگی build step در Cloudflare Workers.