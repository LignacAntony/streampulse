package email

import (
	"bytes"
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"github.com/LignacAntony/streampulse/internal/config"
)

const (
	testToken = "jeton-de-reinitialisation-secret"
	testTo    = "user@streampulse.dev"
)

// TestLogMailer_NeJournaliseJamaisLeJeton est le test de sécurité de ce package.
//
// LogMailer existe pour permettre le workflow de réinitialisation sans relay.
// Sa version initiale passait le jeton à zerolog : il atterrissait donc dans
// Loki, indexé et conservé sans limite de rétention, et quiconque lisait les
// logs pouvait prendre la main sur tout compte en ayant demandé une.
//
// Le jeton ne doit atteindre le logger structuré dans aucune des deux branches.
func TestLogMailer_NeJournaliseJamaisLeJeton(t *testing.T) {
	cases := []struct {
		name   string
		pretty bool
	}{
		{name: "sans sortie console lisible", pretty: false},
		{name: "avec sortie console lisible", pretty: true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var logs bytes.Buffer
			logger := zerolog.New(&logs)
			ctx := logger.WithContext(t.Context())

			var out bytes.Buffer
			m := &LogMailer{pretty: tc.pretty, baseURL: "streampulse://app", out: &out}

			if err := m.SendPasswordResetEmail(ctx, testTo, testToken); err != nil {
				t.Fatalf("SendPasswordResetEmail: %v", err)
			}

			if strings.Contains(logs.String(), testToken) {
				t.Errorf("le jeton est passé dans le logger structuré, donc dans Loki:\n%s", logs.String())
			}
		})
	}
}

// TestLogMailer_EcritLeLienHorsDuLogger : en mode console lisible, le lien doit
// être exploitable par le développeur — c'est la raison d'être du mode — mais
// sur la sortie fournie, jamais dans le logger.
func TestLogMailer_EcritLeLienHorsDuLogger(t *testing.T) {
	var logs bytes.Buffer
	ctx := zerolog.New(&logs).WithContext(t.Context())

	var out bytes.Buffer
	m := &LogMailer{pretty: true, baseURL: "streampulse://app", out: &out}

	if err := m.SendPasswordResetEmail(ctx, testTo, testToken); err != nil {
		t.Fatalf("SendPasswordResetEmail: %v", err)
	}

	got := out.String()
	if !strings.Contains(got, testToken) {
		t.Errorf("le lien de développement ne contient pas le jeton, le workflow est inutilisable:\n%s", got)
	}
	if !strings.Contains(got, testTo) {
		t.Errorf("le destinataire n'apparaît pas, on ne sait pas à qui appartient le lien:\n%s", got)
	}
}

// TestLogMailer_SansConsoleLisibleNEcritRien vérifie l'autre branche : hors mode
// console, rien ne doit sortir sur `out` non plus — un conteneur redirige sa
// sortie standard vers la collecte de logs, donc écrire là reviendrait à
// contourner la protection.
func TestLogMailer_SansConsoleLisibleNEcritRien(t *testing.T) {
	var logs bytes.Buffer
	ctx := zerolog.New(&logs).WithContext(t.Context())

	var out bytes.Buffer
	m := &LogMailer{pretty: false, baseURL: "streampulse://app", out: &out}

	if err := m.SendPasswordResetEmail(ctx, testTo, testToken); err != nil {
		t.Fatalf("SendPasswordResetEmail: %v", err)
	}

	if out.Len() != 0 {
		t.Errorf("sortie non vide hors mode console lisible: %q", out.String())
	}
	// L'avertissement doit exister : un développeur sans relay doit comprendre
	// pourquoi il ne reçoit rien, plutôt que de croire à un bug.
	if !strings.Contains(logs.String(), "SMTP") {
		t.Errorf("aucun avertissement journalisé, l'absence d'email est inexplicable:\n%s", logs.String())
	}
}

// TestNewFromConfig_ChoisitLeMailer verrouille la sélection : un SMTP_HOST
// renseigné doit produire un vrai envoi, jamais le mailer de développement.
func TestNewFromConfig_ChoisitLeMailer(t *testing.T) {
	if m := NewFromConfig(&config.Config{SMTPHost: ""}); !isLogMailer(m) {
		t.Errorf("SMTP_HOST vide: got %T, want *LogMailer", m)
	}
	if m := NewFromConfig(&config.Config{SMTPHost: "mailpit"}); isLogMailer(m) {
		t.Error("SMTP_HOST renseigné: LogMailer sélectionné, les emails ne partiraient pas")
	}
}

func isLogMailer(m Mailer) bool {
	_, ok := m.(*LogMailer)
	return ok
}
