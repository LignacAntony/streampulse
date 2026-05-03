package main

import (
	"context"

	"github.com/LignacAntony/streampulse/internal/infrastructure/database"
	"github.com/LignacAntony/streampulse/internal/infrastructure/seeder"
)

func main() {
	ctx := context.Background()

	conn := database.Connect(ctx)
	defer conn.Close(ctx)

	seeder.Run(ctx, conn)
}
