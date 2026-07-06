package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

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

func main() {
	if err := run(); err != nil {
		log.Fatalf("%v", err)
	}
}

func run() error {
	ctx := context.Background()

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
	streamingSvc := streaming.NewService(streamingRepo, streamingKeys)
	streamingHandler := streaming.NewHandler(streamingSvc, cfg.StreamIngestBaseURL)

	broadcasterRepo := broadcaster.NewRepository(pool)
	broadcasterSvc := broadcaster.NewService(broadcasterRepo)
	broadcasterHandler := broadcaster.NewHandler(broadcasterSvc, broadcasterSvc, broadcasterSvc, broadcasterSvc)

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

	log.Printf("API StreamPulse démarrée sur %s (env=%s)", cfg.HTTPAddr(), cfg.GoEnv)
	if err := srv.ListenAndServe(); err != nil {
		return fmt.Errorf("serveur http: %w", err)
	}

	return nil
}
