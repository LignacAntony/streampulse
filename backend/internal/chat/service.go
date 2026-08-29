package chat

import (
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/LignacAntony/streampulse/internal/shared/apperror"
)

const (
	MinContentLen   = 1
	MaxContentLen   = 500
	DefaultHistoryN = 50
)

// Message est le type domaine d'un message de chat.
type Message struct {
	ID        string
	StreamID  string
	UserID    string
	Username  string
	Content   string
	CreatedAt time.Time
	DeletedAt *time.Time
}

// BannedUser est le type domaine d'un utilisateur banni (vue liste).
type BannedUser struct {
	UserID    string
	Username  string
	Reason    *string
	CreatedAt time.Time
}

// UserMessage est un message de chat avec le titre du flux (vue admin).
type UserMessage struct {
	ID          string
	StreamID    string
	UserID      string
	Username    string
	Content     string
	CreatedAt   time.Time
	StreamTitle string
}

// Repository est l'interface de persistance du chat.
type Repository interface {
	InsertMessage(ctx context.Context, streamID, userID, content string) (Message, error)
	SoftDeleteMessage(ctx context.Context, messageID, broadcasterID string) error
	InsertBan(ctx context.Context, bannedUserID, bannedBy string, reason *string) error
	DeleteBan(ctx context.Context, bannedUserID, bannedBy string) error
	IsBanned(ctx context.Context, userID, broadcasterID string) (bool, error)
	ListBans(ctx context.Context, bannedBy string) ([]BannedUser, error)
	ListRecentMessages(ctx context.Context, streamID string, limit int32) ([]Message, error)
	GetUsername(ctx context.Context, userID string) (string, error)
	IsGloballyBanned(ctx context.Context, userID string) (bool, error)
	InsertGlobalBan(ctx context.Context, bannedUserID, bannedBy string, reason *string) error
	DeleteGlobalBan(ctx context.Context, bannedUserID string) error
	ListGlobalBans(ctx context.Context) ([]BannedUser, error)
	ListUserMessages(ctx context.Context, userID string, limit, offset int32) ([]UserMessage, error)
}

// StreamOwnerResolver résout le diffuseur propriétaire d'un flux.
type StreamOwnerResolver interface {
	BroadcasterID(ctx context.Context, streamID string) (string, error)
}

// Service porte la logique métier du chat.
type Service struct {
	repo    Repository
	streams StreamOwnerResolver
}

// NewService construit le service chat.
func NewService(repo Repository, streams StreamOwnerResolver) *Service {
	return &Service{repo: repo, streams: streams}
}

// SendMessage valide le contenu, vérifie le ban et persiste le message.
func (s *Service) SendMessage(ctx context.Context, streamID, userID, content string) (Message, error) {
	content = strings.TrimSpace(content)
	n := utf8.RuneCountInString(content)
	if n < MinContentLen || n > MaxContentLen {
		return Message{}, apperror.InvalidArgument("message must be between 1 and 500 characters")
	}

	banned, err := s.IsBanned(ctx, userID, streamID)
	if err != nil {
		return Message{}, err
	}
	if banned {
		return Message{}, apperror.Forbidden("you are banned from this chat")
	}

	return s.repo.InsertMessage(ctx, streamID, userID, content)
}

// DeleteMessage supprime un message (soft delete). Seul le diffuseur du flux
// auquel appartient le message peut le supprimer.
func (s *Service) DeleteMessage(ctx context.Context, messageID, requesterID string) error {
	return s.repo.SoftDeleteMessage(ctx, messageID, requesterID)
}

// BanUser bannit un utilisateur des chats du diffuseur (idempotent).
func (s *Service) BanUser(ctx context.Context, streamID, targetUserID, requesterID string, reason *string) error {
	if targetUserID == requesterID {
		return apperror.InvalidArgument("cannot ban yourself")
	}
	broadcasterID, err := s.streams.BroadcasterID(ctx, streamID)
	if err != nil {
		return err
	}
	if broadcasterID != requesterID {
		return apperror.Forbidden("only the broadcaster can ban users")
	}
	return s.repo.InsertBan(ctx, targetUserID, requesterID, reason)
}

// UnbanUser retire le bannissement d'un utilisateur. Seul le diffuseur qui
// a posé le ban peut le retirer.
func (s *Service) UnbanUser(ctx context.Context, targetUserID, requesterID string) error {
	return s.repo.DeleteBan(ctx, targetUserID, requesterID)
}

// ListBans retourne les utilisateurs bannis par le diffuseur.
func (s *Service) ListBans(ctx context.Context, broadcasterID string) ([]BannedUser, error) {
	return s.repo.ListBans(ctx, broadcasterID)
}

// IsBanned vérifie si un utilisateur est banni par le diffuseur du flux ou
// banni globalement par un admin.
func (s *Service) IsBanned(ctx context.Context, userID, streamID string) (bool, error) {
	global, err := s.repo.IsGloballyBanned(ctx, userID)
	if err != nil {
		return false, err
	}
	if global {
		return true, nil
	}
	broadcasterID, err := s.streams.BroadcasterID(ctx, streamID)
	if err != nil {
		return false, err
	}
	return s.repo.IsBanned(ctx, userID, broadcasterID)
}

// GetUsername résout le username d'un utilisateur.
func (s *Service) GetUsername(ctx context.Context, userID string) (string, error) {
	return s.repo.GetUsername(ctx, userID)
}

// RecentMessages retourne les derniers messages d'un flux (du plus ancien au
// plus récent), pour l'envoi initial à la connexion d'un client.
func (s *Service) RecentMessages(ctx context.Context, streamID string) ([]Message, error) {
	msgs, err := s.repo.ListRecentMessages(ctx, streamID, DefaultHistoryN)
	if err != nil {
		return nil, err
	}
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	return msgs, nil
}

// GlobalBan bannit un utilisateur de tous les chats (admin uniquement).
func (s *Service) GlobalBan(ctx context.Context, targetUserID, adminID string, reason *string) error {
	return s.repo.InsertGlobalBan(ctx, targetUserID, adminID, reason)
}

// GlobalUnban retire le bannissement global d'un utilisateur (admin uniquement).
func (s *Service) GlobalUnban(ctx context.Context, targetUserID string) error {
	return s.repo.DeleteGlobalBan(ctx, targetUserID)
}

// ListGlobalBans retourne les utilisateurs bannis globalement.
func (s *Service) ListGlobalBans(ctx context.Context) ([]BannedUser, error) {
	return s.repo.ListGlobalBans(ctx)
}

// ListUserMessages retourne les messages de chat d'un utilisateur (admin).
func (s *Service) ListUserMessages(ctx context.Context, userID string, limit, offset int32) ([]UserMessage, error) {
	return s.repo.ListUserMessages(ctx, userID, limit, offset)
}

// IsGloballyBanned vérifie le ban global (exposé pour le handler admin).
func (s *Service) IsGloballyBanned(ctx context.Context, userID string) (bool, error) {
	return s.repo.IsGloballyBanned(ctx, userID)
}
