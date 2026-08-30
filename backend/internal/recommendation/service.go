// Package recommendation implémente une recommandation « simple » de pistes
// basée sur l'historique d'écoute de l'utilisateur (US-09-04, STR-203).
//
// Deux responsabilités :
//   - enregistrer un événement d'écoute (RecordPlay), appelé best-effort par le
//     domaine track à la lecture d'une piste ;
//   - produire une liste de pistes recommandées (Recommend) pour le demandeur.
//
// L'algorithme lui-même vit dans la requête SQL (repository) ; le service ne fait
// que traduire les scores bruts en une raison lisible et fixer la taille de liste.
package recommendation

import "context"

// defaultLimit borne le nombre de recommandations rendues. Volontairement modeste :
// une section « Pour toi » se parcourt d'un coup d'œil, pas une page infinie.
const defaultLimit = 20

// RecommendedTrack est une piste proposée à l'utilisateur, accompagnée d'une
// raison lisible (« Parce que vous écoutez souvent X »).
type RecommendedTrack struct {
	ID        string
	Title     string
	Artist    *string
	DurationS *int
	Reason    string
}

// ScoredTrack est une piste candidate avec les signaux bruts calculés par le
// repository : nombre d'écoutes de son artiste, si elle n'a jamais été écoutée, et
// si elle appartient à un autre utilisateur (piste publique). Le service en dérive
// la raison ; ces champs ne sortent pas du domaine.
type ScoredTrack struct {
	ID          string
	Title       string
	Artist      *string
	DurationS   *int
	ArtistPlays int64
	NeverPlayed bool
	FromOthers  bool
}

// Repository persiste l'historique et calcule les candidats (implémenté par
// pgRepository).
type Repository interface {
	// RecordPlay ajoute un événement d'écoute (user a écouté track).
	RecordPlay(ctx context.Context, userID, trackID string) error
	// Recommend rend au plus limit pistes candidates du demandeur, déjà classées.
	Recommend(ctx context.Context, userID string, limit int) ([]ScoredTrack, error)
}

// Service porte la logique métier du domaine recommendation.
type Service struct {
	repo Repository
}

// NewService construit le service de recommandation.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// RecordPlay enregistre une écoute. L'appelant (track) l'invoque best-effort :
// une erreur est remontée mais ne doit pas interrompre la lecture.
func (s *Service) RecordPlay(ctx context.Context, userID, trackID string) error {
	return s.repo.RecordPlay(ctx, userID, trackID)
}

// Recommend rend les pistes recommandées au demandeur, chacune avec sa raison.
func (s *Service) Recommend(ctx context.Context, userID string) ([]RecommendedTrack, error) {
	scored, err := s.repo.Recommend(ctx, userID, defaultLimit)
	if err != nil {
		return nil, err
	}
	out := make([]RecommendedTrack, 0, len(scored))
	for _, t := range scored {
		out = append(out, RecommendedTrack{
			ID:        t.ID,
			Title:     t.Title,
			Artist:    t.Artist,
			DurationS: t.DurationS,
			Reason:    reasonFor(t),
		})
	}
	return out, nil
}

// reasonFor traduit les signaux bruts d'une piste en une justification lisible.
// Ordre de priorité aligné sur le classement SQL : l'affinité d'artiste prime,
// sinon on distingue une découverte publique, une nouveauté de sa bibliothèque et
// une redécouverte.
func reasonFor(t ScoredTrack) string {
	if t.ArtistPlays > 0 && t.Artist != nil && *t.Artist != "" {
		return "Parce que vous écoutez souvent " + *t.Artist
	}
	if t.NeverPlayed {
		if t.FromOthers {
			return "Découverte publique"
		}
		return "Nouveauté de votre bibliothèque"
	}
	return "À réécouter"
}
