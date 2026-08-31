package auth

import (
	"context"

	"google.golang.org/api/idtoken"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

// GoogleClaims sont les champs d'un ID token Google que le domaine consomme.
type GoogleClaims struct {
	Sub           string // identifiant Google stable de l'utilisateur
	Email         string
	EmailVerified bool
	Name          string
}

// GoogleVerifier valide un ID token Google et en extrait les claims utiles.
//
// Interface (ISP + DIP) : le service dépend de cette abstraction, jamais de la
// librairie Google directement. Un fake la remplace dans les tests, sans réseau.
type GoogleVerifier interface {
	Verify(ctx context.Context, idToken string) (GoogleClaims, error)
}

// googleTokenVerifier valide le jeton contre les clés publiques de Google via la
// librairie officielle (google.golang.org/api/idtoken) : signature RS256,
// expiration et audience (== clientID) sont contrôlées par la lib.
type googleTokenVerifier struct {
	clientID string
}

// NewGoogleVerifier construit un vérificateur pour l'audience clientID attendue
// (le Client Web OAuth du projet Google Cloud, cf. config GoogleClientID).
func NewGoogleVerifier(clientID string) GoogleVerifier {
	return &googleTokenVerifier{clientID: clientID}
}

func (v *googleTokenVerifier) Verify(ctx context.Context, idToken string) (GoogleClaims, error) {
	payload, err := idtoken.Validate(ctx, idToken, v.clientID)
	if err != nil {
		return GoogleClaims{}, apperror.Unauthorized("invalid google token")
	}

	// idtoken.Validate a déjà vérifié signature, expiration et audience. On
	// contrôle encore l'émetteur, par défense en profondeur.
	if iss, _ := payload.Claims["iss"].(string); iss != "https://accounts.google.com" && iss != "accounts.google.com" {
		return GoogleClaims{}, apperror.Unauthorized("invalid google token issuer")
	}

	email, _ := payload.Claims["email"].(string)
	emailVerified, _ := payload.Claims["email_verified"].(bool)
	name, _ := payload.Claims["name"].(string)

	return GoogleClaims{
		Sub:           payload.Subject,
		Email:         email,
		EmailVerified: emailVerified,
		Name:          name,
	}, nil
}
