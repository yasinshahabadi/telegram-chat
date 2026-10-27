# AI_PROJECT_STATE.md

آخرین به‌روزرسانی: 1405/08/05 (2026-10-27)

---

## ۱. هویت پروژه

- نام: **Guysgram**
- پکیج اندروید: `com.yasinshahabadi.guysgram`
- نسخهٔ فعلی در کد: **1.0.12+12**
- نسخهٔ منتشرشده روی GitHub: **v1.0.10**
- نسخهٔ در حال آماده‌سازی: **1.0.12+12**
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
### Input Bar Emoji Picker (Stage 20-A) — ✅ کامل روی staging
### Clipboard Image Paste (Stage 20-B) — ❌ کنسل و پاکسازی شد
### Attachment Picker (Stage 21) — ✅ کامل + تست دستگاه واقعی
### Cache Hygiene (Stage 21.1) — ✅ کامل + تست دستگاه واقعی
### Reply Jump Fix (Stage 21.2) — ✅ کامل + تست خودکار و دستگاه واقعی

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
| 19 | تنظیم ایموجی‌های ری‌اکشن (Drawer + صفحه + سرویس محلی) |
| 20-A | انتخابگر ایموجی در کادر تایپ چت |
| 21 | نوار پیوست شناور + گالری اختصاصی + پیش‌نمایش/کپشن/ارسال |
| 21.1 | پاک‌سازی خودکار کش دیسک + سقف ۴۸MB برای بندانگشتی‌های گالری |
| 21.2 | پرش دقیق به ابتدای پیام reply + مدیریت پیام حذف‌شده/بسیار قدیمی |

### فازهای کنسل‌شده
| Stage | محتوا | دلیل |
|---|---|---|
| 20-B | پیست تصویر از کلیپ‌بورد (با دکمهٔ اختصاصی) | تجربهٔ کاربری مطلوب نبود |
| 20-B-ب | جایگزینی TextField با EditText بومی برای `commitContent` | به قیمت از دست دادن پنل ایموجی Stage 20-A |

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
│ ├── chat_input_bar.dart (Stage 20-A/21: پنل ایموجی + نوار پیوست)
│ ├── attachment_action.dart (Stage 21: مدل اکشن قابل‌گسترش)
│ ├── attachment_panel.dart (Stage 21: نوار پیوست شناور)
│ ├── reaction_bar.dart
│ ├── reply_thumbnail.dart
│ ├── swipe_to_reply.dart
│ ├── unread_divider.dart
│ ├── user_avatar.dart
│ └── media_bubble_content.dart
├── dialogs/ (5 فایل)
└── state/
    ├── chat_upload_coordinator.dart
    ├── message_scroll_controller.dart (Stage 21.2 — پرش دقیق به پیام reply)
    └── unread_flow_controller.dart

### Presentation — settings (Stage 19)
features/settings/presentation/
├── widgets/app_drawer.dart
└── screens/reaction_emojis_screen.dart

### Presentation — media (Stage 21)
features/media/presentation/
├── screens/
│ ├── media_picker_screen.dart (گالری اختصاصی، مجوز، انتخاب شماره‌دار)
│ └── media_composer_screen.dart (پیش‌نمایش + کپشن + ارسال)
└── widgets/gallery_media_tile.dart (بندانگشتی کش‌شده + نشان انتخاب)

### Data — media (Stage 21)
features/media/data/
└── gallery_media_service.dart (photo_manager: مجوز + صفحه‌بندی ۷۲تایی)

### Domain — media (Stage 21)
features/media/domain/
├── media_upload_limits.dart (۱۰ فایل / ۲۰MB + تشخیص نوع)
└── models/
    ├── picked_media.dart (مدل یکپارچهٔ گالری/فایل)
    └── media_send_payload.dart (خروجی composer به چت)

### Data — chat
data/
├── chat_repository.dart
├── socket_event_dispatcher.dart
├── upload_lifecycle.dart
├── pending_action_queue.dart
├── chat_websocket_client.dart
└── sync_engine.dart

### Core — storage (Stage 21.1)
core/storage/
└── app_cache_manager.dart (پاک‌سازی file_picker + فایل‌های اصلی گالری
    + سقف ۴۸MB برای کش بندانگشتی Glide)

### Core — settings
core/settings/
└── reaction_emoji_settings.dart

### Domain Models
domain/models/
├── chat_message_model.dart
└── message_entity.dart

### Domain Models — media (Stage 21)
features/media/domain/models/
├── picked_media.dart
├── media_send_payload.dart
└── media_attachment_model.dart (existing)

### DB Schema
- **سرور D1:**
  - `messages`: + 5 ستون forward + `telegram_media_group_id` + `text_entities`
  - `pending_media_groups` (buffering آلبوم)
- **کلاینت SQLite:** v5 با ۵ ستون forward + `text_entities`.
- **کلاینت SharedPreferences:** `reaction_emojis_v1`.

### سرور
- `normalizer.js`: forward + آلبوم buffering + entities
- `webhookHandler.js`: orchestration آلبوم + لاگ تشخیصی chat_id
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
| 16 | شمارندهٔ معکوس RTL (`12 / 11` به‌جای `11 / 12`) | ⏳ ثبت‌شده، تصمیم کاربر: فعلاً بی‌اهمیت |
| 17 | دکمهٔ keyboard در پنل ایموجی کیبورد را باز نمی‌کرد | `_inputFocusNode.requestFocus()` بعد از `setState` (Stage 20-A) |

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
- **دلیل:** تلگرام می‌تواند بدون هشدار گروه را به سوپرگروه ارتقا دهد.
- **روش:** `console.warn` در سه نقطه.
- **جایگزین رد شده:** ارسال هشدار به ادمین در تلگرام.

### تنظیم ایموجی‌های ری‌اکشن (Stage 19)
- **دلیل:** شخصی‌سازی ایموجی‌های منوی long-press.
- **روش:** `ReactionEmojiSettings` (per-device، SharedPreferences).
- **مرزها:** حداکثر ۱۲، حداقل ۱، بدون تکرار.
- **Drawer قابل‌گسترش:** افزودن گزینه = یک `_DrawerItem` جدید.
- **جایگزین رد شده:** ذخیره در سرور.

### API `onReorderItem` در `ReorderableListView` (Stage 19)
- **دلیل:** `onReorder` در Flutter 3.41+ deprecated شده است.

### انتخابگر ایموجی در کادر تایپ (Stage 20-A)
- **دلیل:** تجربهٔ مشابه تلگرام برای درج سریع ایموجی.
- **روش:** `ChatInputBar` از `StatelessWidget` → `StatefulWidget`.
  پنل ثابت با `AnimatedSize` (220ms، ارتفاع ۳۰۰dp).
- **FocusNode:** `_inputFocusNode` روی `TextField` برای تشخیص فوکوس
  و انحصار متقابل با پنل.
- **متد `_insertEmoji`:** درج در محل `controller.selection`.
- **رفع باگ دکمهٔ keyboard:** `setState(false)` سپس `requestFocus()`.

### انتخابگر پیوست و گالری اختصاصی (Stage 21)
- **دلیل:** جایگزینی bottom sheet ساده با تجربهٔ تلگرام: نوار شناور،
  گالری داخلی، پیش‌نمایش و کپشن پیش از ارسال.
- **روش:** `AttachmentPanel` شناور + `AttachmentAction` قابل‌گسترش
  (افزودن اکشن جدید = یک آیتم در لیست اکشن‌ها).
  اکشن‌ها: گالری، فایل، موزیک.
- **گالری:** `photo_manager` 3.12 + `photo_manager_image_provider` 2.2؛
  فقط عکس/ویدیو (`RequestType.common`)، گرید ۳ ستونه، انتخاب شماره‌دار،
  سقف ۱۰، بارگذاری صفحه‌بندی‌شده ۷۲تایی.
- **Composer مشترک:** گالری/فایل/موسیقی همه به یک صفحهٔ پیش‌نمایش
  (PageView + نوار بندانگشتی + کپشن + ارسال) می‌روند.
- **مجوزها:** `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` /
  `READ_MEDIA_VISUAL_USER_SELECTED` (Android 13+) و
  `READ_EXTERNAL_STORAGE` (maxSdk 32). حالت «دسترسی محدود» هم مدیریت می‌شود.
- **موسیقی/فایل:** از picker سیستم (SAF) با `FileType.audio` / `any`؛
  نیازی به مجوز صوتی نیست.
- **بدون HD badge:** سرور فایل اصلی را می‌فرستد؛ HD گمراه‌کننده بود.
- **پیش‌بررسی:** سقف ۱۰ فایل و ۲۰MB *قبل* از ساخت پیام خوش‌بینانه
  (هم در composer و هم در coordinator).
- **کپشن:** از composer → coordinator → repository → upload lifecycle
  → `sendMedia` سرور (سرور از قبل caption را به تلگرام می‌فرستاد).
- **حافظه:** بندانگشتی‌ها ۳۲۰px با `FilterQuality.low` و `RepaintBoundary`؛
  کش تصویر در `dispose` گالری پاک می‌شود (خروج: ~۱۳۰MB کاهش PSS).
- **پیشرفت آپلود:** برای عکس، همان تصویر محلی با حلقهٔ درصد و برای
  چند فایل برچسب «در حال ارسال N فایل…» نمایش داده می‌شود.
- **جایگزین رد شده:** bottom sheet سیستمی، کپشن در صفحهٔ جدا، HD toggle.

### ویژگی‌های رد شده (برای مرجع آینده)
- **پشتیبانی از GIF:** کنسل شد.
- **پیست متن از کلیپ‌بورد:** انجام نشد چون long-press سیستم اندروید
  از قبل paste را دارد.
- **پیست تصویر از کلیپ‌بورد (Stage 20-B):** پیاده‌سازی و سپس کنسل شد.
  رجوع به بخش ۱۷ برای جزئیات فنی.

## ۷. محدودیت‌ها

- R2 استفاده نمی‌شود.
- سقف حجم آپلود: ۲۰ MB.
- حداکثر پیوست در پیام: ۱۰.
- Bot API آلبوم: فقط photo/video، حداکثر ۱۰ آیتم.
- گالری اختصاصی فقط عکس/ویدیو؛ فایل و موسیقی از picker سیستم.
- FLAC به‌عنوان document ارسال می‌شود (sendAudio تلگرام فقط mp3/m4a
  را تضمین می‌کند)؛ سایر فرمت‌های صوتی طبق لیست سرور.
- گالری فعلاً انتخابگر آلبوم/فیلتر (عکس، ویدیو، آلبوم‌ها) ندارد.
- Android فقط. RTL.
- کش دیسک: `file_picker` بعد از هر انتخاب/انصراف پاک می‌شود؛ کش
  بندانگشتی گالری (Glide) سقف ۴۸MB دارد و در صورت عبور، در پایان کار با
  گالری ریست می‌شود.
- **Flutter `TextField` از `commitContent` پشتیبانی نمی‌کند**
  (بخش ۱۷).
- **پرش به پیام reply** حداکثر بازهٔ ۱۰۰۰ پیام را از DB بارگذاری می‌کند؛
  پیام‌های قدیمی‌تر با پیام «بسیار قدیمی» و بدون خطا رد می‌شوند (Stage 21.2).

## ۸. بدهی فنی باقی‌مانده

- **بدون تست خودکار** (به‌جز ۶ تست `message_scroll_controller_test.dart`
  برای Stage 21.2)؛ بقیهٔ بخش‌ها هنوز تست ندارند.
- `_ensureConnectedAndSynced()` در `build()`.
- `/api/test-push` بدون احراز هویت.
- debug menu در production build.
- پاک‌سازی ۲۴ ساعته D1 (به درخواست کاربر).
- `ChatRoom.js` هنوز INSERT مستقیم دارد.
- **🔴 توکن ربات در چت لو رفته و باید بچرخد** (بخش ۱۳).
- **🟡 عدد شمارنده در `reaction_emojis_screen.dart` در حالت RTL
  معکوس نمایش داده می‌شود.** تصمیم کاربر: فعلاً بی‌اهمیت.

## ۹. حالت فعلی

- **Last verified build:** ✅ release روی دستگاه واقعی SM-A528B (Android 14)
- **Known blocking bug:** ندارد.
- **Stage 18، 19، 20-A، 21، 21.1 و 21.2 کامل؛ Stage 21، 21.1 و 21.2 روی دستگاه تست شد.**
- **Stage 21.2 (Reply Jump) با ۶ تست خودکار و تست دستی روی دستگاه واقعی پوشش داده شده.**
- **Stage 20-B کنسل و کاملاً پاک‌سازی شده.**
- **در حال آماده‌سازی `v1.0.12+12` (شامل Stage 21 + Cache Hygiene + Reply Jump).**

## ۱۰. مرحلهٔ بعد

- **انتشار `v1.0.12+12`** (این جلسه، در حال انجام؛ شامل Stage 21،
  پاک‌سازی کش Stage 21.1 و Stage 21.2). APK ریلیز arm64 ساخته و روی دستگاه
  نصب شد (۲۳.۸MB).
- تست دستی تکمیلی Stage 21.2: کلیک پشت‌سرهم روی چند reply (لغو درخواست قبلی)
  و مقصدی که دقیقاً مرز بازهٔ ۱۰۰۰ پیامی است.
- تست دستی بیشتر Stage 21 روی دستگاه‌های دیگر (حالت دسترسی محدود،
  ویدیوهای بزرگ، RTL شدید).
- **🔴 چرخش توکن ربات** (اولویت P0 — امنیتی؛ طبق تصمیم کاربر:
  بعد از انتشار انجام می‌شود).
- **Deploy production Worker** با تغییرات Stage 18 (اگر در آینده
  تصمیم گرفته شد به production منتقل شود).
- migration های production D1 (0003/0004/0005) — فعلاً لازم نیست
  چون کلاینت به staging وصل است.
- تست خودکار (P1).
- حذف `/api/test-push` (P2).

## ۱۱. اطلاعات سرور

- **D1 staging DB ID:** `1ecf41a0-8348-439c-b062-10b3cce3e99f`
- **D1 production DB ID:** `6b53e474-18eb-4be4-87cf-6fda96db3cf1`
- **Staging URL:** `https://telegram-chat-staging.yasinshahabadi007.workers.dev`
- **Production URL:** `https://telegram-chat-app.yasinshahabadi007.workers.dev`
- **گروه تلگرام (سوپرگروه فعلی):** `-1004362736569`
- **گروه تلگرام (شناسهٔ قدیمی، منسوخ):** `-5585398377`
- **کلاینت به کدام سرور وصل است:** **staging** (طبق `config.dart`)
- **Migrations وضعیت:**
  - 0001, 0002: ✅ staging + production
  - 0003, 0004, 0005: ✅ staging؛ ⏳ production

## ۱۲. نقاط حساس (نظارت)

- پیام‌های قدیمی که فرمت‌دار نیستند (entities قبل از Stage 17).
- آلبوم‌ها دیرتر از ۳ ثانیه برسند.
- لینک‌ها به مرورگر باز شوند (AndroidManifest قدیمی روی گوشی).
- forward header نمایش داده نشود.
- **🔴 اگر در `wrangler tail` پیام‌های زیر دیده شد:**
  - `[Webhook] ⚠️ message IGNORED — chat_id=...`
  - `[Webhook] ⚠️ edited_message IGNORED — ...`
  - `[Webhook] ⚠️ message_reaction IGNORED — ...`

## ۱۳. هشدار امنیتی — نیازمند اقدام فوری

**توکن ربات `@chattransfer_test_bot` در چت لو رفته است.**

**طبق تصمیم کاربر:** چرخش بعد از انتشار `v1.0.11+11` انجام می‌شود.

مراحل (اولویت P0، بلافاصله بعد از انتشار):

1. در BotFather → `/revoke` → توکن جدید.
2. `.dev.vars` محلی به‌روزرسانی.
3. `npx wrangler secret put TELEGRAM_BOT_TOKEN --env staging`
4. `npx wrangler secret put TELEGRAM_BOT_TOKEN` (production)
5. `setWebhook` با توکن جدید برای staging.
6. commit نکنید — فقط در Secrets و `.dev.vars` محلی.

## ۱۴. نقشهٔ رفع باگ Stage 18 (مرجع آینده)

**علت ریشه‌ای:** تلگرام گروه را به سوپرگروه ارتقا داد و `chat_id`
از `-5585398377` به `-1004362736569` تغییر کرد.

**تشخیص:**
```bash
curl.exe -s "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
curl.exe -s "https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<OLD_ID>&text=Test"
# انتظار: ok:false + "group chat was upgraded to a supergroup chat"
```

رفع (commit 1d7516f):

wrangler.toml: هر دو TELEGRAM_GROUP_ID.

webhookHandler.js: افزودن console.warn تشخیصی.

۱۵. نقشهٔ Stage 19 (Reaction Emoji Settings)
فایل‌های جدید:

mobile/lib/core/settings/reaction_emoji_settings.dart

mobile/lib/features/settings/presentation/widgets/app_drawer.dart

mobile/lib/features/settings/presentation/screens/reaction_emojis_screen.dart

فایل‌های اصلاح‌شده:

mobile/lib/main.dart

mobile/lib/features/chat/presentation/widgets/reaction_bar.dart

mobile/lib/features/chat/presentation/screens/chat_screen.dart

نکات: کلید prefs reaction_emojis_v1، مرزها ۱..۱۲، بدون تکرار،
onReorderItem (Flutter 3.41+).

۱۶. نقشهٔ Stage 20-A (Input Bar Emoji Picker)
فایل اصلاح‌شده:

mobile/lib/features/chat/presentation/widgets/chat_input_bar.dart

نکات کلیدی:

StatefulWidget + _inputFocusNode + _isEmojiPanelOpen.

پنل با AnimatedSize (220ms).

_insertEmoji در محل cursor.

رفع باگ toggle کیبورد: setState(false) سپس requestFocus().

۱۷. محدودیت Flutter — commitContent (مرجع آینده)
مشکل: کاربران می‌خواهند با کیبورد بومی اندروید، تصویر را از
پنل تصاویر کیبورد (commitContent) بفرستند. در تلگرام این کار
می‌شود، ولی در برنامهٔ ما نه.

دلیل: TextField فلاتر از InputConnection.commitContent
پشتیبانی نمی‌کند. کیبورد با پرسیدن getMimeTypes از
InputConnection می‌فهمد فیلد تصویر را نمی‌پذیرد و آیتم را
خاکستری نشان می‌دهد.

راه‌حل‌های ممکن (هیچ‌کدام تا این لحظه انتخاب نشده):

جایگزینی TextField با EditText بومی از طریق AndroidView:

نیاز به پیاده‌سازی کامل PlatformView + مدیریت متن دوطرفه.

پنل ایموجی Stage 20-A از کار می‌افتد و باید بازسازی شود.

رفتار paste متن، انتخاب/ویرایش/کپی داخل فیلد هم عوض می‌شود.

پیچیدگی: ۲ تا ۴ جلسه کار.

ریسک regression: بالا.

انتظار برای پشتیبانی رسمی Flutter: عملاً غیرقابل برنامه‌ریزی.

دکمهٔ paste اختصاصی (Stage 20-B قدیم): پیاده‌سازی شد ولی
کاربر آن را رد کرد چون تجربهٔ کاربری مطلوب نبود.

تصمیم فعلی: ویژگی پیست تصویر از کلیپ‌بورد کنسل شده است.

۱۸. نقشهٔ انتشار v1.0.11+11 (این جلسه)
هدف سرور: staging (تأییدشده توسط کاربر).

محتوای نسخه:

Stage 19: تنظیم ایموجی‌های ری‌اکشن

Stage 20-A: انتخابگر ایموجی در کادر تایپ

Stage 18 (روی staging از قبل deploy شده)

متن Changelog (تأییدشده):

تنظیم ایموجی‌های ری‌اکشن (حداکثر ۱۲)

انتخابگر ایموجی در کادر تایپ

منوی همبرگری قابل‌گسترش

رفع قطع ارتباط با گروه تلگرام

نمایش بهتر پیام‌های ارسالی از گروه

## ۱۹. نقشهٔ Stage 21 (Attachment Picker)

**هدف:** جایگزینی bottom sheet پیوست با نوار شناور قابل‌گسترش + گالری
داخلی + پیش‌نمایش/کپشن، مشابه تلگرام.

**فایل‌های جدید:**
- `mobile/lib/features/chat/presentation/widgets/attachment_action.dart`
- `mobile/lib/features/chat/presentation/widgets/attachment_panel.dart`
- `mobile/lib/features/media/data/gallery_media_service.dart`
- `mobile/lib/features/media/domain/media_upload_limits.dart`
- `mobile/lib/features/media/domain/models/picked_media.dart`
- `mobile/lib/features/media/domain/models/media_send_payload.dart`
- `mobile/lib/features/media/presentation/screens/media_picker_screen.dart`
- `mobile/lib/features/media/presentation/screens/media_composer_screen.dart`
- `mobile/lib/features/media/presentation/widgets/gallery_media_tile.dart`

**فایل‌های اصلاح‌شده:**
- `chat_input_bar.dart`: `attachmentActions` + پنل پیوست + انحصار با ایموجی
- `chat_screen.dart`: ساخت اکشن‌ها و بازکردن picker/composer
- `chat_upload_coordinator.dart`: `pickFiles`، `sendPickedMedia`، اعتبارسنجی، caption
- `chat_repository.dart`: انتقال caption
- `upload_lifecycle.dart`: caption در پیام خوش‌بینانه
- `message_bubble.dart`: نمایش پیشرفت با بندانگشتی محلی
- `pubspec.yaml` / `pubspec.lock`: photo_manager
- `AndroidManifest.xml`: مجوزهای گالری
- `android/gradle.properties`: کامنت‌کردن پروکسی مردهٔ `192.168.100.5:4865`

**تست انجام‌شده روی SM-A528B (Android 14):**
- باز/بسته شدن نوار و انحصار متقابل با پنل ایموجی ✅
- مجوز گالری (Allow all)، بارگذاری ۲۸۰۰+ آیتم، اسکرول/صفحه‌بندی ✅
- انتخاب شماره‌دار ۱..۱۰ و بلاک مورد یازدهم با SnackBar ✅
- composer: پیش‌نمایش، حذف، افزودن، کپشن، ارسال ✅
- ارسال عکس تکی و دو عکس با کپشن + تیک تحویل ✅
- فایل از SAF → composer → بلاک ۲۱MB با پیام سقف ۲۰MB ✅
- باز شدن picker موسیقی (SAF audio) ✅
- حافظه: خروج از گالری ۴۴۴MB → ۳۱۱MB (پس از پاک‌سازی کش تصویر) ✅
- `flutter analyze`: No issues found ✅
- release APK: 63.5MB ✅

**نکات:**
- دو پیام تست روی گروه واقعی ارسال شد: «Test» (تک‌عکس) و «Two» (دوعکس).
- خطای قبلی Gradle مربوط به پروکسی قدیمی در `gradle.properties` بود.
- اسکرین‌شات‌های تست از `/sdcard` پاک شدند.

## ۲۰. نقشهٔ Stage 21.1 (Cache Hygiene)

**مشکل:** پس از استفادهٔ عادی، Android Settings حجم Cache را ۵۴۴MB نشان می‌داد.

**ریشه‌یابی روی دستگاه (debug APK + `run-as`):**
- `cache` = ۵۱۸MB؛ از این مقدار `cache/file_picker` = ۴۹۸MB.
- دو کپی ۲۱۴MB از یک ویدیوی ۲۲۴MB (توسط سقف ۲۰MB رد شده بود، ولی
  `file_picker` قبل از آن فایل را کپی کرده بود)، یک PDF تست ۲۱MB و چند
  عکس/موزیک.
- `cache/image_manager_disk_cache` (بندانگشتی Glide از `photo_manager`) =
  ۱۷MB.
- `cache/libCachedImageData` (`cached_network_image`) = ۲.۹MB.

**علت:** `file_picker` هر فایل انتخاب‌شده را در cache کپی می‌کند و هیچ‌وقت
پاک نمی‌کند؛ نه بعد از ارسال، نه بعد از انصراف/رد شدن به‌خاطر حجم. Glide هم
به‌طور پیش‌فرض تا ۲۵۰MB کش دیسک دارد.

**راه‌حل:**
- فایل جدید `mobile/lib/core/storage/app_cache_manager.dart`.
- در شروع برنامه: پاک‌سازی کل `cache/file_picker`، حذف کپی‌های `pm_*`، و
  اگر کش Glide از ۴۸MB بیشتر باشد `PhotoManager.clearFileCache()`.
- بعد از بستن composer فایل/موسیقی (چه ارسال، چه انصراف): حذف همان
  فایل‌های `cache/file_picker/<timestamp>/` و پوشهٔ خالی.
- بعد از بستن گالری (ارسال/انصراف): با ۴۰۰ms تأخیر، حذف `pm_*` و در صورت
  عبور از ۴۸MB پاک‌سازی کش Glide.
- کش مدیای دائمی (`app_flutter/telegram_media`، سقف ۲۰۰MB) دست‌نخورده
  است؛ پاک‌سازی فقط روی `cache` انجام می‌شود.
- آپلود همچنان از فایل اصلی انجام می‌شود و کپی دائمی برای retry قبل از
  آپلود در `UploadLifecycle` ساخته می‌شود.

**تست روی SM-A528B (Android 14):**
- پس از نصب build جدید و باز شدن برنامه: `cache` از ۵۱۸MB به ۲۱MB رسید ✅
- انتخاب ویدیوی ۲۲۴MB → composer → انصراف: `cache` ۲۳۵MB → ۲۱MB
  (پاک‌سازی فوری) ✅
- ساخت مصنوعی ۶۰MB در کش Glide و ری‌استارت: کش از ۸۱MB به ۳.۲MB رسید
  (سقف ۴۸MB) ✅
- باز شدن گالری ۲۸۵۶ آیتم و بازسازی بندانگشتی‌ها بدون خطا ✅
- `flutter analyze`: No issues found ✅
- release APK (63.5MB) نصب و اجرا شد؛ در Android Settings:
  **Cache = ۵.۰۴MB** (قبلاً ۵۴۴MB)، Data = ۱۰۲MB (کش مدیای دائمی با
  سقف ۲۰۰MB)، Total = ۱۷۸MB ✅

**فایل‌های اصلاح‌شده:**
- `mobile/lib/core/storage/app_cache_manager.dart` (جدید)
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`
- `mobile/lib/features/media/presentation/screens/media_picker_screen.dart`
  (فلگ باز بودن گالری تا پاک‌سازی کش در حین نمایش انجام نشود)
- `mobile/lib/main.dart`

## ۲۱. نقشهٔ Stage 21.2 (Reply Jump Fix)

**مشکل گزارش‌شده:** با کلیک روی پیش‌نمایش «پاسخ» (reply)، اسکرول به ابتدای
پیام ریپلای‌شده انجام نمی‌شد، هایلایت درست کار نمی‌کرد و برای پیام‌های خیلی
قدیمی، لیست به سمت پیام‌های جدید (جهت اشتباه) می‌رفت.

**ریشه‌یابی:**
- روش قبلی `animateToApproximateIndex(index)` با تخمین ثابت **۹۰ پیکسل برای
  هر پیام** اسکرول می‌کرد؛ اما ارتفاع پیام‌ها در این چت متغیر و گاه تا ~۹۰۰
  پیکسل است. برای پیام‌های قدیمی خطا جمع می‌شد و گاهی حتی offset در جهت
  اشتباه محاسبه می‌شد.
- مسیر `GlobalKey`/`ensureVisible` عملاً هرگز اجرا نمی‌شد، چون
  `ListView.builder` آیتم مقصد را (که خارج از viewport بود) نمی‌ساخت.
- فقط ۵۰ پیام آخر در حافظه بارگذاری می‌شد؛ پیام‌های قدیمی‌تر اصلاً در لیست
  نبودند و پرش به آن‌ها ممکن نبود.
- تایمر پاک‌سازی هایلایت (۱.۶ ثانیه) **قبل** از شروع اسکرول فعال می‌شد و
  می‌توانست قبل از رسیدن به مقصد منقضی شود.

**راه‌حل:**
- فایل جدید `mobile/lib/features/chat/presentation/state/message_scroll_controller.dart`:
  - `GlobalKey` پایدار برای هر پیام + اندازه‌گیری ارتفاع واقعی آیتم‌های ساخته‌شده.
  - تخمین offset با نزدیک‌ترین لنگر ساخته‌شده و
    `RenderAbstractViewport.getOffsetToReveal`.
  - پرش تقریبی + تصحیح تکراری در چند فریم تا ساخته‌شدن آیتم مقصد.
  - برای مقاصد چند صفحه‌ای، پرش فوری (`jumpTo`) به‌جای انیمیشن طولانی؛
    انیمیشن از میان صدها آیتم میانی، هم کند است و هم فشار زیادی به رندر
    متن/ایموجی می‌آورد.
  - در پایان `Scrollable.ensureVisible(alignment: 1.0)` که در لیست
    `reverse: true` ابتدای پیام را دقیقاً بالای viewport می‌گذارد.
  - لغو خودکار درخواست قبلی هنگام کلیک پشت‌سرهم روی چند reply.
- هایلایت: بلافاصله روی پیام فعال می‌شود، اما تایمر پاک‌سازی (۲.۲ ثانیه)
  فقط **بعد از رسیدن** به مقصد شروع می‌شود و در صورت شکست پاک می‌شود.
- پیام حذف‌شده: بررسی حافظه ← بارگذاری بازهٔ پیوسته از DB (حداکثر ۱۰۰۰ پیام،
  با کوئری گروهی برای پیوست/واکنش) ← در غیر این صورت SnackBar فارسی
  «این پیام دیگر موجود نیست» و بدون اسکرول/خطا. برای پیام قدیمی‌تر از بازهٔ
  ۱۰۰۰تایی، پیام جداگانهٔ «بسیار قدیمی» نمایش داده می‌شود.
- اصلاح ارجاع‌های کهنهٔ reply وقتی شناسهٔ optimistic با شناسهٔ واقعی سرور
  جایگزین می‌شود (`_repointReplyReferences` + `updateReplyTargetId`).
- حذف کد مردهٔ `ensureVisibleOnKey` و `animateToApproximateIndex` از
  `UnreadFlowController`.

**تست روی دستگاه واقعی (SM-A528B — Android 14، debug build):**
- پرش به پیام ریپلای‌شدهٔ روی صفحه: ابتدای پیام دقیقاً بالای viewport + هایلایت ✅
- پاک‌شدن خودکار هایلایت ۲.۲ ثانیه بعد از رسیدن (نه از لحظهٔ کلیک) ✅
- پرش به پیامی که در حافظه نبود (پیام ۵۱اُم، خارج از پنجرهٔ ۵۰تایی):
  بارگذاری از DB و پرش دقیق + هایلایت ✅
- پرش به پیامی ~۲۰۰ پیام قدیمی‌تر: بارگذاری ۷۴۶ رکورد از DB در ۳۱۲ms و
  رسیدن به ابتدای پیام مقصد + هایلایت ✅
- پیام حذف‌شده: SnackBar «این پیام دیگر موجود نیست (حذف شده است).»
  بدون اسکرول و بدون خطا ✅
- بدون هیچ Exception در `logcat` ✅
- نکتهٔ مهم (مشکل دستگاه، نه کد): پس از اسکرول‌های بسیار سریع و مصنوعی،
  رندر متن روی گوشی به‌هم ریخت؛ بررسی نشان داد این باگ در سطح سیستم است،
  چون صفحهٔ «تنظیمات» اندروید هم به‌جای متن خودش، گلیف‌های خراب چت را نشان
  می‌داد. با `purge-persistent-cache` موقتاً خوب شد ولی با تعامل بعدی برگشت.
  رفع قطعی نیاز به ری‌استارت گوشی دارد (کاربر خودش انجام می‌دهد). این مورد
  به تغییرات Stage 21.2 مربوط نیست و در استفادهٔ عادی رخ نداد.

**تست خودکار:** `mobile/test/message_scroll_controller_test.dart` (۶ تست):
پرش به پیام خیلی قدیمی و قرارگرفتن ابتدای آن بالای صفحه، پیام میانی با
همسایه‌های بلند، بازگشت به پیام جدیدتر از حالت اسکرول‌شده، لیست ۲۰۰تایی با
ارتفاع‌های بزرگ ساخته‌نشده، پیام حذف‌شده بدون خطا/اسکرول، و لغو پرش قبلی.

**نتیجه:** `flutter analyze` → No issues found؛ `flutter test` → همهٔ
تست‌ها سبز. `flutter build apk --release --target-platform android-arm64` →
۲۳.۸MB و نصب موفق روی دستگاه.

**فایل‌ها:**
- `mobile/lib/features/chat/presentation/state/message_scroll_controller.dart` (جدید)
- `mobile/lib/features/chat/presentation/screens/chat_screen.dart`
- `mobile/lib/features/chat/presentation/widgets/chat_message_list.dart`
- `mobile/lib/features/chat/data/chat_repository.dart`
- `mobile/lib/core/database/local_chat_dao.dart`
- `mobile/lib/features/chat/data/socket_event_dispatcher.dart`
- `mobile/lib/features/chat/data/upload_lifecycle.dart`
- `mobile/lib/features/chat/presentation/state/unread_flow_controller.dart`
- `mobile/test/message_scroll_controller_test.dart` (جدید)
