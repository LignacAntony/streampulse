# =============================================================
# Stage 1 — Builder
# Compile le binaire Go en statique (sans CGO) pour produire
# un binaire autonome transférable dans une image minimale.
# =============================================================
FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o /app/api \
    ./cmd/api

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
