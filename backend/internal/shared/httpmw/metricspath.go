package httpmw

import "regexp"

// otherPath agrège toute requête hors table de routes en une série unique —
// un scan de bot ne doit jamais créer de nouvelle série Prometheus.
const otherPath = "{other}"

// staticPaths : routes sans segment dynamique, labellisées telles quelles.
var staticPaths = map[string]struct{}{
	"/api/auth/register":              {},
	"/api/auth/login":                 {},
	"/api/auth/refresh":               {},
	"/api/auth/logout":                {},
	"/api/auth/forgot-password":       {},
	"/api/auth/reset-password":        {},
	"/api/auth/me":                    {},
	"/api/users/me":                   {},
	"/api/broadcaster-requests":       {},
	"/api/broadcaster-requests/me":    {},
	"/api/admin/broadcaster-requests": {},
	"/api/admin/users":                {},
	"/api/streams":                    {},
}

// dynamicRoutes : ordonnées de la plus spécifique à la plus générale — la
// première qui matche gagne. Toute évolution du routeur (main.go) doit se
// refléter ici, le test TestNormalizePath fait foi.
var dynamicRoutes = []struct {
	re      *regexp.Regexp
	pattern string
}{
	{regexp.MustCompile(`^/api/streams/ingest/[^/]+$`), "/api/streams/ingest/{stream_key}"},
	{regexp.MustCompile(`^/api/streams/[^/]+/playlist\.m3u8$`), "/api/streams/{id}/playlist.m3u8"},
	{regexp.MustCompile(`^/api/streams/[^/]+/segments/[^/]+$`), "/api/streams/{id}/segments/{segment}"},
	{regexp.MustCompile(`^/api/streams/[^/]+/start$`), "/api/streams/{id}/start"},
	{regexp.MustCompile(`^/api/streams/[^/]+/stop$`), "/api/streams/{id}/stop"},
	{regexp.MustCompile(`^/api/streams/[^/]+/events$`), "/api/streams/{id}/events"},
	{regexp.MustCompile(`^/api/streams/[^/]+$`), "/api/streams/{id}"},
	{regexp.MustCompile(`^/api/admin/users/[^/]+$`), "/api/admin/users/{id}"},
	{regexp.MustCompile(`^/api/admin/broadcaster-requests/[^/]+/approve$`), "/api/admin/broadcaster-requests/{id}/approve"},
	{regexp.MustCompile(`^/api/admin/broadcaster-requests/[^/]+/reject$`), "/api/admin/broadcaster-requests/{id}/reject"},
}

// normalizePath réduit un path de requête au pattern de sa route pour servir
// de label Prometheus à cardinalité bornée (ADR 019).
func normalizePath(path string) string {
	if _, ok := staticPaths[path]; ok {
		return path
	}
	for _, route := range dynamicRoutes {
		if route.re.MatchString(path) {
			return route.pattern
		}
	}
	return otherPath
}
