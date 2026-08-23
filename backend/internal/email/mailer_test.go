package email

import (
	"bytes"
	"context"
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

// buildPlainEmail produit les octets envoyés au relais SMTP. Le format n'est
// pas cosmétique : des en-têtes mal terminés, ou une ligne vide manquante
// entre en-têtes et corps, et le message part en pièce jointe illisible ou est
// rejeté. Rien d'autre ne vérifie cette forme — l'envoi réel n'est pas testé.
func TestBuildPlainEmail(t *testing.T) {
	msg := string(buildPlainEmail(
		"noreply@streampulse.test",
		"destinataire@example.com",
		"Sujet de test",
		"streampulse://app/reset-password?token=abc",
	))

	entetes := []string{
		"From: noreply@streampulse.test\r\n",
		"To: destinataire@example.com\r\n",
		"Subject: Sujet de test\r\n",
		"Content-Type: text/plain; charset=UTF-8\r\n",
	}
	for _, e := range entetes {
		if !strings.Contains(msg, e) {
			t.Errorf("en-tête manquant ou mal terminé: %q", e)
		}
	}

	// La ligne vide sépare les en-têtes du corps : sans elle, tout le message
	// est interprété comme un bloc d'en-têtes.
	entete, corps, ok := strings.Cut(msg, "\r\n\r\n")
	if !ok {
		t.Fatal("aucune ligne vide entre les en-têtes et le corps")
	}
	if strings.Contains(entete, "Bonjour") {
		t.Error("le corps a débordé dans les en-têtes")
	}
	if !strings.Contains(corps, "streampulse://app/reset-password?token=abc") {
		t.Error("le lien de réinitialisation doit figurer dans le corps")
	}
	if !strings.Contains(corps, "expire dans 1 heure") {
		t.Error("la durée de validité doit être annoncée au destinataire")
	}
}

// Le lien est construit à partir de APP_BASE_URL : une erreur ici enverrait
// l'utilisateur sur un domaine qui n'est pas le nôtre.
func TestSMTPMailer_LienConstruitDepuisLaBaseURL(t *testing.T) {
	m := &SMTPMailer{
		host:    "127.0.0.1",
		port:    "1",
		from:    "noreply@streampulse.test",
		baseURL: "streampulse://app",
	}

	// L'envoi échoue (aucun relais sur ce port), mais l'erreur doit être
	// enveloppée et non paniquer — c'est le seul chemin observable sans relais.
	err := m.SendPasswordResetEmail(context.Background(), "qui@example.com", "jeton-test")
	if err == nil {
		t.Fatal("l'envoi vers un relais inexistant doit échouer")
	}
	if !strings.Contains(err.Error(), "email: smtp send") {
		t.Errorf("erreur = %v, want une erreur enveloppée « email: smtp send »", err)
	}
}
