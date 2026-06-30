ALTER TABLE streams DROP CONSTRAINT IF EXISTS uq_streams_stream_key;
ALTER TABLE streams DROP COLUMN IF EXISTS stream_key;
