-- Unicité de la position d'une piste au sein d'une playlist (US-05-03).
--
-- DEFERRABLE INITIALLY DEFERRED : le réordonnancement réécrit toutes les
-- positions d'une playlist dans une seule transaction ; les états intermédiaires
-- contiennent forcément des doublons (déplacer la piste 3 en position 0 avant
-- d'avoir décalé les autres). La contrainte n'est donc vérifiée qu'au COMMIT.
ALTER TABLE playlist_tracks
    ADD CONSTRAINT uq_playlist_tracks_position UNIQUE (playlist_id, position)
    DEFERRABLE INITIALLY DEFERRED;
