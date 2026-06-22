package broadcaster

import (
	"context"
	"log"
	"net/http"

	"github.com/LignacAntony/streampulse/internal/auth"
	"github.com/LignacAntony/streampulse/internal/shared/apperror"
	"github.com/LignacAntony/streampulse/internal/shared/httpjson"
)

const maxRequestBodyBytes = 1 << 20 // 1 MiB

type Requester interface {
	RequestBroadcaster(ctx context.Context, userID, message string) (Request, error)
}

type MyRequestReader interface {
	GetMyRequest(ctx context.Context, userID string) (Request, error)
}

type RequestLister interface {
	ListRequests(ctx context.Context, status string) ([]AdminRequest, error)
}

type RequestReviewer interface {
	ApproveRequest(ctx context.Context, requestID, adminID, note string) (Request, error)
	RejectRequest(ctx context.Context, requestID, adminID, note string) (Request, error)
}

type requestBody struct {
	Message string `json:"message"`
}

type reviewBody struct {
	ReviewNote string `json:"review_note"`
}

type Handler struct {
	requester Requester
	reader    MyRequestReader
	lister    RequestLister
	reviewer  RequestReviewer
}

func NewHandler(requester Requester, reader MyRequestReader, lister RequestLister, reviewer RequestReviewer) *Handler {
	return &Handler{requester: requester, reader: reader, lister: lister, reviewer: reviewer}
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	var body requestBody
	if err := httpjson.Decode(w, r, &body, maxRequestBodyBytes); err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	req, err := h.requester.RequestBroadcaster(r.Context(), userID, body.Message)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusCreated, req); err != nil {
		log.Printf("broadcaster: encode create-request response: %v", err)
	}
}

func (h *Handler) GetMine(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	req, err := h.reader.GetMyRequest(r.Context(), userID)
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, req); err != nil {
		log.Printf("broadcaster: encode get-my-request response: %v", err)
	}
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	requests, err := h.lister.ListRequests(r.Context(), r.URL.Query().Get("status"))
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, map[string]any{"requests": requests}); err != nil {
		log.Printf("broadcaster: encode list-requests response: %v", err)
	}
}

func (h *Handler) Approve(w http.ResponseWriter, r *http.Request) {
	h.review(w, r, true)
}

func (h *Handler) Reject(w http.ResponseWriter, r *http.Request) {
	h.review(w, r, false)
}

func (h *Handler) review(w http.ResponseWriter, r *http.Request, approve bool) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		httpjson.WriteError(w, r, httpjson.StatusError(http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed"))
		return
	}

	adminID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		httpjson.WriteError(w, r, apperror.Unauthorized("unauthenticated"))
		return
	}

	requestID := r.PathValue("id")
	if requestID == "" {
		httpjson.WriteError(w, r, apperror.InvalidArgument("missing request id"))
		return
	}

	// La note de traitement est optionnelle : un corps absent est accepté.
	var body reviewBody
	if r.ContentLength != 0 {
		if err := httpjson.Decode(w, r, &body, maxRequestBodyBytes); err != nil {
			httpjson.WriteError(w, r, err)
			return
		}
	}

	var (
		req Request
		err error
	)
	if approve {
		req, err = h.reviewer.ApproveRequest(r.Context(), requestID, adminID, body.ReviewNote)
	} else {
		req, err = h.reviewer.RejectRequest(r.Context(), requestID, adminID, body.ReviewNote)
	}
	if err != nil {
		httpjson.WriteError(w, r, err)
		return
	}

	if err := httpjson.Write(w, http.StatusOK, req); err != nil {
		log.Printf("broadcaster: encode review-request response: %v", err)
	}
}
