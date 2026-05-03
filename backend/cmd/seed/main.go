package main

import (
	"context"

	"github.com/thierrymaignan/streampulse/internal/infrastructure/database"
	"github.com/thierrymaignan/streampulse/internal/infrastructure/seeder"
)

func main() {
	ctx := context.Background()

	conn := database.Connect(ctx)
	defer conn.Close(ctx)

	seeder.Run(ctx, conn)
}
