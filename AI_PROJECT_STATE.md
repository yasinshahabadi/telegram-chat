# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/15 (2026-10-06)

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
سوپراگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. وضعیت جاری

### Refactor (Stages 1-9) — ✅ کامل
تجزیهٔ `chat_screen.dart` (~1500 خط) و `chat_repository.dart` (~750 خط).

### Forward + Links (Stages 10-13) — ✅ کامل
نمایش forward header، deep link به تلگرام، و لینک‌های کلیک‌شدنی.

### Media Groups / Album (Stages 14-16) — ✅ کامل
دریافت و ارسال آلبوم‌های تلگرام به صورت یکپارچه.

### فازهای کامل‌شده (کل جلسه)
| Stage | محتوا |
|---|---|
| 1 | استخراج ۵ دیالوگ + debug sheet |
| 2 | استخراج AppBar/subtitle/pinned |
| 3 | استخراج لیست پیام‌ها |
| 4 | استخراج منطق آپلود |
| 5 | استخراج unread flow |
| 5.5 | رفع ۳ باگ جانبی (session, FK, unauthorized) |
| 6 | استخراج سوکت dispatcher |
| 6.5 | رفع باگ duplicate attachment |
| 7 | استخراج صف + آپلود + رفع باگ ack |
| 8 | پاک‌سازی کد مرده |
| 9 | چیدمان پیام‌ها مثل تلگرام (خودی راست، دیگران چپ) |
| 10 | migration + normalizer سرور برای forward |
| 11 | SQLite v4 + ChatMessageModel + DAO |
| 12 | ForwardHeader widget + ادغام |
| 13 | LinkifiedText + tg:// deep links |
| **14** | **buffering آلبوم‌های ورودی در webhook** |
| **15** | **sendMediaGroup برای آلبوم‌های خروجی** |
| **16** | **state update + commit نهایی** |

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
| `forward_header.dart` | — | ~۹۰ خط |
| `linkified_text.dart` | — | ~۱۳۰ خط |

**فایل‌های جدید کل:** ۱۵ فایل در کلاینت + ۲ migration در سرور.

## ۴. معماری فعلی

### Presentation Layer
presentation/
├── screens/chat_screen.dart (root StatefulWidget, ~330 خط)
├── widgets/
│ ├── chat_app_bar.dart
│ ├── chat_status_subtitle.dart
│ ├── pinned_message_banner.dart
│ ├── chat_message_list.dart
│ ├── message_bubble.dart (RTL-aware layout)
│ ├── forward_header.dart (Stage 12)
│ ├── linkified_text.dart (Stage 13)
│ ├── chat_input_bar.dart
│ ├── reaction_bar.dart
│ ├── reply_thumbnail.dart
│ ├── swipe_to_reply.dart
│ ├── unread_divider.dart
│ ├── user_avatar.dart
│ └── media_bubble_content.dart
├── dialogs/ (5 فایل)
└── state/
├── chat_upload_coordinator.dart
└── unread_flow_controller.dart

### Data Layer
data/
├── chat_repository.dart
├── socket_event_dispatcher.dart
├── upload_lifecycle.dart
├── pending_action_queue.dart
├── chat_websocket_client.dart
└── sync_engine.dart


### DB Schema
- **سرور D1:**
  - جدول `messages` با ۵ ستون forward + `telegram_media_group_id`.
  - جدول جدید `pending_media_groups` (buffering).
- **کلاینت SQLite:** v4 با ۵ ستون forward.

### سرور
- D1 + Durable Object `ChatRoom`.
- `/api/sync` بر پایه cursor.
- `normalizer.js`: پشتیبانی از forward + آلبوم (buffering).
- `webhookHandler.js`: orchestration با `ctx.waitUntil` برای finalize آلبوم.
- `mediaController.js`: `sendMediaGroup` با fallback به ارسال جدا.

## ۵. باگ‌ها و بهبودهای کل جلسه

### Refactor
| # | مورد | رفع |
|---|---|---|
| 1 | `_dependents.isEmpty` در دیالوگ ویرایش | حذف `controller.dispose()` زودهنگام |
| 2 | پیام بعد از background نمی‌آمد | حذف `substring` در Authorization |
| 3 | `FOREIGN KEY constraint failed` | `PRAGMA defer_foreign_keys = ON` |
| 4 | کاربر با session مرده logout نمی‌شد | `SyncResult.unauthorized` |
| 5 | پیام عکس دو بار | `DELETE` به‌جای rename |
| 6 | `message_ack` DB را با id جدید ذخیره نمی‌کرد | `saveMessage(id=realMessageId)` |

### UI / Feature
| # | مورد | رفع |
|---|---|---|
| 7 | همهٔ پیام‌ها سمت راست | `MainAxisAlignment.end` (RTL) |
| 8 | آواتار در راست حباب | آواتار به آخرین فرزند |
| 9 | لینک‌ها کلیک‌پذیر نبودند | `LinkifiedText` |
| 10 | باز شدن مرورگر به‌جای تلگرام | `tg://` + `<queries>` |
| 11 | آلبوم تلگرام → چند حباب | `pending_media_groups` buffering |
| 12 | ارسال چند فایل → چند پست جدا | `sendMediaGroup` + fallback |

## ۶. تصمیمات معماری اخیر

### الگوی callback
- **دلیل:** جدا کردن منطق state پیچیده بدون DI framework.
- **جایگزین رد شده:** interface یا ChangeNotifier جدید.

### لاگ‌های `debugPrint` حفظ می‌شوند
- **دلیل:** درخواست کاربر برای دیباگ بهتر.
- **پیامد:** در release، `debugPrint` خودکار ساکت می‌شود.

### `tg://` به‌جای `https://t.me`
- **دلیل:** `https://t.me` توسط Chrome و Telegram claim می‌شود.
- **جایگزین رد شده:** `intent://` (پیچیده‌تر).

### `PRAGMA defer_foreign_keys = ON` در `saveMessage`
- **دلیل:** rename branch نیاز به حذف قبل از insert دارد.

### `DELETE` به‌جای rename در `saveMessage`
- **دلیل:** جلوگیری از duplicate attachment.

### RTL-aware layout در `MessageBubble`
- **دلیل:** چیدمان مثل تلگرام.
- **پیامد:** اگر LTR شود، باید بازبینی شود.

### Media Group Buffering با D1
- **دلیل:** Worker stateless است، تلگرام آلبوم‌ها را به‌صورت چند webhook می‌فرستد.
- **روش:** `pending_media_groups` + `ctx.waitUntil` با تأخیر 1.5s.
- **پیامد:** آلبوم‌ها ~2s دیرتر نمایش داده می‌شوند (فقط آلبوم).

### `sendMediaGroup` با fallback
- **دلیل:** Bot API فقط photo/video را در آلبوم قبول می‌کند.
- **پیامد:** برای فایل مختلط، به ارسال جدا fallback می‌کنیم.

## ۷. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت.
- حداکثر پیوست در یک پیام: ۱۰.
- Bot API آلبوم: فقط photo/video، حداکثر ۱۰ آیتم.
- Android فقط. RTL.
- FK cascade: `saveMessage` همیشه `UPDATE` وقتی ردیف وجود دارد.

## ۸. بدهی فنی باقی‌مانده

- **بدون تست خودکار**.
- `_ensureConnectedAndSynced()` در `build()`.
- `/api/test-push` بدون احراز هویت.
- `_showNotificationDebugMenu` در build production.
- **پاک‌سازی ۲۴ ساعته D1** روی `messages` (به درخواست کاربر).
- `ChatRoom.js` هنوز `INSERT` مستقیم دارد.

## ۹. حالت کاری فعلی

- **Last verified build:** ✅ staging + دستگاه واقعی (SM A528B)
- **Last verified tests:** همهٔ سناریوهای Stage 1-16
- **Known blocking bug:** ندارد.

## ۱۰. مرحلهٔ بعد (پیشنهاد)

1. **(P1) تست خودکار** برای `LocalChatDao`, `SyncEngine`, `SocketEventDispatcher`, `LinkifiedText`.
2. **(P1) آپدیت نسخه به `1.0.10+10`** و انتشار روی GitHub Releases.
3. **(P1) migration روی D1 production** (migration 0003 و 0004).
4. **(P2) حذف `/api/test-push`** و گیت کردن debug menu.
5. **(P3) شکستن `_ensureConnectedAndSynced`** در `main.dart`.

## ۱۱. نقاط حساس (نظارت مداوم)

پس از release بعدی، ۱-۲ هفته به این نشانه‌ها توجه کن:

- دکمهٔ دانلود روی عکس‌های آپلودشده
- پیام بعد از Force Stop دو بار دانلود
- پیام دوگانه در یک حباب
- logout غیرمنتظره
- forward header نمایش داده نشود
- لینک‌ها به مرورگر باز شوند
- آلبوم‌ها دیرتر از ۳ ثانیه برسند

## ۱۲. اطلاعات سرور

- **D1 staging DB ID:** `1ecf41a0-8348-439c-b062-10b3cce3e99f`
- **D1 production DB ID:** `6b53e474-18eb-4be4-87cf-6fda96db3cf1`
- **Staging URL:** `https://telegram-chat-staging.yasinshahabadi007.workers.dev`
- **Migrations وضعیت:**
  - 0001: ✅ staging + production
  - 0002: ✅ staging + production
  - 0003 (forward): ✅ staging؛ ⏳ production
  - 0004 (media groups): ✅ staging؛ ⏳ production