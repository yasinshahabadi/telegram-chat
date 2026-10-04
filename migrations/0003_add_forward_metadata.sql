-- ==========================================================
-- MIGRATION 0003: FORWARD METADATA FOR MESSAGES
-- ==========================================================
-- این ستون‌ها اطلاعات "Forwarded from" را ذخیره می‌کنند که
-- از فیلد forward_origin در Telegram Bot API 7.0+ استخراج می‌شود.
--
-- type:         'channel' | 'chat' | 'user' | 'hidden_user'
-- chat_id:      شناسهٔ کانال/گروه/کاربر (اگر موجود باشد)
-- chat_username: نام کاربری عمومی (بدون @) — برای ساخت deep link
-- chat_title:   نام نمایشی
-- message_id:   شناسهٔ پیام در کانال مبدأ — برای پرش مستقیم
--
-- برای forward از کاربر خصوصی، chat_id ممکن است null باشد.
-- برای forward از کاربر مخفی، همه چیز null است به جز title.

ALTER TABLE messages ADD COLUMN forward_from_type TEXT;
ALTER TABLE messages ADD COLUMN forward_from_chat_id TEXT;
ALTER TABLE messages ADD COLUMN forward_from_chat_username TEXT;
ALTER TABLE messages ADD COLUMN forward_from_chat_title TEXT;
ALTER TABLE messages ADD COLUMN forward_from_message_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_messages_forward_chat
  ON messages(forward_from_chat_id);