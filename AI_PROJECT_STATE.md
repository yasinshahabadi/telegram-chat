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
### Forward + Links (Stages 10-13) — ✅ کامل
### Media Groups / Album (Stages 14-16) — ✅ کامل
### Text Entities (Stage 17) — ✅ کامل

### فازهای کامل‌شده
| Stage | محتوا |
|---|---|
| 1-9 | Refactor + UI چیدمان تلگرام |
| 10 | migration + normalizer سرور برای forward |
| 11 | SQLite v4 + forward fields در model |
| 12 | ForwardHeader widget |
| 13 | LinkifiedText + tg:// deep links |
| 14 | buffering آلبوم‌های ورودی |
| 15 | sendMediaGroup برای آلبوم‌های خروجی |
| 16 | state update + commit |
| **17** | **Text entities (bold/link/blockquote/code) — سرور + کلاینت** |

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
| `formatted_message_text.dart` | — | ~۳۰۰ خط |
| `message_entity.dart` | — | ~۱۳۰ خط |

## ۴. معماری فعلی

### Presentation
presentation/
├── screens/chat_screen.dart
├── widgets/
│ ├── chat_app_bar.dart
│ ├── chat_status_subtitle.dart
│ ├── pinned_message_banner.dart
│ ├── chat_message_list.dart
│ ├── message_bubble.dart
│ ├── forward_header.dart
│ ├── linkified_text.dart (fallback)
│ ├── formatted_message_text.dart (Stage 17)
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


### Data
data/
├── chat_repository.dart
├── socket_event_dispatcher.dart
├── upload_lifecycle.dart
├── pending_action_queue.dart
├── chat_websocket_client.dart
└── sync_engine.dart


### Domain Models
domain/models/
├── chat_message_model.dart
└── message_entity.dart (Stage 17)


### DB Schema
- **سرور D1:**
  - `messages`: + 5 ستون forward + `telegram_media_group_id` + `text_entities`
  - `pending_media_groups` (buffering آلبوم)
- **کلاینت SQLite:** v5 با ۵ ستون forward + `text_entities`.

### سرور
- `normalizer.js`: forward + آلبوم buffering + entities
- `webhookHandler.js`: orchestration آلبوم
- `mediaController.js`: `sendMediaGroup` با fallback

## ۵. باگ‌ها و بهبودهای کل جلسه

| # | مورد | رفع |
|---|---|---|
| 1 | `_dependents.isEmpty` دیالوگ | حذف dispose زودهنگام |
| 2 | پیام بعد از background نمی‌آمد | حذف substring در Authorization |
| 3 | `FOREIGN KEY constraint failed` | `PRAGMA defer_foreign_keys` |
| 4 | logout نشدن با session مرده | `SyncResult.unauthorized` |
| 5 | پیام عکس دو بار | DELETE به‌جای rename |
| 6 | ack DB را با id جدید ذخیره نمی‌کرد | `saveMessage(id=realMessageId)` |
| 7 | همهٔ پیام‌ها سمت راست | `MainAxisAlignment.end` (RTL) |
| 8 | آواتار در راست حباب | آواتار به آخرین فرزند |
| 9 | لینک‌ها کلیک‌پذیر نبودند | `LinkifiedText` |
| 10 | مرورگر به‌جای تلگرام | `tg://` + `<queries>` |
| 11 | آلبوم → چند حباب | `pending_media_groups` |
| 12 | چند فایل → چند پست | `sendMediaGroup` |
| 13 | فرمت متن (bold/blockquote/link) رعایت نمی‌شد | `text_entities` + `FormattedMessageText` |

## ۶. تصمیمات معماری

### الگوی callback (state controllers)
- **دلیل:** جدا کردن منطق پیچیده بدون DI framework.
- **جایگزین رد شده:** interface یا ChangeNotifier جدید.

### لاگ‌های debugPrint حفظ می‌شوند
- **دلیل:** درخواست کاربر برای دیباگ بهتر.

### `tg://` به‌جای `https://t.me`
- **دلیل:** https://t.me توسط Chrome هم claim می‌شود.

### `PRAGMA defer_foreign_keys = ON`
- **دلیل:** rename branch نیاز به حذف قبل از insert دارد.

### Media Group Buffering با D1 + ctx.waitUntil
- **دلیل:** Worker stateless است.
- **روش:** `pending_media_groups` + تأخیر 1.5s.

### Text Entities (Stage 17)
- **دلیل:** سرور قبلاً `msg.text` را ذخیره می‌کرد و فرمت‌ها (bold, link, blockquote) از دست می‌رفت.
- **روش:** ذخیرهٔ `msg.entities` به‌عنوان JSON در DB + رندر با `TextSpan`.
- **جایگزین رد شده:** پارس HTML روی کلاینت (شکننده، خطاها زیاد).

## ۷. محدودیت‌ها

- R2 استفاده نمی‌شود.
- سقف حجم آپلود: ۲۰ MB.
- حداکثر پیوست در پیام: ۱۰.
- Bot API آلبوم: فقط photo/video، حداکثر ۱۰ آیتم.
- Android فقط. RTL.

## ۸. بدهی فنی باقی‌مانده

- **بدون تست خودکار**.
- `_ensureConnectedAndSynced()` در `build()`.
- `/api/test-push` بدون احراز هویت.
- debug menu در production build.
- پاک‌سازی ۲۴ ساعته D1 (به درخواست کاربر).
- `ChatRoom.js` هنوز INSERT مستقیم دارد.

## ۹. حالت فعلی

- **Last verified build:** ✅ staging + دستگاه واقعی
- **Known blocking bug:** ندارد.
- **Stage 17 کامل.**

## ۱۰. مرحلهٔ بعد
- **انتشار v1.0.10+10** (این جلسه).
- تست خودکار (P1).
- migration روی production D1.
- حذف `/api/test-push`.

## ۱۱. اطلاعات سرور

- **D1 staging DB ID:** `1ecf41a0-8348-439c-b062-10b3cce3e99f`
- **D1 production DB ID:** `6b53e474-18eb-4be4-87cf-6fda96db3cf1`
- **Staging URL:** `https://telegram-chat-staging.yasinshahabadi007.workers.dev`
- **Production URL (طبق wrangler.toml name = telegram-chat-app):** `https://telegram-chat-app.yasinshahabadi007.workers.dev`
- **Migrations وضعیت:**
  - 0001, 0002: ✅ staging + production
  - 0003, 0004, 0005: ✅ staging؛ ⏳ production

## ۱۲. نقاط حساس (نظارت)

پس از release، به این نشانه‌ها توجه کن:
- پیام‌های قدیمی که فرمت‌دار نیستند (چون entities قبل از Stage 17 ذخیره نشده)
- آلبوم‌ها دیرتر از ۳ ثانیه برسند
- لینک‌ها به مرورگر باز شوند (AndroidManifest قدیمی روی گوشی)
- forward header نمایش داده نشود