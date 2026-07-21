package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/LignacAntony/streampulse/internal/admin"
	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/broadcaster"
	"github.com/LignacAntony/streampulse/internal/config"
	"github.com/LignacAntony/streampulse/internal/email"
	"github.com/LignacAntony/streampulse/internal/infrastructure/database"
	"github.com/LignacAntony/streampulse/internal/infrastructure/migrator"
	"github.com/LignacAntony/streampulse/internal/infrastructure/seeder"
	"github.com/LignacAntony/streampulse/internal/openapi"
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

func main() {
	if err := run(); err != nil {
		log.Fatalf("%v", err)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}

	// 1. Appliquer les migrations
	migrator.Run()

	// 2. Seed uniquement en développement (connexion simple, one-shot)
	if cfg.IsDev() {
		conn := database.Connect(ctx)
		if err := seeder.Run(ctx, conn); err != nil {
			if cerr := conn.Close(ctx); cerr != nil {
				log.Printf("db close: %v", cerr)
			}
			return fmt.Errorf("seed: %w", err)
		}
		if cerr := conn.Close(ctx); cerr != nil {
			log.Printf("db close: %v", cerr)
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

	// Réconciliation : les sessions LiveSessions sont en mémoire et reparties
	// vides ; on termine les flux restés 'live' en base (orphelins d'un précédent
	// process) pour éviter une divergence DB/registre.
	if n, err := streamingSvc.ReconcileLiveStreams(ctx); err != nil {
		return fmt.Errorf("reconcile live streams: %w", err)
	} else if n > 0 {
		log.Printf("réconciliation: %d flux live orphelin(s) terminé(s)", n)
	}

	broadcasterRepo := broadcaster.NewRepository(pool)
	broadcasterSvc := broadcaster.NewService(broadcasterRepo)
	broadcasterHandler := broadcaster.NewHandler(broadcasterSvc, broadcasterSvc, broadcasterSvc, broadcasterSvc)

	// Gestion des utilisateurs par un administrateur (US-08-01) : streamingSvc
	// est injecté comme LiveStopper (arrêt des lives en cours à la suppression)
	// et comme StreamModerator (interruption d'un flux en modération, STR-192).
	adminRepo := admin.NewRepository(pool)
	adminSvc := admin.NewService(adminRepo, streamingSvc, streamingSvc)
	adminHandler := admin.NewHandler(adminSvc)

	// 5. Démarrer le serveur HTTP
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]string{"status": "ok"}); err != nil {
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		w.WriteHeader(http.StatusOK)
	})

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

	handler := httpmw.CORS(cfg.CORSAllowedOrigins, cfg.IsDev(), mux)

	srv := &http.Server{
		Addr:         cfg.HTTPAddr(),
		Handler:      handler,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() {
		log.Printf("API StreamPulse démarrée sur %s (env=%s)", cfg.HTTPAddr(), cfg.GoEnv)
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
	log.Println("arrêt en cours…")

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
