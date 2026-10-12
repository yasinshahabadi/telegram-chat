# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/07/20 (2026-10-12)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در کد: **1.0.10+10**
- نسخهٔ منتشرشده روی GitHub: **v1.0.10**
- نسخهٔ بعدی برنامه‌ریزی‌شده: **1.0.11+11**
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
### Supergroup Fix (Stage 18) — ✅ کامل روی staging
### Reaction Emoji Settings (Stage 19) — ✅ کامل روی staging

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
| 17 | Text entities (bold/link/blockquote/code) — سرور + کلاینت |
| 18 | رفع قطع ارتباط پس از ارتقای گروه به سوپرگروه |
| 19 | تنظیم ایموجی‌های ری‌اکشن (Drawer + صفحهٔ تنظیمات + سرویس محلی) |

## ۴. معماری فعلی

### Presentation — chat
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
│ ├── formatted_message_text.dart
│ ├── chat_input_bar.dart
│ ├── reaction_bar.dart (Stage 19: از ReactionEmojiSettings می‌خواند)
│ ├── reply_thumbnail.dart
│ ├── swipe_to_reply.dart
│ ├── unread_divider.dart
│ ├── user_avatar.dart
│ └── media_bubble_content.dart
├── dialogs/ (5 فایل)
└── state/
├── chat_upload_coordinator.dart
└── unread_flow_controller.dart

### Presentation — settings (Stage 19)
features/settings/presentation/
├── widgets/app_drawer.dart
└── screens/reaction_emojis_screen.dart

### Data — chat
data/
├── chat_repository.dart
├── socket_event_dispatcher.dart
├── upload_lifecycle.dart
├── pending_action_queue.dart
├── chat_websocket_client.dart
└── sync_engine.dart

### Core — settings (Stage 19)
core/settings/
└── reaction_emoji_settings.dart

### Domain Models
domain/models/
├── chat_message_model.dart
└── message_entity.dart

### DB Schema
- **سرور D1:**
  - `messages`: + 5 ستون forward + `telegram_media_group_id` + `text_entities`
  - `pending_media_groups` (buffering آلبوم)
- **کلاینت SQLite:** v5 با ۵ ستون forward + `text_entities`.
- **کلاینت SharedPreferences:** `reaction_emojis_v1` (Stage 19).

### سرور
- `normalizer.js`: forward + آلبوم buffering + entities
- `webhookHandler.js`: orchestration آلبوم + لاگ تشخیصی chat_id (Stage 18)
- `mediaController.js`: `sendMediaGroup` با fallback

## ۵. باگ‌ها و بهبودهای کل جلسات

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
| 13 | فرمت متن رعایت نمی‌شد | `text_entities` + `FormattedMessageText` |
| 14 | قطع کامل ارتباط برنامه ↔ گروه | به‌روزرسانی `TELEGRAM_GROUP_ID` |
| 15 | Emoji picker پس‌زمینهٔ سفید در تم تاریک | تنظیم `Config` رنگ‌ها از `Theme` (Stage 19) |

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
- **دلیل:** سرور قبلاً `msg.text` را ذخیره می‌کرد و فرمت‌ها از دست می‌رفت.
- **روش:** ذخیرهٔ `msg.entities` به‌عنوان JSON در DB + رندر با `TextSpan`.
- **جایگزین رد شده:** پارس HTML روی کلاینت.

### لاگ تشخیصی `chat_id` در `webhookHandler.js` (Stage 18)
- **دلیل:** وقتی تلگرام گروه را خودکار به سوپرگروه ارتقا می‌دهد،
  `chat_id` کاملاً عوض می‌شود و پیام‌های ورودی بی‌صدا دور ریخته
  می‌شوند؛ هیچ خطایی در `wrangler tail` دیده نمی‌شود.
- **روش:** در سه نقطه (`message`, `edited_message`, `message_reaction`)،
  اگر `checkIsTargetGroup` نامطابق بود، `console.warn` با `chat_id`
  واقعی چاپ می‌شود.
- **جایگزین رد شده:** ارسال هشدار به ادمین در تلگرام.

### تنظیم ایموجی‌های ری‌اکشن (Stage 19)
- **دلیل:** کاربر باید بتواند لیست پیش‌فرض ایموجی‌های منوی long-press
  را شخصی‌سازی کند.
- **روش:** `ReactionEmojiSettings` (singleton + ChangeNotifier +
  SharedPreferences با کلید `reaction_emojis_v1`).
- **دلیل per-device (نه سرور):** کاربر درخواست کرد شخصی‌سازی فقط محلی
  باشد. هر دستگاه لیست خودش را دارد.
- **مرزها:** حداکثر ۱۲، حداقل ۱، بدون تکرار.
- **Drawer قابل‌گسترش:** `AppDrawer` با `_SectionLabel` + `_DrawerItem`.
  افزودن گزینهٔ جدید فقط یک `_DrawerItem`.
- **جایگزین رد شده:** ذخیره در سرور (نیاز به جدول جدید + endpoint).

### API جدید `onReorderItem` (Stage 19)
- **دلیل:** `ReorderableListView.onReorder` در Flutter 3.41+ deprecated
  شده و `onReorderItem` جایگزین آن است.
- **پیامد:** متد `reorderEmojis` در سرویس دیگر offset را اصلاح نمی‌کند؛
  API جدید خودش `newIndex` را تنظیم می‌کند.

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
- **🔴 توکن ربات در چت لو رفته و باید بچرخد** (بخش ۱۳).
- **🟡 عدد شمارنده در `reaction_emojis_screen.dart` در حالت RTL
  معکوس نمایش داده می‌شود** (`12 / 11` به‌جای `11 / 12`). اصلاح
  پیشنهادی: `Directionality(textDirection: TextDirection.ltr, ...)`.
  **در انتظار تأیید کاربر.**

## ۹. حالت فعلی

- **Last verified build:** ✅ staging + دستگاه واقعی
- **Known blocking bug:** ندارد.
- **Stage 18 و 19 کامل روی staging.**

## ۱۰. مرحلهٔ بعد

- **🔴 چرخش توکن ربات** (اولویت P0 — امنیتی).
- **Deploy production Worker** با تغییرات Stage 18 و 19.
- migration های production D1 (0003/0004/0005) — با backup اولیه.
- انتشار `v1.0.11+11` (در صورت درخواست کاربر).
- تست خودکار (P1).
- حذف `/api/test-push` (P2).

## ۱۱. اطلاعات سرور

- **D1 staging DB ID:** `1ecf41a0-8348-439c-b062-10b3cce3e99f`
- **D1 production DB ID:** `6b53e474-18eb-4be4-87cf-6fda96db3cf1`
- **Staging URL:** `https://telegram-chat-staging.yasinshahabadi007.workers.dev`
- **Production URL:** `https://telegram-chat-app.yasinshahabadi007.workers.dev`
- **گروه تلگرام (سوپرگروه فعلی):** `-1004362736569`
- **گروه تلگرام (شناسهٔ قدیمی، منسوخ):** `-5585398377`
- **Migrations وضعیت:**
  - 0001, 0002: ✅ staging + production
  - 0003, 0004, 0005: ✅ staging؛ ⏳ production

## ۱۲. نقاط حساس (نظارت)

- پیام‌های قدیمی که فرمت‌دار نیستند (entities قبل از Stage 17 ذخیره نشده)
- آلبوم‌ها دیرتر از ۳ ثانیه برسند
- لینک‌ها به مرورگر باز شوند (AndroidManifest قدیمی روی گوشی)
- forward header نمایش داده نشود
- **🔴 اگر در `wrangler tail` پیام‌های زیر دیده شد:**
  - `[Webhook] ⚠️ message IGNORED — chat_id=... does not match TELEGRAM_GROUP_ID=...`
  - `[Webhook] ⚠️ edited_message IGNORED — ...`
  - `[Webhook] ⚠️ message_reaction IGNORED — ...`
- **🟡 ترتیب ایموجی‌ها پس از reorder درست ذخیره می‌شود؟**
  (با API جدید `onReorderItem` — تست دستی تأیید شده، ولی در صورت
  مشاهدهٔ رفتار عجیب، اول این را چک کنید.)

## ۱۳. هشدار امنیتی — نیازمند اقدام فوری

**توکن ربات `@chattransfer_test_bot` در چت لو رفته است.**

مراحل (اولویت P0):

1. در BotFather → `/revoke` → توکن جدید بگیرید.
2. در `.dev.vars` (که نباید در گیت باشد) جایگزین کنید.
3. `npx wrangler secret put TELEGRAM_BOT_TOKEN --env staging`
4. `npx wrangler secret put TELEGRAM_BOT_TOKEN` (production)
5. `setWebhook` را با توکن جدید برای staging (و در صورت نیاز production)
   مجدداً تنظیم کنید.
6. commit نکنید — توکن فقط در Secrets Cloudflare و `.dev.vars` محلی.

**هرگز توکن واقعی را در چت، در گیت، یا در اسکرین‌شات قرار ندهید.**
در پیام‌های آیندهٔ چت، آن را با `<TOKEN>` جایگزین کنید.

## ۱۴. نقشهٔ رفع باگ Stage 18 (برای مرجع آینده)

**علامت:** برنامه هیچ پیامی از گروه نمی‌گیرد و هیچ پیامی به گروه نمی‌فرستد.

**علت ریشه‌ای:** تلگرام گروه عادی `WWW chat` را به سوپرگروه ارتقا داد
(به دلیل فعال شدن «تاریخچه برای اعضای جدید»). این کار باعث شد
`chat_id` از `-5585398377` به `-1004362736569` تغییر کند.

**تشخیص قطعی:**
```bash
curl.exe -s "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
curl.exe -s "https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<OLD_ID>&text=TestFromBot"
# انتظار: ok:false با description: "group chat was upgraded to a supergroup chat"
# و پارامتر migrate_to_chat_id

```

رفع (commit 1d7516f):

wrangler.toml: تغییر هر دو TELEGRAM_GROUP_ID.

webhookHandler.js: افزودن console.warn تشخیصی.

Deploy: npx wrangler deploy --env staging.

درس‌آموخته: تلگرام می‌تواند بدون هشدار صریح گروه را ارتقا دهد.

۱۵. نقشهٔ Stage 19 (Reaction Emoji Settings)
فایل‌های جدید:

mobile/lib/core/settings/reaction_emoji_settings.dart

mobile/lib/features/settings/presentation/widgets/app_drawer.dart

mobile/lib/features/settings/presentation/screens/reaction_emojis_screen.dart

فایل‌های اصلاح‌شده:

mobile/lib/main.dart (import + initialize)

mobile/lib/features/chat/presentation/widgets/reaction_bar.dart

mobile/lib/features/chat/presentation/screens/chat_screen.dart (drawer)

نکات کلیدی:

کلید prefs: reaction_emojis_v1

حداقل ۱، حداکثر ۱۲، بدون تکرار

Drawer قابل‌گسترش (افزودن گزینه = افزودن یک _DrawerItem)

Drag & Drop با onReorderItem (Flutter 3.41+)

رنگ‌بندی Picker از Theme.colorScheme (سازگار با dark/light)