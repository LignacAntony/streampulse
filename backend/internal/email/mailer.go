package email

import (
	"context"
	"fmt"
	"io"
	"net/smtp"
	"os"

	"github.com/rs/zerolog"

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

// LogMailer écrit le lien de réinitialisation sur la sortie standard au lieu de
// l'envoyer. Réservé au développement : config.validate refuse désormais un
// SMTP_HOST vide en production, précisément pour qu'il ne puisse pas y être
// sélectionné.
//
// Le lien est écrit hors du logger structuré. Un jeton passé à zerolog
// atterrirait dans Loki, indexé et conservé sans limite ; ici il reste dans le
// terminal du développeur, et n'est produit que si la sortie console lisible
// est active — c'est-à-dire jamais en conteneur (STR-172).
type LogMailer struct {
	pretty  bool
	baseURL string
	out     io.Writer // injectable pour les tests ; os.Stdout si nil
}

func (l *LogMailer) SendPasswordResetEmail(ctx context.Context, to, rawToken string) error {
	if !l.pretty {
		zerolog.Ctx(ctx).Warn().
			Str("to", to).
			Msg("email: SMTP non configuré, réinitialisation non envoyée (activer LOG_PRETTY pour afficher le lien en dev)")
		return nil
	}

	out := l.out
	if out == nil {
		out = os.Stdout
	}
	_, err := fmt.Fprintf(out, "\n[dev] réinitialisation pour %s\n[dev] %s/reset-password?token=%s\n\n", to, l.baseURL, rawToken)
	if err != nil {
		return fmt.Errorf("email: écriture du lien de développement: %w", err)
	}
	return nil
}

func NewFromConfig(cfg *config.Config) Mailer {
	if cfg.SMTPHost == "" {
		return &LogMailer{pretty: cfg.LogPretty, baseURL: cfg.AppBaseURL}
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
