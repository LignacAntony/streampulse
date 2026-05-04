ALTER TABLE streams   ADD CONSTRAINT uq_streams_user_title   UNIQUE (user_id, title);
ALTER TABLE tracks    ADD CONSTRAINT uq_tracks_user_title    UNIQUE (user_id, title);
ALTER TABLE playlists ADD CONSTRAINT uq_playlists_user_name  UNIQUE (user_id, name);
