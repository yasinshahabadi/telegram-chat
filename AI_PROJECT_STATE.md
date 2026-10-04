# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/14 (2026-10-05)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در کد: **1.0.9+9**
- نسخهٔ منتشرشده روی GitHub: **v1.0.9**
- نسخهٔ بعدی برنامه‌ریزی‌شده: **1.0.10+10**
- پلتفرم هدف: **فقط اندروید**
- شاخهٔ جاری: **upgrade-v3**
- ریپوی GitHub: `yasinshahabadi/telegram-chat`
- محیط استقرار فعلی: `staging`

## ۲. هدف پروژه

اپلیکیشن اندروید اختصاصی برای گروه محدودی از کاربران، که پیام‌ها و مدیای
سوپرگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. وضعیت جاری: Refactor کامل شد ✅

### هدف
تجزیهٔ `chat_screen.dart` (~1500 خط) و `chat_repository.dart` (~750 خط)
به فایل‌های کوچک‌تر برای کاهش بدهی فنی و افزایش قابلیت نگهداری.

### فازهای کامل‌شده (همه در یک جلسه)
| Stage | محتوا | فایل‌های جدید |
|---|---|---|
| 1 | استخراج ۵ دیالوگ + debug sheet | 5 فایل در `presentation/dialogs/` |
| 2 | استخراج AppBar/subtitle/pinned | 3 فایل در `presentation/widgets/` |
| 3 | استخراج لیست پیام‌ها | `chat_message_list.dart` |
| 4 | استخراج منطق آپلود | `state/chat_upload_coordinator.dart` |
| 5 | استخراج unread flow | `state/unread_flow_controller.dart` |
| 5.5 | رفع ۳ باگ جانبی | (تغییر در `sync_engine`, `main`, `local_chat_dao`) |
| 6 | استخراج سوکت | `socket_event_dispatcher.dart` |
| 6.5 | رفع باگ duplicate attachment | (تغییر در `local_chat_dao`) |
| 7 | استخراج صف + آپلود + رفع باگ ack | `pending_action_queue.dart`, `upload_lifecycle.dart` |
| 8 | پاک‌سازی کد مرده | (فقط `chat_screen.dart`) |

### نتیجهٔ metrics
| فایل | قبل | بعد |
|---|---|---|
| `chat_screen.dart` | ~۱۵۰۰ خط | ~۳۳۰ خط |
| `chat_repository.dart` | ~۷۵۰ خط | ~۳۰۰ خط |
| `socket_event_dispatcher.dart` | — | ~۳۰۰ خط |
| `upload_lifecycle.dart` | — | ~۳۵۰ خط |
| `pending_action_queue.dart` | — | ~۱۸۰ خط |
| `unread_flow_controller.dart` | — | ~۳۲۰ خط |
| `chat_upload_coordinator.dart` | — | ~۲۸۰ خط |

**فایل‌های جدید کل:** ۱۳ فایل جدید.

## ۴. معماری فعلی (کلاینت)

### Presentation Layer
presentation/
├── screens/chat_screen.dart (root StatefulWidget, ~330 خط)
├── widgets/
│ ├── chat_app_bar.dart (static factory برای AppBar)
│ ├── chat_status_subtitle.dart (subtitle خود AnimatedBuilder دارد)
│ ├── pinned_message_banner.dart (banner خود AnimatedBuilder دارد)
│ ├── chat_message_list.dart (ListView + empty/loading state)
│ ├── message_bubble.dart (حباب پیام + context menu)
│ ├── chat_input_bar.dart (input + voice recording)
│ ├── reaction_bar.dart (chips + picker)
│ ├── reply_thumbnail.dart (thumbnail در reply)
│ ├── swipe_to_reply.dart (swipe gesture wrapper)
│ ├── unread_divider.dart (divider animation)
│ ├── user_avatar.dart (avatar + online badge)
│ └── media_bubble_content.dart (media display)
├── dialogs/
│ ├── edit_message_dialog.dart (static show → String?)
│ ├── retry_upload_dialog.dart (static show → String?)
│ ├── delete_confirm_dialog.dart (static show → bool)
│ ├── logout_confirm_dialog.dart (static show → bool)
│ └── notification_debug_sheet.dart (static show)
└── state/
├── chat_upload_coordinator.dart (pick/voice/upload/retry)
└── unread_flow_controller.dart (divider + mark-read)

### Data Layer
data/
├── chat_repository.dart (ChangeNotifier — state root, ~300 خط)
├── socket_event_dispatcher.dart (12 نوع رویداد سوکت)
├── upload_lifecycle.dart (چرخهٔ ساخت/نهایی/retry پیام)
├── pending_action_queue.dart (صف + scheduling retry)
├── chat_websocket_client.dart (WS + heartbeat 25s/60s)
└── sync_engine.dart (cursor-based sync + لاگ)


### الگوی معماری
- **State root:** `ChatRepository extends ChangeNotifier`
- **State controllers:** کلاس‌های stateless با callback به root (`UnreadFlowController`, `ChatUploadCoordinator`).
- **Data helpers:** کلاس‌های مستقل با callback (`SocketEventDispatcher`, `UploadLifecycle`, `PendingActionQueue`).
- **هیچ DI framework، هیچ code generation، هیچ abstraction اضافی.**

## ۵. سرور (Cloudflare Workers)

بدون تغییر این جلسه. نکات مهم:
- D1 + Durable Object `ChatRoom`.
- Zero-Trust Session.
- `/api/sync` بر پایه cursor.
- مدیا فقط از Telegram Bot API (بدون R2).
- `ChatRoom.js` هنوز از `INSERT` مستقیم استفاده می‌کند (برای آینده یادداشت شود).

## ۶. باگ‌های رفع‌شده در این جلسه

| # | باگ | ریشه | رفع |
|---|---|---|---|
| 1 | `_dependents.isEmpty` در دیالوگ ویرایش | `controller.dispose()` زودهنگام در Stage 1 | حذف dispose |
| 2 | پیام در foreground بعد از بازگشت از background نمی‌آمد | `Bearer ${token.substring(0,8)}...` در هدر (رگرسیون Stage 5) | حذف substring |
| 3 | `FOREIGN KEY constraint failed` در `saveMessage` | `UPDATE attachments` قبل از `INSERT messages` | `PRAGMA defer_foreign_keys = ON` |
| 4 | کاربر با session مرده logout نمی‌شد | نبود چک 401 در sync | `SyncResult.unauthorized` + `_handleUnauthorized` |
| 5 | پیام عکس دو بار نمایش داده می‌شد | rename branch attachments قدیمی را رها می‌کرد | `DELETE` به‌جای `UPDATE` در rename |
| 6 | `message_ack` ردیف DB را با id جدید ذخیره نمی‌کرد | فقط `updateMessageStatus(realMessageId)` صدا زده می‌شد | `saveMessage(id=realMessageId)` با rename branch |

## ۷. تصمیمات معماری اخیر

### الگوی callback در `presentation/state/` و `data/`
- **دلیل:** جدا کردن منطق state پیچیده بدون DI framework.
- **جایگزین رد شده:** interface جدید یا ChangeNotifier تازه — بیش از حد پیچیده برای این حجم.
- **پیامد:** کلاس‌های state stateless هستند و برای تست قابل تزریق.

### لاگ‌های `debugPrint` باقی می‌مانند
- **دلیل:** درخواست کاربر برای دیباگ بهتر در آینده.
- **پیامد:** در release build، `debugPrint` خودکار ساکت می‌شود. BODY logging با `kDebugMode` محافظت شده.

### `PRAGMA defer_foreign_keys = ON` در `saveMessage`
- **دلیل:** rename branch نیاز به حذف ردیف قدیمی قبل از insert ردیف جدید دارد.
- **جایگزین رد شده:** تغییر ترتیب عملیات (پیچیده‌تر، شکننده‌تر).

### `DELETE` به‌جای rename در `saveMessage` rename branch
- **دلیل:** جلوگیری از duplicate attachment.
- **جایگزین رد شده:** حفظ ردیف‌های قدیمی و merge (نیازمند فیلد `old_id` در attachments).

## ۸. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت.
- حداکثر پیوست در یک پیام: ۱۰.
- Android فقط. RTL.
- FK cascade: `saveMessage` همیشه `UPDATE` وقتی ردیف وجود دارد (نه `INSERT OR REPLACE`).

## ۹. بدهی فنی باقی‌مانده

- **بدون تست خودکار** (فقط placeholder در `widget_test.dart`).
- `_ensureConnectedAndSynced()` در `build()` — الگوی نازیبا (باقی‌مانده از قبل).
- `/api/test-push` بدون احراز هویت (کاندید حذف).
- `_showNotificationDebugMenu` در build production نمایش داده می‌شود.
- **پاک‌سازی ۲۴ ساعته D1** روی `messages` (به درخواست کاربر حفظ می‌شود).
- **مدیا groups تلگرام:** هر عکس → پیام جدا.
- `ChatRoom.js` روی سرور هنوز `INSERT` مستقیم دارد.

## ۱۰. حالت کاری فعلی

- **Last verified build:** ✅ staging + دستگاه واقعی (SM A528B)
- **Last verified tests:** همهٔ سناریوهای Stage 1-8
- **Known blocking bug:** ندارد.

## ۱۱. حالت کاری این جلسه

- **فایل‌های جدید کل:** ۱۳
- **فایل‌های تغییر یافته:** `chat_screen`, `chat_repository`, `sync_engine`, `main.dart`, `local_chat_dao`, `socket_event_dispatcher`, `chat_message_list`
- **خطوط کاهش‌یافته در `chat_screen`:** ~۱۲۰۰ خط
- **خطوط کاهش‌یافته در `chat_repository`:** ~۴۵۰ خط

## ۱۲. مرحلهٔ بعد (پیشنهاد)

به ترتیب اولویت:

1. **(P1) تست خودکار** برای `LocalChatDao`, `SyncEngine`, `SocketEventDispatcher` — پوشش باگ‌های رفع‌شده.
2. **(P1) آپدیت نسخه به `1.0.10+10`** و انتشار روی GitHub Releases.
3. **(P2) حذف `/api/test-push`** و گیت کردن debug menu.
4. **(P2) بررسی media groups تلگرام** — اگر کاربر بخواهد.
5. **(P3) شکستن `_ensureConnectedAndSynced`** در `main.dart`.
6. **(P3) افزودن لاگ بیشتر** در نقاط کلیدی (به درخواست کاربر).

## ۱۳. نقاط حساس (نظارت مداوم)

- **پس از release بعدی**: ۱-۲ هفته به این نشانه‌ها توجه کنید:
  - دکمهٔ دانلود روی عکس‌های آپلودشده ظاهر شود
  - پیام بعد از Force Stop دو بار دانلود بخواهد
  - پیام دوگانه در یک حباب
  - logout غیرمنتظره (session server-side invalid)

**اگر دیده شد**:

```powershell
adb shell run-as com.yasinshahabadi.guysgram sqlite3 /data/data/com.yasinshahabadi.guysgram/databases/telegram_chat_local_v2.db "SELECT id, message_id, local_path, is_downloaded FROM attachments ORDER BY created_at DESC LIMIT 10;"