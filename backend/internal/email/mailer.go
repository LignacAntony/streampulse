// Package email fournit les implémentations concrètes de l'interface auth.Mailer.
// Il expose deux implémentations :
//   - SMTPMailer : envoi réel via net/smtp (STARTTLS, port 587 par défaut).
//   - LogMailer  : log stdout uniquement, utilisé si SMTP_HOST est absent.
//
// Choisir l'implémentation avec NewFromConfig.
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

// ─── SMTPMailer ──────────────────────────────────────────────────────────────

// SMTPMailer envoie des emails via un relay SMTP (STARTTLS).
type SMTPMailer struct {
	host     string
	port     string
	username string
	password string
	from     string
	baseURL  string
}

// SendPasswordResetEmail construit et envoie l'email de réinitialisation.
func (m *SMTPMailer) SendPasswordResetEmail(_ context.Context, to, rawToken string) error {
	link := m.baseURL + "/reset-password?token=" + rawToken
	msg := buildPlainEmail(m.from, to, "Réinitialisation de votre mot de passe StreamPulse", link)

	auth := smtp.PlainAuth("", m.username, m.password, m.host)
	addr := m.host + ":" + m.port
	if err := smtp.SendMail(addr, auth, m.from, []string{to}, msg); err != nil {
		return fmt.Errorf("email: smtp send: %w", err)
	}
	return nil
}

// ─── LogMailer ───────────────────────────────────────────────────────────────

// LogMailer écrit l'email dans stdout au lieu de l'envoyer (mode dev/test).
type LogMailer struct{}

// SendPasswordResetEmail log le token en clair (dev uniquement).
func (l *LogMailer) SendPasswordResetEmail(_ context.Context, to, rawToken string) error {
	log.Printf("[email:dev] password-reset to=%s token=%s", to, rawToken)
	return nil
}

// ─── Constructeur ─────────────────────────────────────────────────────────────

// NewFromConfig retourne un SMTPMailer si SMTP_HOST est configuré,
// sinon un LogMailer (aucune configuration SMTP requise en développement).
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
