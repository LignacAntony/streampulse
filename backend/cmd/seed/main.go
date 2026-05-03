package main

import (
	"context"
	"log"

	"github.com/LignacAntony/streampulse/internal/infrastructure/database"
	"github.com/LignacAntony/streampulse/internal/infrastructure/seeder"
)

func main() {
	ctx := context.Background()

	conn := database.Connect(ctx)
	defer func() {
		if err := conn.Close(ctx); err != nil {
			log.Printf("db close: %v", err)
		}
	}()

	seeder.Run(ctx, conn)
}
