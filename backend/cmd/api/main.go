package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/LignacAntony/streampulse/internal/infrastructure/database"
	"github.com/LignacAntony/streampulse/internal/infrastructure/migrator"
	"github.com/LignacAntony/streampulse/internal/infrastructure/seeder"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("%v", err)
	}
}

func run() error {
	ctx := context.Background()

	// 1. Appliquer les migrations
	migrator.Run()

	// 2. Seed uniquement en développement
	if os.Getenv("GO_ENV") == "development" {
		conn := database.Connect(ctx)
		defer func() {
			if err := conn.Close(ctx); err != nil {
				log.Printf("db close: %v", err)
			}
		}()

		if err := seeder.Run(ctx, conn); err != nil {
			return fmt.Errorf("seed: %w", err)
		}
	}

	// 3. Démarrer le serveur HTTP
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

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Println("API StreamPulse démarrée sur :8080")
	if err := srv.ListenAndServe(); err != nil {
		return fmt.Errorf("serveur http: %w", err)
	}

	return nil
}
