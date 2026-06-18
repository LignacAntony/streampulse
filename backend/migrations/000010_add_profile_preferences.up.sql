ALTER TABLE profiles ADD COLUMN theme TEXT NOT NULL DEFAULT 'dark'
    CHECK (theme IN ('system', 'light', 'dark'));
ALTER TABLE profiles ADD COLUMN notifications_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE profiles ADD COLUMN audio_quality TEXT NOT NULL DEFAULT 'normal'
    CHECK (audio_quality IN ('low', 'normal', 'high'));
