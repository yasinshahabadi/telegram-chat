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
سوپراگروه تلگرام را در یک UI بومی نمایش می‌دهد، با پشتیبانی کامل آفلاین،
اعلان‌های FCM و پاسخ مستقیم از اعلان.

## ۳. وضعیت جاری

### Refactor (Stages 1-9) — ✅ کامل
تجزیهٔ `chat_screen.dart` (~1500 خط) و `chat_repository.dart` (~750 خط).

### Forward + Links (Stages 10-13) — ✅ کامل
نمایش forward header، deep link به تلگرام، و لینک‌های کلیک‌شدنی.

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
| **10** | **migration + normalizer سرور برای forward** |
| **11** | **SQLite v4 + ChatMessageModel + DAO** |
| **12** | **ForwardHeader widget + ادغام** |
| **13** | **LinkifiedText + tg:// deep links** |

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

**فایل‌های جدید کل:** ۱۵ فایل.

## ۴. معماری فعلی (کلاینت)

### Presentation Layer
presentation/
├── screens/chat_screen.dart (root StatefulWidget, ~330 خط)
├── widgets/
│ ├── chat_app_bar.dart (static factory برای AppBar)
│ ├── chat_status_subtitle.dart (subtitle خود AnimatedBuilder دارد)
│ ├── pinned_message_banner.dart (banner خود AnimatedBuilder دارد)
│ ├── chat_message_list.dart (ListView + empty/loading state)
│ ├── message_bubble.dart (حباب پیام + RTL-aware layout)
│ ├── forward_header.dart (Stage 12 — نمایش فوروارد)
│ ├── linkified_text.dart (Stage 13 — لینک/منشن کلیک‌شدنی)
│ ├── chat_input_bar.dart (input + voice recording)
│ ├── reaction_bar.dart (chips + picker)
│ ├── reply_thumbnail.dart (thumbnail در reply)
│ ├── swipe_to_reply.dart (swipe gesture wrapper)
│ ├── unread_divider.dart (divider animation)
│ ├── user_avatar.dart (avatar + online badge)
│ └── media_bubble_content.dart (media display)
├── dialogs/ (5 فایل)
└── state/
├── chat_upload_coordinator.dart
└── unread_flow_controller.dart


### Data Layer
data/
├── chat_repository.dart (ChangeNotifier — state root)
├── socket_event_dispatcher.dart (12 نوع رویداد سوکت)
├── upload_lifecycle.dart (چرخهٔ ساخت/نهایی/retry)
├── pending_action_queue.dart (صف + scheduling)
├── chat_websocket_client.dart (WS + heartbeat 25s/60s)
└── sync_engine.dart (cursor-based sync + لاگ)


### DB Schema
- **سرور D1:** جدول `messages` شامل ۵ ستون forward (migration 0003).
- **کلاینت SQLite:** v4 با ۵ ستون forward مشابه.

## ۵. سرور (Cloudflare Workers)

- D1 + Durable Object `ChatRoom`.
- Zero-Trust Session.
- `/api/sync` بر پایه cursor.
- مدیا فقط از Telegram Bot API (بدون R2).
- `normalizer.js` حالا `forward_origin` (Bot API 7+) و legacy fields را پشتیبانی می‌کند.
- `ChatRoom.js` هنوز `INSERT` مستقیم دارد (برای آینده).

## ۶. باگ‌ها و بهبودهای این جلسه

### Refactor
| # | مورد | رفع |
|---|---|---|
| 1 | `_dependents.isEmpty` در دیالوگ ویرایش | حذف `controller.dispose()` زودهنگام |
| 2 | پیام بعد از background نمی‌آمد | حذف `substring` در Authorization header |
| 3 | `FOREIGN KEY constraint failed` | `PRAGMA defer_foreign_keys = ON` |
| 4 | کاربر با session مرده logout نمی‌شد | `SyncResult.unauthorized` + `_handleUnauthorized` |
| 5 | پیام عکس دو بار نمایش داده می‌شد | `DELETE` به‌جای rename در `saveMessage` |
| 6 | `message_ack` DB را با id جدید ذخیره نمی‌کرد | `saveMessage(id=realMessageId)` |

### UI / Feature
| # | مورد | رفع |
|---|---|---|
| 7 | همهٔ پیام‌ها سمت راست بودند | `MainAxisAlignment.end` (RTL-aware) |
| 8 | آواتار در راست حباب بود | آواتار به آخرین فرزند Row منتقل شد |
| 9 | لینک‌ها کلیک‌پذیر نبودند | widget `LinkifiedText` + regex |
| 10 | باز شدن مرورگر به‌جای تلگرام | `tg://` scheme + `<queries>` در manifest |

## ۷. تصمیمات معماری اخیر

### الگوی callback
- **دلیل:** جدا کردن منطق state پیچیده بدون DI framework.
- **جایگزین رد شده:** interface یا ChangeNotifier جدید.

### لاگ‌های `debugPrint` حفظ می‌شوند
- **دلیل:** درخواست کاربر برای دیباگ بهتر.
- **پیامد:** در release، `debugPrint` خودکار ساکت می‌شود.

### `tg://` به‌جای `https://t.me/...`
- **دلیل:** `https://t.me` توسط Chrome و Telegram claim می‌شود → Android ممکن است به مرورگر بفرستد. `tg://` فقط توسط Telegram claim می‌شود → مستقیم به اپ.
- **جایگزین رد شده:** `intent://` (پیچیده‌تر، مخصوص Android).

### `PRAGMA defer_foreign_keys = ON` در `saveMessage`
- **دلیل:** rename branch نیاز به حذف ردیف قدیمی قبل از insert ردیف جدید دارد.

### `DELETE` به‌جای rename در `saveMessage` rename branch
- **دلیل:** جلوگیری از duplicate attachment.

### RTL-aware layout در `MessageBubble`
- **دلیل:** چیدمان مثل تلگرام — پیام خودی راست، دیگران چپ با آواتار در چپ.
- **پیامد:** اگر اپ روزی در LTR اجرا شود، این کد باید بازبینی شود.

## ۸. محدودیت‌های مهم

- R2 استفاده نمی‌شود (محدودیت کارت اعتباری ایران).
- سقف حجم هر آپلود: ۲۰ مگابایت.
- حداکثر پیوست در یک پیام: ۱۰.
- Android فقط. RTL.
- FK cascade: `saveMessage` همیشه `UPDATE` وقتی ردیف وجود دارد.

## ۹. بدهی فنی باقی‌مانده

- **بدون تست خودکار** (فقط placeholder).
- `_ensureConnectedAndSynced()` در `build()` — الگوی نازیبا.
- `/api/test-push` بدون احراز هویت (کاندید حذف).
- `_showNotificationDebugMenu` در build production نمایش داده می‌شود.
- **پاک‌سازی ۲۴ ساعته D1** روی `messages` (به درخواست کاربر حفظ می‌شود).
- **مدیا groups تلگرام:** هر عکس → پیام جدا.
- `ChatRoom.js` هنوز `INSERT` مستقیم دارد.

## ۱۰. حالت کاری فعلی

- **Last verified build:** ✅ staging + دستگاه واقعی (SM A528B)
- **Last verified tests:** همهٔ سناریوهای Stage 1-13
- **Known blocking bug:** ندارد.

## ۱۱. مرحلهٔ بعد (پیشنهاد)

به ترتیب اولویت:

1. **(P1) تست خودکار** برای `LocalChatDao`, `SyncEngine`, `SocketEventDispatcher`, `LinkifiedText`.
2. **(P1) آپدیت نسخه به `1.0.10+10`** و انتشار روی GitHub Releases.
3. **(P2) migration روی D1 production** (وقتی staging تأیید شد).
4. **(P2) حذف `/api/test-push`** و گیت کردن debug menu.
5. **(P3) بررسی media groups تلگرام**.
6. **(P3) شکستن `_ensureConnectedAndSynced`** در `main.dart`.

## ۱۲. نقاط حساس (نظارت مداوم)

- **پس از release بعدی:** ۱-۲ هفته به این نشانه‌ها توجه کنید:
  - دکمهٔ دانلود روی عکس‌های آپلودشده ظاهر شود
  - پیام بعد از Force Stop دو بار دانلود بخواهد
  - پیام دوگانه در یک حباب
  - logout غیرمنتظره (session server-side invalid)
  - forward header نمایش داده نشود (migration سرور اعمال نشده)
  - لینک‌ها به مرورگر باز شوند (AndroidManifest قدیمی)

## ۱۳. اطلاعات تماس سرور

- **D1 staging DB ID:** `1ecf41a0-8348-439c-b062-10b3cce3e99f`
- **D1 production DB ID:** `6b53e474-18eb-4be4-87cf-6fda96db3cf1`
- **Staging URL:** `https://telegram-chat-staging.yasinshahabadi007.workers.dev`
- **Migration 0003 وضعیت:** ✅ اعمال‌شده روی staging؛ ⏳ در انتظار برای production