-- Historique d'écoute (US-09-04, STR-203) : une ligne par lecture d'une piste par
-- un utilisateur. Alimente l'algorithme de recommandation « basé sur l'historique
-- d'écoute ». On garde chaque événement (pas un compteur agrégé) pour pouvoir
-- pondérer par la récence et faire évoluer l'algo sans remigrer.
--
-- Portée : les PISTES de la bibliothèque (endpoint authentifié GET
-- /api/tracks/{id}/stream → l'identité du lecteur est connue). Le direct HLS est
-- sans connexion et public (OptionalAuth) : aucun événement par utilisateur n'y
-- est fiable, il reste donc hors de cet historique (cf. ADR 046).
CREATE TABLE IF NOT EXISTS listening_history (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    track_id   UUID        NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    played_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sert le calcul d'affinité et l'exclusion des pistes déjà écoutées, par user et
-- par récence.
CREATE INDEX idx_listening_history_user_played ON listening_history(user_id, played_at DESC);
CREATE INDEX idx_listening_history_user_track  ON listening_history(user_id, track_id);
