ALTER TABLE streams   DROP CONSTRAINT IF EXISTS uq_streams_user_title;
ALTER TABLE tracks    DROP CONSTRAINT IF EXISTS uq_tracks_user_title;
ALTER TABLE playlists DROP CONSTRAINT IF EXISTS uq_playlists_user_name;
