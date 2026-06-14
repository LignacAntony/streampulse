package openapi

import (
	_ "embed"
	"net/http"

	"github.com/swaggest/swgui/v5emb"
)

const (
	SpecPath    = "/swagger/openapi.yaml"
	SwaggerPath = "/swagger/"
)

//go:embed openapi.yaml
var specYAML []byte

func SpecYAML() []byte {
	out := make([]byte, len(specYAML))
	copy(out, specYAML)
	return out
}

func SpecHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", http.MethodGet+", "+http.MethodHead)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Content-Type", "application/yaml; charset=utf-8")
		if r.Method == http.MethodHead {
			return
		}
		_, _ = w.Write(specYAML)
	})
}

func SwaggerHandler() http.Handler {
	return v5emb.New("StreamPulse API", SpecPath, SwaggerPath)
}

func RedirectHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, SwaggerPath, http.StatusPermanentRedirect)
	})
}
