package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"

	"github.com/LignacAntony/streampulse/internal/admin"
	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/broadcaster"
	"github.com/LignacAntony/streampulse/internal/config"
	"github.com/LignacAntony/streampulse/internal/email"
	"github.com/LignacAntony/streampulse/internal/infrastructure/database"
	"github.com/LignacAntony/streampulse/internal/infrastructure/migrator"
	"github.com/LignacAntony/streampulse/internal/infrastructure/seeder"
	"github.com/LignacAntony/streampulse/internal/observability"
	"github.com/LignacAntony/streampulse/internal/openapi"
	"github.com/LignacAntony/streampulse/internal/playlist"
	"github.com/LignacAntony/streampulse/internal/profiles"
	"github.com/LignacAntony/streampulse/internal/shared/httpmw"
	"github.com/LignacAntony/streampulse/internal/streaming"
)

// var _ vérifie à la compilation que *streaming.Service satisfait bien
// admin.LiveStopper, l'interface étroite (ISP) que le service admin consomme
// pour arrêter les lives d'un utilisateur supprimé (STR-191 Task 2).
var _ admin.LiveStopper = (*streaming.Service)(nil)

// var _ vérifie à la compilation que *streaming.Service satisfait bien
// admin.StreamModerator, l'interface étroite (ISP) que le service admin
// consomme pour interrompre un flux lors d'une action de modération (STR-192).
var _ admin.StreamModerator = (*streaming.Service)(nil)

// var _ vérifie à la compilation que le repository admin, seul à savoir écrire
// dans audit_logs, satisfait streaming.AuditRecorder — l'interface étroite que
// le domaine streaming consomme pour journaliser une rotation de clé (STR-228).
var _ streaming.AuditRecorder = (admin.Repository)(nil)

func main() {
	if err := run(); err != nil {
		// Avant config.Load le logger applicatif n'existe pas encore : le
		// global zerolog émet du JSON sur stderr, collectable par Loki.
		log.Fatal().Err(err).Msg("échec du démarrage")
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}

	// Logger racine (STR-163, ADR 018) : JSON structuré sur stdout, posé en
	// global — les call sites sans *http.Request loggent via zerolog/log,
	// les handlers via zerolog.Ctx(r.Context()) (corrélation request_id).
	logger := observability.New(cfg, os.Stdout)
	log.Logger = logger

	// Tracing OTEL (STR-164, ADR 020) : export OTLP/HTTP vers Tempo, noop si
	// OTEL_EXPORTER_OTLP_ENDPOINT est vide (go run local).
	shutdownTracer, err := observability.NewTracer(ctx, cfg)
	if err != nil {
		return fmt.Errorf("tracer: %w", err)
	}
	defer func() {
		flushCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracer(flushCtx); err != nil {
			log.Warn().Err(err).Msg("arrêt du tracer OTEL")
		}
	}()

	// 1. Appliquer les migrations
	migrator.Run()

	// 2. Seed uniquement en développement (connexion simple, one-shot)
	if cfg.IsDev() {
		conn := database.Connect(ctx)
		if err := seeder.Run(ctx, conn); err != nil {
			if cerr := conn.Close(ctx); cerr != nil {
				log.Warn().Err(cerr).Msg("fermeture connexion db")
			}
			return fmt.Errorf("seed: %w", err)
		}
		if cerr := conn.Close(ctx); cerr != nil {
			log.Warn().Err(cerr).Msg("fermeture connexion db")
		}
	}

	// 3. Pool partagé pour les handlers HTTP
	pool, err := database.NewPool(ctx, cfg)
	if err != nil {
		return fmt.Errorf("db pool: %w", err)
	}
	defer pool.Close()

	// 4. Composition des dépendances métier
	authRepo := auth.NewRepository(pool)
	mailer := email.NewFromConfig(cfg)
	authSvc := auth.NewService(authRepo, cfg.JWTSecret, mailer)
	authHandler := auth.NewHandler(authSvc, authSvc, authSvc, authSvc, authSvc, authSvc, authSvc)

	profilesRepo := profiles.NewRepository(pool)
	profilesSvc := profiles.NewService(profilesRepo)
	profilesHandler := profiles.NewHandler(profilesSvc, profilesSvc)

	streamingRepo := streaming.NewRepository(pool)
	streamingKeys := streaming.NewKeyGenerator()
	streamingSessions := streaming.NewLiveSessions(ctx)
	streamingSvc := streaming.NewService(streamingRepo, streamingKeys, streamingSessions)
	streamingHandler := streaming.NewHandler(streamingSvc, cfg.StreamIngestBaseURL, streamingSessions)
	streamingHandler.SetIngestReconnectGrace(cfg.IngestReconnectGrace())
	streamingSessions.SetIngestDisconnectHandler(cfg.IngestReconnectGrace(), func(streamID string) error {
		stopCtx, cancel := context.WithTimeout(context.Background(), cfg.IngestStopTimeout())
		defer cancel()
		if err := streamingSvc.EndDisconnectedStream(stopCtx, streamID); err != nil {
			log.Error().Err(err).Str("stream_id", streamID).
				Msg("streaming: échec de l'arrêt après expiration de l'ingest, nouvelle tentative planifiée")
			return err
		}
		return nil
	})

	// Métriques métier du streaming (STR-166, ADR 022) : le domaine reçoit
	// l'implémentation Prometheus via son interface étroite, et la gauge des
	// directs lit l'état réel du registre de sessions à chaque scrape.
	streamingMetrics := observability.NewStreamingMetrics(prometheus.DefaultRegisterer)
	streamingSessions.SetMetrics(streamingMetrics)
	streamingHandler.SetMetrics(streamingMetrics)
	streamingHandler.SetTrustProxyHeaders(cfg.TrustProxyHeaders)
	observability.RegisterLiveStreamsGauge(prometheus.DefaultRegisterer, streamingSessions.ActiveCount)

	// Réconciliation : les sessions LiveSessions sont en mémoire et reparties
	// vides ; on termine les flux restés 'live' en base (orphelins d'un précédent
	// process) pour éviter une divergence DB/registre.
	if n, err := streamingSvc.ReconcileLiveStreams(ctx); err != nil {
		return fmt.Errorf("reconcile live streams: %w", err)
	} else if n > 0 {
		log.Info().Int64("count", n).Msg("réconciliation: flux live orphelins terminés")
	}

	broadcasterRepo := broadcaster.NewRepository(pool)
	broadcasterSvc := broadcaster.NewService(broadcasterRepo)
	broadcasterHandler := broadcaster.NewHandler(broadcasterSvc, broadcasterSvc, broadcasterSvc, broadcasterSvc)

	// Playlists de l'utilisateur (US-05-02) : CRUD + listing des pistes.
	playlistRepo := playlist.NewRepository(pool)
	playlistSvc := playlist.NewService(playlistRepo)
	playlistHandler := playlist.NewHandler(playlistSvc)

	// Gestion des utilisateurs par un administrateur (US-08-01) : streamingSvc
	// est injecté comme LiveStopper (arrêt des lives en cours à la suppression)
	// et comme StreamModerator (interruption d'un flux en modération, STR-192).
	adminRepo := admin.NewRepository(pool)
	adminSvc := admin.NewService(adminRepo, streamingSvc, streamingSvc)
	adminHandler := admin.NewHandler(adminSvc)

	// `audit_logs` appartient au domaine admin ; le streaming n'en connaît que
	// l'interface étroite AuditRecorder, satisfaite ici par le repository admin
	// (STR-228). Injecté après coup plutôt qu'au constructeur : adminRepo dépend
	// lui-même de streamingSvc via NewService juste au-dessus.
	streamingSvc.SetAuditRecorder(adminRepo)

	// 5. Démarrer le serveur HTTP
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
	})

	// Métriques Prometheus (STR-165, ADR 019) — registre par défaut : inclut
	// les collectors Go (go_goroutines, go_memstats_*) + ceux du middleware.
	mux.Handle("/metrics", promhttp.Handler())

	mux.HandleFunc("/api/auth/register", authHandler.Register)
	mux.HandleFunc("/api/auth/login", authHandler.Login)
	mux.HandleFunc("/api/auth/refresh", authHandler.Refresh)
	mux.Handle("/api/auth/logout", auth.RequireAuth(cfg.JWTSecret, http.HandlerFunc(authHandler.Logout)))
	mux.HandleFunc("/api/auth/forgot-password", authHandler.ForgotPassword)
	mux.HandleFunc("/api/auth/reset-password", authHandler.ResetPassword)
	mux.Handle("/api/auth/me", auth.RequireAuth(cfg.JWTSecret, http.HandlerFunc(authHandler.DeleteAccount)))

	mux.Handle("/api/users/me", auth.RequireAuth(cfg.JWTSecret, http.HandlerFunc(profilesHandler.Me)))

	mux.Handle("/api/broadcaster-requests", auth.RequireAuth(cfg.JWTSecret, http.HandlerFunc(broadcasterHandler.Create)))
	mux.Handle("/api/broadcaster-requests/me", auth.RequireAuth(cfg.JWTSecret, http.HandlerFunc(broadcasterHandler.GetMine)))
	mux.Handle("/api/admin/broadcaster-requests", auth.RequireAuth(cfg.JWTSecret, auth.RequireRole("admin", http.HandlerFunc(broadcasterHandler.List))))
	mux.Handle("/api/admin/broadcaster-requests/{id}/approve", auth.RequireAuth(cfg.JWTSecret, auth.RequireRole("admin", http.HandlerFunc(broadcasterHandler.Approve))))
	mux.Handle("/api/admin/broadcaster-requests/{id}/reject", auth.RequireAuth(cfg.JWTSecret, auth.RequireRole("admin", http.HandlerFunc(broadcasterHandler.Reject))))

	// Gestion des utilisateurs (US-08-01, STR-196) : recherche/liste, activation/
	// désactivation, suppression définitive — réservé aux admins.
	mux.Handle("GET /api/admin/users", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("admin", http.HandlerFunc(adminHandler.List))))
	mux.Handle("PATCH /api/admin/users/{id}", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("admin", http.HandlerFunc(adminHandler.SetActive))))
	mux.Handle("DELETE /api/admin/users/{id}", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("admin", http.HandlerFunc(adminHandler.Delete))))

	// Supervision et interruption des flux actifs par un administrateur
	// (STR-192) : liste de modération (tous les live, publics et privés) et
	// stop audité (journal best-effort côté service).
	mux.Handle("GET /api/admin/streams", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("admin", http.HandlerFunc(adminHandler.ListStreams))))
	mux.Handle("POST /api/admin/streams/{id}/stop", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("admin", http.HandlerFunc(adminHandler.StopStream))))

	// Flux : création réservée au broadcaster ; liste des flux publics en direct
	// accessible sans authentification (découverte en invité, US-04-01).
	mux.Handle("POST /api/streams", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(streamingHandler.Create))))
	mux.Handle("GET /api/streams", http.HandlerFunc(streamingHandler.List))
	// Consultation/modification/suppression d'un flux : auth requise, la
	// propriété est vérifiée dans le service (cf. ADR 013).
	mux.Handle("GET /api/streams/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.Get)))
	mux.Handle("PUT /api/streams/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.Update)))
	mux.Handle("DELETE /api/streams/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.Delete)))
	// Cycle de vie du direct (STR-77) : start/stop réservés au diffuseur propriétaire.
	mux.Handle("PATCH /api/streams/{id}/start", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(streamingHandler.Start))))
	mux.Handle("PATCH /api/streams/{id}/stop", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(streamingHandler.Stop))))
	// Rotation du secret d'ingest (STR-228), propriétaire diffuseur uniquement.
	//
	// Le chemin porte un segment de plus que `{id}/rotate-key` proposé au
	// ticket, pour la raison qui a imposé PUT aux favoris plus bas :
	// POST /api/streams/{id}/rotate-key et POST /api/streams/ingest/{stream_key}
	// ont quatre segments chacun et /api/streams/ingest/rotate-key matcherait les
	// deux — le ServeMux refuse alors d'enregistrer les patterns. Départager par
	// la longueur du chemin plutôt que par la méthode garde POST, qui est le bon
	// verbe ici (chaque appel frappe une clé neuve, rien d'idempotent), et ne se
	// recasse pas si un jour une autre méthode est montée sur `ingest/`.
	mux.Handle("POST /api/streams/{id}/key/rotate", auth.RequireAuth(cfg.JWTSecret,
		auth.RequireRole("broadcaster", http.HandlerFunc(streamingHandler.RotateKey))))
	// Favoris (US-04-05) : ajout/retrait d'un flux et liste « mes favoris ».
	// Action de niveau utilisateur : RequireAuth seul (pas de rôle diffuseur).
	// Ajout en PUT (idempotent) et non POST : un POST /api/streams/{id}/favorite
	// entrerait structurellement en conflit avec POST /api/streams/ingest/{stream_key}
	// dans le ServeMux (le chemin /api/streams/ingest/favorite matcherait les deux).
	mux.Handle("PUT /api/streams/{id}/favorite", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.AddFavorite)))
	mux.Handle("DELETE /api/streams/{id}/favorite", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.RemoveFavorite)))
	mux.Handle("GET /api/users/me/favorites", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.ListFavorites)))
	// Tableau de bord diffuseur (STR-153) : pas de RequireRole("broadcaster") —
	// un non-diffuseur ne possède aucun flux et reçoit [] (cf. ADR 024).
	mux.Handle("GET /api/users/me/streams", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.ListMine)))
	// Statistiques d'audience du flux, propriétaire uniquement (STR-154).
	mux.Handle("GET /api/streams/{id}/stats", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.Stats)))

	// Playlists (US-05-02) : actions de niveau utilisateur, RequireAuth seul (cf. ADR 026).
	mux.Handle("POST /api/playlists", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.Create)))
	mux.Handle("GET /api/playlists", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.List)))
	mux.Handle("GET /api/playlists/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.Get)))
	mux.Handle("PUT /api/playlists/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.Update)))
	mux.Handle("DELETE /api/playlists/{id}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.Delete)))
	mux.Handle("GET /api/playlists/{id}/tracks", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.ListTracks)))
	// Pistes d'une playlist (US-05-03) : ajout, retrait, réordonnancement complet.
	mux.Handle("POST /api/playlists/{id}/tracks", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.AddTrack)))
	mux.Handle("PUT /api/playlists/{id}/tracks", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.ReorderTracks)))
	mux.Handle("DELETE /api/playlists/{id}/tracks/{trackId}", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.RemoveTrack)))
	// Bibliothèque de pistes du demandeur : source du sélecteur d'ajout.
	mux.Handle("GET /api/tracks", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(playlistHandler.ListUserTracks)))
	// Événements SSE du direct (STR-85) : notif d'arrêt aux auditeurs authentifiés.
	mux.Handle("GET /api/streams/{id}/events", auth.RequireAuth(cfg.JWTSecret,
		http.HandlerFunc(streamingHandler.Events)))
	// Ingest du flux audio par le diffuseur (STR-70/71) : auth par stream_key dans
	// le path (pas de JWT), le corps est un push audio continu segmenté en HLS.
	mux.Handle("POST /api/streams/ingest/{stream_key}", http.HandlerFunc(streamingHandler.Ingest))
	// Lecture HLS par l'auditeur (STR-108) : manifeste + segments, PUBLIQUE — le
	// player natif just_audio ne peut pas porter le Bearer. Auth *optionnelle* : un
	// anonyme obtient les flux publics (privé → 404 via GetStream) ; un propriétaire
	// authentifié qui présente un token voit aussi ses propres flux privés.
	// Limiteur de charge (STR-88) : budget partagé entre les deux routes, à
	// l'extérieur de OptionalAuth pour rejeter sous surcharge avant tout traitement.
	// L'ingest n'est pas concerné (un seul push par flux, déjà garanti par
	// errIngestInProgress).
	hlsLimit := streaming.NewMaxInFlight(cfg.HLSMaxConcurrent)
	mux.Handle("GET /api/streams/{id}/playlist.m3u8",
		hlsLimit(auth.OptionalAuth(cfg.JWTSecret, http.HandlerFunc(streamingHandler.Playlist))))
	mux.Handle("GET /api/streams/{id}/segments/{segment}",
		hlsLimit(auth.OptionalAuth(cfg.JWTSecret, http.HandlerFunc(streamingHandler.Segment))))
	// Documentation OpenAPI (Swagger UI + spec brute) — exposée hors production
	// uniquement, pour ne pas publier la surface de l'API sur l'environnement public.
	if !cfg.IsProd() {
		mux.Handle("/swagger", openapi.RedirectHandler())
		mux.Handle(openapi.SpecPath, openapi.SpecHandler())
		mux.Handle("/swagger/", openapi.SwaggerHandler())
	}

	// Chaîne d'observabilité (ADR 018/019/020), de l'extérieur vers le mux :
	// CORS → Tracing (span racine) → AccessLog (logs corrélés trace_id) →
	// Metrics. Les préflights OPTIONS absorbés par CORS ne sont ni tracés,
	// ni loggés, ni comptés.
	handler := httpmw.CORS(cfg.CORSAllowedOrigins, cfg.IsDev(),
		httpmw.Tracing(mux,
			httpmw.AccessLog(logger,
				httpmw.Metrics(prometheus.DefaultRegisterer, mux))))

	srv := &http.Server{
		Addr:         cfg.HTTPAddr(),
		Handler:      handler,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() {
		log.Info().Str("addr", cfg.HTTPAddr()).Str("environment", cfg.GoEnv).Msg("API StreamPulse démarrée")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
		}
	}()

	// Échec de démarrage (port pris, adresse invalide) → on remonte l'erreur ;
	// sinon on attend le signal d'arrêt.
	select {
	case err := <-serveErr:
		return fmt.Errorf("serveur http: %w", err)
	case <-ctx.Done(): // SIGINT / SIGTERM
	}
	log.Info().Msg("arrêt en cours…")

	// StopAll d'abord : ferme les canaux SSE pour débloquer les handlers en vol
	// (srv.Shutdown n'annule pas les contextes de requête). Shutdown draine ensuite
	// les connexions, puis Wait garantit la fin des goroutines de session.
	streamingSessions.StopAll()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("arrêt serveur: %w", err)
	}
	streamingSessions.Wait()
	return nil
}
