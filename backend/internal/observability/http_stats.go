package observability

import (
	"fmt"

	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
)

// Familles lues par [HTTPStats]. Déclarées par httpmw.Metrics (ADR 019/041).
const (
	httpRequestsMetric      = "http_requests_total"
	httpResponseBytesMetric = "http_response_bytes_total"
	statusLabel             = "status"
)

// HTTPTotals est le cumul des compteurs HTTP depuis le démarrage du process.
//
// Ce sont des **cumuls**, pas des taux : le registre Prometheus ne conserve pas
// d'historique, il ne porte que la valeur courante de chaque compteur. Un taux
// d'erreur calculé à partir de ces nombres est donc « depuis le boot », et non
// « sur les 5 dernières minutes » comme celui des dashboards. La distinction
// doit rester visible du consommateur (ADR 041 §5).
type HTTPTotals struct {
	Requests      int64
	ClientErrors  int64 // 4xx
	ServerErrors  int64 // 5xx
	ResponseBytes int64
}

// HTTPStats lit les compteurs HTTP directement dans le registre Prometheus du
// process (STR-244).
//
// Pourquoi le registre local plutôt qu'une requête à Prometheus : l'API n'aurait
// alors plus seulement Prometheus comme observateur, mais comme **dépendance** —
// une panne du serveur de métriques ferait tomber une route applicative, et le
// déploiement gagnerait une URL de plus à configurer. Le prix est la perte des
// fenêtres temporelles : ce que l'endpoint admin rend est un cumul, ce que
// Grafana montre est un taux. Les deux répondent à des questions différentes.
type HTTPStats struct {
	gatherer prometheus.Gatherer
}

// NewHTTPStats lit le registre passé (prometheus.DefaultGatherer en pratique).
func NewHTTPStats(g prometheus.Gatherer) *HTTPStats {
	return &HTTPStats{gatherer: g}
}

// Totals agrège les compteurs HTTP. Une famille absente n'est pas une erreur :
// au démarrage, aucune requête n'a encore été servie et le registre ne contient
// pas encore les séries — rendre une erreur ferait échouer l'endpoint admin
// pendant les premières secondes de vie du process.
func (s *HTTPStats) Totals() (HTTPTotals, error) {
	families, err := s.gatherer.Gather()
	if err != nil {
		return HTTPTotals{}, fmt.Errorf("observability: gather http metrics: %w", err)
	}

	var out HTTPTotals
	for _, family := range families {
		switch family.GetName() {
		case httpRequestsMetric:
			for _, m := range family.GetMetric() {
				v := int64(m.GetCounter().GetValue())
				out.Requests += v
				switch statusClass(m) {
				case '4':
					out.ClientErrors += v
				case '5':
					out.ServerErrors += v
				}
			}
		case httpResponseBytesMetric:
			for _, m := range family.GetMetric() {
				out.ResponseBytes += int64(m.GetCounter().GetValue())
			}
		}
	}
	return out, nil
}

// statusClass retourne le premier caractère du label `status` d'une série, ou 0
// si le label est absent. Comparer le préfixe évite de reparser un entier dont
// on ne veut que la classe.
func statusClass(m *dto.Metric) byte {
	for _, pair := range m.GetLabel() {
		if pair.GetName() == statusLabel {
			if v := pair.GetValue(); v != "" {
				return v[0]
			}
		}
	}
	return 0
}
