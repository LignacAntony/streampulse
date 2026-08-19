package httpmw

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

// RateLimit borne le nombre de requêtes par couple (adresse cliente, route) sur
// une fenêtre glissante approximée par un seau à jetons.
//
// Monté sur /api/auth/* : sans lui, rien ne limitait les tentatives de connexion
// (force brute sur les mots de passe), les inscriptions en masse, ni les demandes
// de réinitialisation (bombardement d'emails vers une adresse tierce). Le
// limiteur de streaming/limiter.go ne couvre que la concurrence HLS et ne borne
// aucun débit.
//
// Le choix d'un seau plutôt qu'un compteur fixe est délibéré : un compteur par
// fenêtre autorise deux fois la limite à cheval sur deux fenêtres.
//
// La clé inclut la route, et pas seulement l'adresse. Derrière un reverse proxy,
// ClientIP rend l'IP publique : tous les utilisateurs d'un même NAT — Wi-Fi
// d'école, d'entreprise, de café — la partagent. Un seau unique par adresse leur
// ferait partager un seul budget entre connexion, inscription et renouvellement
// de jeton, et trente personnes ouvrant l'app à la même heure s'épuiseraient
// mutuellement. Isoler par route évite au moins qu'un usage automatique assèche
// le budget d'une action humaine.
//
// Cela ne supprime pas le problème du NAT sur une route donnée : la vraie
// réponse pour la connexion et la réinitialisation serait un second facteur sur
// l'email visé plutôt que sur la seule adresse. À traiter séparément.
//
// Volontairement en mémoire, donc par instance. Le déploiement est mono-instance
// (ADR 013) ; un parc en exigerait un partagé, et ce serait une autre décision.
type RateLimit struct {
	capacity int
	refill   time.Duration

	mu      sync.Mutex
	buckets map[string]*bucket

	// trustProxy : cf. ClientIP. Faux par défaut.
	trustProxy bool
	now        func() time.Time // injectable pour les tests
}

type bucket struct {
	tokens   float64
	lastSeen time.Time
}

// NewRateLimit construit un limiteur autorisant capacity requêtes immédiates,
// reconstituées à raison d'une par refill.
func NewRateLimit(capacity int, refill time.Duration, trustProxy bool) *RateLimit {
	return &RateLimit{
		capacity:   capacity,
		refill:     refill,
		buckets:    make(map[string]*bucket),
		trustProxy: trustProxy,
		now:        time.Now,
	}
}

// ClientIP identifie l'appelant.
//
// Dernier maillon de X-Forwarded-For, et non le premier : Caddy n'écrase pas
// l'en-tête par défaut, il y ajoute l'IP observée. Prendre le premier laisserait
// un client poser sa propre valeur et obtenir un seau neuf à chaque requête —
// le limiteur ne limiterait plus rien.
func ClientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			if idx := strings.LastIndex(fwd, ","); idx >= 0 {
				return strings.TrimSpace(fwd[idx+1:])
			}
			return strings.TrimSpace(fwd)
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// allow consomme un jeton pour key. Retourne false et le délai à attendre si le
// seau est vide.
func (rl *RateLimit) allow(key string) (bool, time.Duration) {
	now := rl.now()

	rl.mu.Lock()
	defer rl.mu.Unlock()

	b, ok := rl.buckets[key]
	if !ok {
		b = &bucket{tokens: float64(rl.capacity), lastSeen: now}
		rl.buckets[key] = b
	}

	// Reconstitution proportionnelle au temps écoulé, plafonnée à la capacité.
	if elapsed := now.Sub(b.lastSeen); elapsed > 0 {
		b.tokens += elapsed.Seconds() / rl.refill.Seconds()
		if b.tokens > float64(rl.capacity) {
			b.tokens = float64(rl.capacity)
		}
	}
	b.lastSeen = now

	if b.tokens < 1 {
		missing := 1 - b.tokens
		return false, time.Duration(missing * float64(rl.refill))
	}
	b.tokens--
	return true, 0
}

// evict purge les seaux pleins et inactifs. Sans elle la table croîtrait avec le
// nombre d'IP vues — une adresse qui n'a pas consommé depuis assez longtemps est
// indiscernable d'une inconnue.
func (rl *RateLimit) evict() {
	cutoff := rl.now().Add(-time.Duration(rl.capacity) * rl.refill)

	rl.mu.Lock()
	defer rl.mu.Unlock()
	for key, b := range rl.buckets {
		if b.lastSeen.Before(cutoff) {
			delete(rl.buckets, key)
		}
	}
}

// Middleware refuse en 429 les requêtes au-delà de la limite.
func (rl *RateLimit) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// La route entre dans la clé : les chemins d'auth sont fixes, r.URL.Path
		// suffit et ne dépend pas de la sémantique des motifs du routeur.
		ok, retryAfter := rl.allow(ClientIP(r, rl.trustProxy) + "|" + r.URL.Path)
		if !ok {
			seconds := int(retryAfter.Seconds())
			if seconds < 1 {
				seconds = 1
			}
			w.Header().Set("Retry-After", strconv.Itoa(seconds))
			httpjson.WriteError(w, r, httpjson.StatusError(
				http.StatusTooManyRequests,
				"rate_limited",
				"trop de tentatives, réessayez dans un instant",
			))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// StartEviction lance la purge périodique jusqu'à l'annulation de done.
func (rl *RateLimit) StartEviction(done <-chan struct{}, every time.Duration) {
	go func() {
		t := time.NewTicker(every)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				rl.evict()
			}
		}
	}()
}
