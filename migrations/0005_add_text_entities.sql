-- ==========================================================
-- MIGRATION 0005: TEXT ENTITIES (BOLD, LINKS, BLOCKQUOTE, ...)
-- ==========================================================
-- تلگرام در هر پیام آرایه‌ای از entities می‌فرستد که مشخص می‌کند
-- کدام بازهٔ متن bold است، کدام لینک، کدام blockquote و ...
-- این ستون آن آرایه را به صورت JSON ذخیره می‌کند.
--
-- ساختار هر entity (مثال):
--   { "type": "bold", "offset": 0, "length": 5 }
--   { "type": "text_link", "offset": 10, "length": 8, "url": "https://..." }
--   { "type": "blockquote", "offset": 20, "length": 40 }
--
-- offset و length بر حسب UTF-16 code units هستند (مطابق Bot API).

ALTER TABLE messages ADD COLUMN text_entities TEXT;