package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/thierrymaignan/streampulse/internal/infrastructure/database"
	"github.com/thierrymaignan/streampulse/internal/infrastructure/migrator"
	"github.com/thierrymaignan/streampulse/internal/infrastructure/seeder"
)

func main() {
	ctx := context.Background()

	// 1. Appliquer les migrations
	migrator.Run()

	// 2. Seed uniquement en développement
	if os.Getenv("GO_ENV") == "development" {
		conn := database.Connect(ctx)
		defer conn.Close(ctx)
		seeder.Run(ctx, conn)
	}

	// 3. Démarrer le serveur HTTP
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		w.WriteHeader(http.StatusOK)
	})

	log.Println("API StreamPulse démarrée sur :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
