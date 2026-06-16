// Package httpmw regroupe les middlewares HTTP transverses, applicables
// autour du mux racine (CORS, etc.).
package httpmw

import (
	"net/http"
	"net/url"
	"strings"
)

const (
	allowMethods = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
	allowHeaders = "Authorization, Content-Type"
	maxAgeSecs   = "600"
)

func CORS(allowedOrigins []string, devMode bool, next http.Handler) http.Handler {
	allowed := make(map[string]bool, len(allowedOrigins))
	for _, o := range allowedOrigins {
		allowed[o] = true
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && originAllowed(origin, allowed, devMode) {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Add("Vary", "Origin")
			h.Set("Access-Control-Allow-Methods", allowMethods)
			h.Set("Access-Control-Allow-Headers", allowHeaders)
			h.Set("Access-Control-Max-Age", maxAgeSecs)
		}

		// Préflight : on répond immédiatement, sans atteindre le mux.
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func originAllowed(origin string, allowed map[string]bool, devMode bool) bool {
	if allowed[origin] {
		return true
	}
	if !devMode {
		return false
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	host := u.Hostname()
	return host == "localhost" || host == "127.0.0.1" || strings.EqualFold(host, "[::1]") || host == "::1"
}
