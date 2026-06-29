package email

import (
	"context"
	"fmt"
	"log"
	"net/smtp"

	"github.com/LignacAntony/streampulse/internal/config"
)

// Mailer est la même interface que auth.Mailer — déclarée ici pour permettre
// à NewFromConfig de retourner un type concret sans import circulaire.
// L'assignation dans main.go satisfait structurellement auth.Mailer.
type Mailer interface {
	SendPasswordResetEmail(ctx context.Context, to, rawToken string) error
}

type SMTPMailer struct {
	host     string
	port     string
	username string
	password string
	from     string
	baseURL  string
}

func (m *SMTPMailer) SendPasswordResetEmail(_ context.Context, to, rawToken string) error {
	link := m.baseURL + "/reset-password?token=" + rawToken
	msg := buildPlainEmail(m.from, to, "Réinitialisation de votre mot de passe StreamPulse", link)

	// Auth optionnelle : certains relays locaux (Mailpit, Mailhog) n'en ont pas.
	var auth smtp.Auth
	if m.username != "" {
		auth = smtp.PlainAuth("", m.username, m.password, m.host)
	}

	addr := m.host + ":" + m.port
	if err := smtp.SendMail(addr, auth, m.from, []string{to}, msg); err != nil {
		return fmt.Errorf("email: smtp send: %w", err)
	}
	return nil
}

type LogMailer struct{}

func (l *LogMailer) SendPasswordResetEmail(_ context.Context, to, rawToken string) error {
	log.Printf("[email:dev] password-reset to=%s token=%s", to, rawToken)
	return nil
}

func NewFromConfig(cfg *config.Config) Mailer {
	if cfg.SMTPHost == "" {
		return &LogMailer{}
	}
	return &SMTPMailer{
		host:     cfg.SMTPHost,
		port:     cfg.SMTPPort,
		username: cfg.SMTPUsername,
		password: cfg.SMTPPassword,
		from:     cfg.SMTPFrom,
		baseURL:  cfg.AppBaseURL,
	}
}

func buildPlainEmail(from, to, subject, resetLink string) []byte {
	body := fmt.Sprintf(
		"Bonjour,\r\n\r\n"+
			"Vous avez demandé la réinitialisation de votre mot de passe StreamPulse.\r\n\r\n"+
			"Cliquez sur le lien suivant pour créer un nouveau mot de passe :\r\n"+
			"%s\r\n\r\n"+
			"Ce lien expire dans 1 heure.\r\n\r\n"+
			"Si vous n'avez pas effectué cette demande, ignorez cet email.\r\n\r\n"+
			"L'équipe StreamPulse",
		resetLink,
	)
	raw := fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		from, to, subject, body,
	)
	return []byte(raw)
}
