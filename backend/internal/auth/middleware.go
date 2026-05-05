package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

type contextKey int

const (
	contextKeyUserID contextKey = iota
	contextKeyRole
)

// UserIDFromContext retourne l'ID de l'utilisateur authentifié depuis le contexte.
func UserIDFromContext(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(contextKeyUserID).(string)
	return v, ok
}

// RoleFromContext retourne le rôle de l'utilisateur authentifié depuis le contexte.
func RoleFromContext(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(contextKeyRole).(string)
	return v, ok
}

// RequireAuth valide le JWT Bearer et injecte userID + role dans le contexte.
// Retourne 401 et n'appelle pas next si le token est absent ou invalide.
func RequireAuth(jwtSecret string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tokenStr, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || tokenStr == "" {
			httpjson.WriteError(w, r, apperror.Unauthorized("missing bearer token"))
			return
		}

		claims, err := ParseAccessToken(tokenStr, jwtSecret)
		if err != nil {
			httpjson.WriteError(w, r, err)
			return
		}

		ctx := context.WithValue(r.Context(), contextKeyUserID, claims.UserID)
		ctx = context.WithValue(ctx, contextKeyRole, claims.Role)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequireRole vérifie que le rôle stocké dans le contexte atteint le niveau requis.
// Doit être chaîné après RequireAuth.
func RequireRole(required string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		role, ok := RoleFromContext(r.Context())
		if !ok {
			httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
			return
		}
		if !hasRole(role, required) {
			httpjson.WriteError(w, r, apperror.Forbidden("insufficient role"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// hasRole implémente une hiérarchie simple : admin > broadcaster > user > anonymous.
func hasRole(userRole, required string) bool {
	rank := map[string]int{
		"anonymous":   0,
		"user":        1,
		"broadcaster": 2,
		"admin":       3,
	}
	return rank[userRole] >= rank[required]
}
