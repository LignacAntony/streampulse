package seeder

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

type userSeed struct {
	email    string
	username string
	password string
	role     string
}

func seedUsers(ctx context.Context, tx pgx.Tx) error {
	log.Println("seed users...")

	users := []userSeed{
		{"admin@streampulse.dev", "admin", "Password123!", "admin"},
		{"broadcaster@streampulse.dev", "broadcaster", "Password123!", "broadcaster"},
		{"user1@streampulse.dev", "user1", "Password123!", "user"},
		{"user2@streampulse.dev", "user2", "Password123!", "user"},
	}

	for _, u := range users {
		hash, err := bcrypt.GenerateFromPassword([]byte(u.password), 12)
		if err != nil {
			return fmt.Errorf("bcrypt %s: %w", u.email, err)
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO users (email, username, password_hash, role)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (email) DO NOTHING
		`, u.email, u.username, string(hash), u.role)
		if err != nil {
			return fmt.Errorf("insert user %s: %w", u.email, err)
		}

		log.Printf("  ✓ user %s (%s)", u.username, u.role)
	}

	return nil
}
