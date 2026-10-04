# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/13 (2026-10-05)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در کد: **1.0.9+9**
- نسخهٔ منتشرشده روی GitHub: **v1.0.9**
- نسخهٔ بعدی برنامه‌ریزی‌شده: **1.0.10+10**
- پلتفرم هدف: **فقط اندروید**
- شاخهٔ جاری: **upgrade-v3**
- **ریپوی GitHub:** `yasinshahabadi/telegram-chat`
- **محیط استقرار فعلی:** `staging`

## ۲. وضعیت جاری: کاهش بدهی فنی (Refactor)

### هدف
تجزیهٔ `chat_screen.dart` (45KB) و `chat_repository.dart` (30KB) به فایل‌های کوچک‌تر.

### فازهای کامل‌شده
| Stage | محتوا | فایل‌های جدید | تست |
|---|---|---|---|
| 1 | استخراج ۵ دیالوگ + debug sheet | `presentation/dialogs/{edit_message,retry_upload,delete_confirm,logout_confirm,notification_debug_sheet}.dart` | ✅ |
| 2 | استخراج AppBar/subtitle/pinned | `presentation/widgets/{chat_app_bar,chat_status_subtitle,pinned_message_banner}.dart` | ✅ |
| 3 | استخراج لیست پیام‌ها | `presentation/widgets/chat_message_list.dart` | ✅ |
| 4 | استخراج منطق آپلود | `presentation/state/chat_upload_coordinator.dart` | ✅ |
| 5 | استخراج unread flow | `presentation/state/unread_flow_controller.dart` | ✅ |
| 5.5 | رفع ۳ باگ جانبی | (تغییر در `sync_engine.dart`, `main.dart`, `local_chat_dao.dart`) | ✅ |

### فازهای باقیمانده
| Stage | محتوا | وضعیت |
|---|---|---|
| 6 | `SocketEventDispatcher` | **آماده شروع** |
| 7 | `PendingActionQueue` + `UploadLifecycle` | در انتظار |
| 8 | حذف کد مرده + نهایی‌سازی | در انتظار |

## ۳. باگ‌های رفع‌شده در Stage 5.5 (این جلسه)

### باگ ۱ — Session در هدر truncate می‌شد (رگرسیون Stage 5)
**علامت:** کاربر در foreground پیام نمی‌گرفت پس از بازگشت از background.
**ریشه:** `'Bearer ${sessionToken.substring(0, 8)}...'` — توکن real به سرور می‌رفت truncate.
**رفع:** حذف `substring`.

### باگ ۲ — FOREIGN KEY constraint در rename پیام
**علامت:** `DatabaseException(FOREIGN KEY constraint failed)` هنگام sync پیام با `client_message_id` منطبق بر `temp_upload_*` orphan.
**ریشه:** `UPDATE attachments SET message_id = newId` قبل از `INSERT messages (id=newId)`.
**رفع:** `PRAGMA defer_foreign_keys = ON` در ابتدای transaction `saveMessage`.

### باگ ۳ — کاربر با session مرده logout نمی‌شد
**علامت:** کاربر با session invalid سرور، همچنان در اپ می‌ماند و پیام نمی‌گیرد.
**رفع:** `SyncResult.unauthorized` + `_handleUnauthorized` در `main.dart`.

## ۴. تصمیمات معماری اخیر

### تصمیم: الگوی `presentation/state/` (Stage 4-5)
- **دلیل:** جدا کردن منطق state پیچیده از UI بدون افزودن DI framework.
- **جایگزین‌های رد شده:** `ChangeNotifier` جدید (پیچیدگی)، DI (بزرگ برای این پروژه).
- **روش:** callback بین کنترلر و `ChatScreen`.
- **پیامد:** `chat_screen.dart` از 1500 خط به ~340 خط کاهش یافته.

### تصمیم: لاگ‌های debugPrint باقی می‌مانند
- **دلیل:** کاربر می‌خواهد در آینده لاگ‌های بیشتری برای دیباگ اضافه کند.
- **پیامد:** در `release` build، Flutter این لاگ‌ها را خودکار ساکت می‌کند.
- **در آینده:** لاگ‌های بیشتر در نقاط کلیدی اضافه می‌شود.

### تصمیم: `main.dart` یک وضعیت منتظر AuthStatus.resumed
- **جدول زمانی:** `_unreadFlow` و `_uploadCoordinator` در `ChatScreen.initState` ساخته می‌شوند (نه در `main`).

## ۵. بدهی فنی باقیمانده

- **بدون تست خودکار** (فقط placeholder). قرار بود Stage جداگانه باشد.
- `_ensureConnectedAndSynced()` در `build()` — الگوی نازیبا (باقی‌مانده از قبل).
- `/api/test-push` بدون احراز هویت (کاندید حذف در Stage 8).
- `_showNotificationDebugMenu` در build production نمایش داده می‌شود.
- **`ChatRoom.js` روی سرور هنوز از `INSERT` مستقیم استفاده می‌کند** (باید روزی UPDATE شود).
- `chat_repository.dart` هنوز 30KB است (Stage 6 آن را می‌شکند).
- **پاک‌سازی ۲۴ ساعته D1** روی `messages` (به درخواست کاربر حفظ می‌شود).

## ۶. فایل‌های تغییر یافته در Stage 5.5
- `mobile/lib/features/chat/data/sync_engine.dart` — رفع truncation + `unauthorized` flag + لاگ
- `mobile/lib/main.dart` — `_handleUnauthorized` در 4 نقطه
- `mobile/lib/core/database/local_chat_dao.dart` — `PRAGMA defer_foreign_keys`

## ۷. حالت کاری فعلی
- **Last verified build:** ✅ staging + دستگاه واقعی
- **Last verified tests:** همه سناریوهای Stage 5.5
- **Known blocking bug:** ندارد.

## ۸. مرحلهٔ بعد
Stage 6: `SocketEventDispatcher` — استخراج هندلر ۱۱ نوع رویداد سوکت از `chat_repository.dart`.

## ۹. نقاط حساس (نظارت مداوم)
- پس از Stage 5، چهار الگوی لاگ در `main.dart`, `sync_engine.dart`, `chat_repository.dart` باید حفظ شوند.
- الگوی callback بین `presentation/state/*` و `ChatScreen` برای Stage 6 هم استفاده می‌شود.