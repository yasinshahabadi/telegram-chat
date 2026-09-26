-- افزودن ستون‌های آواتار به جدول users
ALTER TABLE users ADD COLUMN avatar_file_id TEXT;
ALTER TABLE users ADD COLUMN avatar_updated_at INTEGER;

CREATE INDEX IF NOT EXISTS idx_users_avatar ON users(avatar_updated_at);