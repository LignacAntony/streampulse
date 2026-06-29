-- name: GetMe :one
SELECT u.id::text AS id, u.email, u.role, u.created_at,
       COALESCE(p.pseudo, u.username)          AS pseudo,
       COALESCE(p.bio, '')                     AS bio,
       p.avatar_url,
       COALESCE(p.theme, 'dark')               AS theme,
       COALESCE(p.notifications_enabled, true)  AS notifications_enabled,
       COALESCE(p.audio_quality, 'normal')      AS audio_quality
FROM users u
LEFT JOIN profiles p ON p.user_id = u.id
WHERE u.id = sqlc.arg(id)::uuid AND u.is_active = true;

-- name: UpsertProfile :exec
INSERT INTO profiles (user_id, pseudo, bio, theme, notifications_enabled, audio_quality)
VALUES (
    sqlc.arg(user_id)::uuid,
    sqlc.arg(pseudo)::text,
    sqlc.arg(bio)::text,
    sqlc.arg(theme)::text,
    sqlc.arg(notifications_enabled)::boolean,
    sqlc.arg(audio_quality)::text
)
ON CONFLICT (user_id) DO UPDATE
  SET pseudo = EXCLUDED.pseudo,
      bio = EXCLUDED.bio,
      theme = EXCLUDED.theme,
      notifications_enabled = EXCLUDED.notifications_enabled,
      audio_quality = EXCLUDED.audio_quality,
      updated_at = NOW();
