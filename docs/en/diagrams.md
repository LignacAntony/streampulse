# Diagrams — StreamPulse

> 🇫🇷 **Version française : [docs/diagrammes.md](../diagrammes.md)** — the
> French version is the reference.

> Version 1.2.0 — last revised: 2026-08-19

Standardised views of the system, in UML notation rendered by Mermaid — GitHub displays them
natively, with no tool and no image to regenerate.

**Each diagram is followed by a textual equivalent.** A diagram remains an image to a screen
reader; the description that comes with it carries the same information in a readable form.

The data schema has its own document: [`database.md`](database.md).

---

## 1. Use cases — the four roles

```mermaid
graph LR
    anonymous(("Anonymous"))
    user(("User"))
    broadcaster(("Broadcaster"))
    admin(("Administrator"))

    anonymous --> UC1["Discover live streams"]
    anonymous --> UC2["Listen to a public stream"]
    anonymous --> UC3["Register / log in"]

    user --> UC1
    user --> UC2
    user --> UC4["Add a stream to favourites"]
    user --> UC5["Upload a track"]
    user --> UC6["Manage playlists"]
    user --> UC7["Listen to a playlist"]
    user --> UC8["Manage profile"]
    user --> UC9["Request the broadcaster role"]
    user --> UC10["Delete account"]

    broadcaster --> UC11["Create a stream"]
    broadcaster --> UC12["Start / stop a live stream"]
    broadcaster --> UC13["Broadcast from the microphone"]
    broadcaster --> UC14["View audience"]
    broadcaster --> UC15["Rotate stream key"]

    admin --> UC16["Manage accounts"]
    admin --> UC17["Supervise active streams"]
    admin --> UC18["Interrupt a stream"]
    admin --> UC19["Process role requests"]

    user -.inherits from.-> anonymous
    broadcaster -.inherits from.-> user
    admin -.inherits from.-> broadcaster
```

**Textual equivalent** — Four hierarchical roles: each inherits the capabilities of the one
before it, in the order anonymous → user → broadcaster → administrator. The anonymous visitor
discovers and listens to public streams, and can register. The user adds favourites, the
library, playlists, their profile, the role request and account deletion. The broadcaster adds
creating streams, starting and stopping a live stream, broadcasting from the microphone, viewing
their audience and rotating their key. The administrator adds account management, supervising and
interrupting streams, and processing role requests.

The hierarchy is enforced by `auth.RequireRole`: a higher rank always satisfies the requirement
of a lower one.

---

## 2. Sequence — authentication and token rotation

```mermaid
sequenceDiagram
    autonumber
    participant M as Mobile application
    participant A as Go API
    participant DB as PostgreSQL

    M->>A: POST /api/auth/login (email, password)
    A->>DB: SELECT user WHERE email
    DB-->>A: user + password_hash
    A->>A: bcrypt.CompareHashAndPassword
    A->>A: sign an HS256 access token (15 min, claims sub + role)
    A->>DB: INSERT refresh_tokens (SHA-256 of the token, 7 days)
    A-->>M: access token + refresh token
    M->>M: store in the OS's secure vault

    Note over M,A: 15 minutes later

    M->>A: GET /api/playlists (Bearer access token)
    A-->>M: 401 — expired token
    M->>A: POST /api/auth/refresh (refresh token)
    A->>DB: SELECT by hash, check expiry
    A->>DB: DELETE the old one, INSERT the new one
    Note right of A: rotation: a consumed refresh<br/>token cannot be reused
    A-->>M: new token pair
    M->>A: replay GET /api/playlists
    A-->>M: 200
```

**Textual equivalent** — At login, the API checks the password with bcrypt, signs an HS256
access token valid for 15 minutes carrying the user id and role, and stores in the database the
**SHA-256 hash** of a refresh token valid for 7 days. The mobile app keeps both in the platform's
secure store. When the access token expires, the API answers 401; the client then exchanges its
refresh token for a new pair. The old refresh token is deleted in the process: a consumed token
cannot be reused. The client finally replays its original request.

On the mobile side, this cycle is serialised: N requests that come back with 401 at the same time
trigger only a single refresh.

---

## 3. Sequence — from ingest to the listener's ear

```mermaid
sequenceDiagram
    autonumber
    participant D as Broadcaster (mobile)
    participant A as Go API
    participant F as ffmpeg
    participant FS as Session directory
    participant L as Listener (mobile)

    D->>A: PATCH /api/streams/{id}/start (Bearer JWT)
    A->>A: status idle → live, create the session (cancellable context)
    A-->>D: 200 + stream_source_url

    D->>A: POST /api/streams/ingest/{stream_key}
    Note right of A: authenticated by the key alone,<br/>without a JWT
    A->>F: write the audio to stdin
    F->>FS: .ts segments (~10 s) + sliding .m3u8 manifest

    par The broadcaster keeps pushing
        loop continuously
            D->>A: audio bytes
            A->>F: relay to stdin
        end
    and The listener reads independently
        L->>A: GET /api/streams/{id}/playlist.m3u8
        A->>FS: read the manifest
        A-->>L: 200 (or 409 if not ready yet)
        loop every ~10 s
            L->>A: GET /api/streams/{id}/segments/{segment}.ts
            A-->>L: 200 — audio segment
        end
    end

    D->>A: PATCH /api/streams/{id}/stop
    A->>F: close stdin, then kill the process
    A->>FS: delete the directory
    A->>A: status live → ended, cancel the context
    A-->>L: SSE "ended" event
```

**Textual equivalent** — The broadcaster starts their stream with their JWT: the status moves
from `idle` to `live` and a cancellable session is created in memory. They then push the audio to
the ingest route, authenticated by the stream key alone — without a JWT, since third-party
broadcasting software has no way to present one. The API relays these bytes to the standard input
of an ffmpeg process, which writes segments of about ten seconds and a sliding manifest into the
session's working directory.

In parallel, the listener fetches the manifest, then the segments, in a loop. The fan-out from
one broadcaster to N listeners therefore happens **through files**, not through an in-memory
channel: each player reads independently.

On stop, the API closes ffmpeg's input to let it finalise its last segment, kills the process,
deletes the directory, cancels the session's context and notifies subscribed listeners with an
`ended` SSE event.

---

## 4. Components and deployment flow

```mermaid
graph TB
    subgraph clients["Clients"]
        mobile["Flutter application<br/>iOS · Android"]
    end

    subgraph vps["VPS — streampulse-net network"]
        caddy["Caddy<br/>TLS Let's Encrypt<br/>only public port"]

        subgraph app["Application"]
            api["Go API<br/>net/http · 127.0.0.1:8080"]
            pg[("PostgreSQL 16")]
            vol[/"track_storage volume"/]
        end

        subgraph obs["Observability"]
            prom["Prometheus"]
            loki["Loki"]
            tempo["Tempo"]
            alloy["Alloy"]
            grafana["Grafana"]
        end
    end

    mobile -->|HTTPS| caddy
    caddy -->|internal HTTP| api
    api --> pg
    api --> vol
    prom -->|scrapes /metrics| api
    alloy -->|JSON logs| loki
    api -.->|stdout| alloy
    api -->|OTLP| tempo
    grafana --> prom
    grafana --> loki
    grafana --> tempo
```

**Textual equivalent** — The Flutter application reaches the VPS over HTTPS. **Caddy is the only
public entry point**: it terminates TLS with an automatically renewed Let's Encrypt certificate,
and relays over HTTP on the internal network to the Go API, which only listens on the loopback
interface.

The API talks to PostgreSQL and writes audio files to a named volume, outside any served
directory.

Three observability flows leave from there: Prometheus comes to fetch metrics on `/metrics`
through an internal scrape, Alloy collects the API's standard output and ships it to Loki, and
the API pushes its traces to Tempo over OTLP. Grafana reads all three sources and serves both the
dashboards and the alerts.

⚠️ **This view describes the target state.** As of 2026-08-19, Prometheus and Grafana are still
published on every interface of the VPS, and Caddy's block on `/metrics` is not deployed — the
fixes are written but await a manual infrastructure sync. See STR-240.

---

## 5. Stream states

```mermaid
stateDiagram-v2
    [*] --> idle : stream created
    idle --> live : PATCH /start (owner, no other live stream)
    live --> ended : PATCH /stop
    live --> ended : ingest lease expired (no audio for N s)
    live --> ended : segmenter died
    ended --> live : PATCH /start (restart, ended_at reset to NULL)

    idle --> archived : DELETE (soft delete)
    live --> archived : DELETE
    ended --> archived : DELETE
    archived --> [*]
```

**Textual equivalent** — A stream is born `idle` when created. It moves to `live` at its owner's
request, provided none of their other streams is already live — a constraint guaranteed by a
partial unique index in the database, not only by the code.

Three paths lead to `ended`: an explicit stop by the broadcaster, the ingest lease expiring once
no more audio arrives, and the segmenter dying. `ended` is **not terminal**: a stream is a
reusable channel, and `PATCH /start` accepts `idle|ended → live`, resetting `ended_at` to NULL
(ADR 048).

Deletion is soft and orthogonal: it sets `archived_at` from any state, without erasing the row.
