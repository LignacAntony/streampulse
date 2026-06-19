ALTER TABLE streams ADD COLUMN stream_key TEXT;

-- Backfill des lignes existantes (dev/seed/legacy) avec une clé unique.
-- gen_random_uuid() est natif PostgreSQL 13+ (pas d'extension requise).
UPDATE streams
SET stream_key = replace(gen_random_uuid()::text, '-', '')
WHERE stream_key IS NULL;

ALTER TABLE streams ALTER COLUMN stream_key SET NOT NULL;
ALTER TABLE streams ADD CONSTRAINT uq_streams_stream_key UNIQUE (stream_key);
