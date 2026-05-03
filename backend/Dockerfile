# =============================================================
# Stage 1 — Builder
# Compile le binaire Go en statique (sans CGO) pour produire
# un binaire autonome transférable dans une image minimale.
# =============================================================
FROM golang:1.25-alpine AS builder

WORKDIR /build

# Copier les fichiers de dépendances en premier pour exploiter
# le cache Docker (layer invalidé uniquement si go.mod change)
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o /app/api \
    ./cmd/api

# =============================================================
# Stage 2 — Runner
# Image finale minimale : uniquement le binaire + CA + timezone
# Cible < 30 MB. Utilisateur non-root pour la sécurité.
# =============================================================
FROM alpine:3 AS runner

RUN apk add --no-cache ca-certificates tzdata

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/api       /app/api
# Les migrations sont lues depuis /app/migrations au démarrage (file://migrations)
COPY --from=builder /build/migrations /app/migrations

USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/api"]
