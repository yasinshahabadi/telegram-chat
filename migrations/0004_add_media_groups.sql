-- ==========================================================
-- MIGRATION 0004: PENDING MEDIA GROUPS BUFFER
-- ==========================================================
-- تلگرام آلبوم‌ها را به صورت چند webhook جداگانه با
-- media_group_id مشترک می‌فرستد. برای تجمیع آن‌ها به یک پیام
-- واحد در DB، از این جدول به‌عنوان buffer موقت استفاده می‌کنیم.
--
-- جریان:
--   1. اولین item: یک message + attachment + ردیف در این جدول
--   2. item های بعدی: attachment اضافه می‌شود، updated_at تازه می‌شود
--   3. پس از 1.5s سکوت: finalize → sync_event + FCM + پاک کردن این ردیف

CREATE TABLE IF NOT EXISTS pending_media_groups (
  group_id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  sender_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pending_media_groups_updated
  ON pending_media_groups(updated_at);

-- ✅ برای debugging: نگه‌داشتن group_id روی خودِ message
ALTER TABLE messages ADD COLUMN telegram_media_group_id TEXT;
CREATE INDEX IF NOT EXISTS idx_messages_media_group
  ON messages(telegram_media_group_id);