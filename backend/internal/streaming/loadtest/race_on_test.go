//go:build loadtest && race

package loadtest

// raceEnabled distingue une compilation avec le détecteur de données. Il
// multiplie le temps CPU du code Go par un facteur d'un ordre de grandeur, ce
// qui est sans importance pour un test de latence mais rend tout modèle de coût
// CPU faux. Cf. le garde-fou en tête de TestStreamCPU_Sweep.
const raceEnabled = true
