package apperror

import (
	"errors"
	"fmt"
	"testing"
)

func TestAsAndIsCode(t *testing.T) {
	cause := errors.New("db failed")
	err := Internal("insert user", cause)

	appErr, ok := As(err)
	if !ok {
		t.Fatal("As() did not find app error")
	}
	if appErr.Code != CodeInternal {
		t.Fatalf("code: want %s, got %s", CodeInternal, appErr.Code)
	}
	if !errors.Is(err, cause) {
		t.Fatal("wrapped cause is not discoverable")
	}
	if !IsCode(err, CodeInternal) {
		t.Fatalf("IsCode() should match %s", CodeInternal)
	}
}

// Les constructeurs sont la surface publique du paquet : chacun doit poser le
// bon code, et c'est le code qui décide du statut HTTP en sortie. Une
// inversion ici transformerait silencieusement un 404 en 403.
func TestConstructeurs_PosentLeBonCode(t *testing.T) {
	cas := []struct {
		nom  string
		err  *Error
		want Code
	}{
		{"InvalidArgument", InvalidArgument("m"), CodeInvalidArgument},
		{"Unauthorized", Unauthorized("m"), CodeUnauthorized},
		{"Forbidden", Forbidden("m"), CodeForbidden},
		{"NotFound", NotFound("m"), CodeNotFound},
		{"UnsupportedMedia", UnsupportedMedia("m"), CodeUnsupportedMedia},
		{"Conflict", Conflict("m"), CodeConflict},
		{"New", New(CodeInternal, "m"), CodeInternal},
	}
	for _, tc := range cas {
		t.Run(tc.nom, func(t *testing.T) {
			if tc.err.Code != tc.want {
				t.Errorf("code = %q, want %q", tc.err.Code, tc.want)
			}
			if tc.err.Message != "m" {
				t.Errorf("message = %q, want %q", tc.err.Message, "m")
			}
			if !IsCode(tc.err, tc.want) {
				t.Errorf("IsCode ne reconnaît pas %q", tc.want)
			}
		})
	}
}

func TestError_Message(t *testing.T) {
	sans := NotFound("introuvable")
	if got, want := sans.Error(), "not_found: introuvable"; got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}

	cause := errors.New("cause interne")
	avec := Wrap(CodeInternal, "échec", cause)
	if got, want := avec.Error(), "internal: échec: cause interne"; got != want {
		t.Errorf("Error() = %q, want %q", got, want)
	}

	// Un pointeur nul ne doit pas paniquer : Error() est appelé sur des valeurs
	// qui traversent des interfaces, où le nil typé passe inaperçu.
	var nul *Error
	if got := nul.Error(); got != "" {
		t.Errorf("Error() sur nil = %q, want vide", got)
	}
	if nul.Unwrap() != nil {
		t.Error("Unwrap() sur nil doit rendre nil")
	}
}

// Coded attache un code public spécifique sans toucher au code qui décide du
// statut : c'est ce qui laisse le mobile distinguer « quota atteint » d'un
// refus d'accès banal, tout en gardant un 403.
func TestCoded_NeChangePasLeCodeDeStatut(t *testing.T) {
	err := Forbidden("quota dépassé").Coded("storage_quota_exceeded")

	if err.Code != CodeForbidden {
		t.Errorf("code = %q, want %q — Coded ne doit pas changer le statut", err.Code, CodeForbidden)
	}
	if err.PublicCode != "storage_quota_exceeded" {
		t.Errorf("PublicCode = %q, want storage_quota_exceeded", err.PublicCode)
	}
}

// As et IsCode doivent traverser un wrapping fmt.Errorf : les repositories
// enveloppent systématiquement leurs erreurs.
func TestAs_EtIsCode_TraversentLeWrapping(t *testing.T) {
	enveloppe := fmt.Errorf("repo: contexte: %w", Conflict("déjà pris"))

	got, ok := As(enveloppe)
	if !ok {
		t.Fatal("As doit retrouver l'erreur applicative sous un wrapping")
	}
	if got.Code != CodeConflict {
		t.Errorf("code = %q, want %q", got.Code, CodeConflict)
	}
	if !IsCode(enveloppe, CodeConflict) {
		t.Error("IsCode doit traverser le wrapping")
	}
	if IsCode(enveloppe, CodeNotFound) {
		t.Error("IsCode ne doit pas reconnaître un autre code")
	}

	if _, ok := As(errors.New("erreur quelconque")); ok {
		t.Error("As ne doit rien retrouver dans une erreur non applicative")
	}
	if IsCode(nil, CodeConflict) {
		t.Error("IsCode(nil) doit être faux")
	}
}
