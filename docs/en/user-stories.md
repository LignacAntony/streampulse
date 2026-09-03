# User stories — StreamPulse

> 🇫🇷 **Version française : [docs/user-stories.md](../user-stories.md)** — the
> French version is the reference.

> Version 1.2.0 — last revised: 2026-08-19

Export of the project's user stories, until now visible only in Linear. An external system is
neither versioned, nor archivable, nor readable by an examining board: this document makes them
readable from the repository.

Each story keeps **its original statement and acceptance criteria**, exactly as they were written
before implementation — not a reconstruction after the fact. The traceability column links each
one to the PR that delivered it.

The corresponding verification scenarios live in the test book (`docs/cahier-de-recette.md`),
delivered by a separate PR still open at the time of writing.

---

## Convention

| Item | Meaning |
|---|---|
| **Identifier** | `US-<epic>-<rank>`. The Linear ticket (`STR-NNN`) is the technical identifier |
| **Estimate** | In points, as set at scoping. Not reassessed since |
| **Status** | Actual state in Linear as of 2026-08-19 |

⚠️ **Six founding epics have no US number.** They were created before the `US-XX-YY` convention
was adopted, and carry a free-form title. Later stories' dependencies nonetheless refer to them by
number (`US-01-02`, `US-02-02`, `US-03-02`…). The mapping given further down is a **proposal for
the team to confirm**: it is inferred from what the dependencies mean, not from a written
decision.

The dependency table below reproduces exactly what Linear contains, including these references to
unassigned numbers.

---

## 1. Infrastructure & Setup

### STR-5 — Git repository setup · ✅ Done

As a developer, I want a well-structured Git repository with develop/main branches, so that
collaborative work is organised and the production branch is protected.

### STR-11 — Setting up Docker Compose · ✅ Done

As a developer, I want a working Docker Compose environment, so that I can start every service
(API, database, observability) with a single command.

- **Given**: Docker and Docker Compose installed
- **When**: I run `docker-compose up`
- **Then**: the go-api, postgres, prometheus, grafana, loki and tempo services start without
  error and are connected on an internal network.

### STR-17 — GitHub Actions CI/CD pipeline · ✅ Done

As a tech lead, I want an automated CI/CD pipeline, so that every push to main automatically
triggers build, tests and deployment with no manual step.

- **Given**: a commit pushed to main
- **When**: the pipeline triggers
- **Then**: the Go build succeeds, unit tests pass, the Docker image is built and the deployment
  to the VPS runs — all in under 5 minutes.

### STR-23 — 12-Factor App configuration · ✅ Done

As a developer, I want all configuration externalised through environment variables, so that the
project follows the 12-Factor App methodology and avoids any hard-coding.

- **Given**: a documented `.env.example` file
- **When**: I launch the application with injected environment variables
- **Then**: the application starts correctly — no configuration value (JWT secret, database URL,
  ports) is hard-coded in the source.

### STR-28 — PostgreSQL database initialisation · ✅ Done

As a backend developer, I want a versioned PostgreSQL schema, so that migrations are reproducible
and the database stays consistent across environments.

- **Given**: an empty PostgreSQL container
- **When**: I run the migrations
- **Then**: every table (users, streams, tracks, playlists, queue_items) is created with the
  appropriate integrity constraints and indexes.

> ⚠️ The shipped schema has **12 tables**, not five: the statement dates from the initial
> scoping. See [`database.md`](database.md).

### US-01-06 (STR-92) — Flutter mobile project setup · ✅ Done · 4 pts

As a Flutter developer, I want a mobile project structured with Clean Architecture and every
dependency configured, so that the team can start building features without any prior setup.

- **Given**: the developer clones the repo and moves into `mobile/`
- **When**: they run `flutter pub get` then `flutter analyze`
- **Then**: the project compiles and the analysis reports no issue.

---

## 2. Authentication & Role Management

### STR-33 — New user registration · ✅ Done

As a visitor, I want to create an account with my email and a password, so that I can access the
platform's personalised features.

- **Given**: a visitor on the registration screen
- **When**: they submit a valid email, a unique username and a password of at least 8 characters
- **Then**: the account is created, the password is hashed with bcrypt (cost ≥ 12), a
  confirmation is shown and the user can log in immediately.

### STR-38 — Secure login with JWT · ✅ Done

As a registered user, I want to log in with my email and password, so that I obtain a JWT token
to access protected resources.

- **Given**: a registered user
- **When**: they enter the correct credentials
- **Then**: the API returns a JWT access token (15 min expiry) and a refresh token (7-day
  expiry) — the token carries the user's role in its claims.

### STR-44 — User profile management · ✅ Done

As a logged-in user, I want to view and edit my personal information, so that I can keep my
profile up to date.

- **Given**: a logged-in user on their profile
- **When**: they change their username or avatar and confirm
- **Then**: the changes are saved, the UI is updated and a confirmation is shown.

### STR-49 — Requesting and activating the Broadcaster role · ✅ Done

As a standard user, I want to request the Broadcaster role from my profile, so that I can create
and manage live streams.

- **Given**: a user with the standard User role
- **When**: they submit a Broadcaster role request
- **Then**: their request is pending, an admin can approve it from the dashboard — once
  approved, the user gets the Broadcaster role and can create streams.

### STR-54 — Password reset · ✅ Done

As a user who forgot their password, I want to receive a reset link by email, so that I can
recover access to my account.

- **Given**: a valid email submitted on the "forgot password" screen
- **When**: the user clicks the link they received (valid for 1 hour)
- **Then**: they can set a new password — the old token is invalidated after use.

### STR-59 — Account deletion (GDPR compliance) · ✅ Done

As a logged-in user, I want to be able to permanently delete my account and all my data, so that
I can exercise my right to erasure (GDPR Art. 17).

- **Given**: an authenticated user confirming the deletion
- **When**: they confirm the deletion (double confirmation)
- **Then**: all their personal data (email, username, history, playlists, audio files) is
  removed from the database and from storage.

---

## 3. Live Streaming Engine (Go Backend)

### STR-64 — Creating and configuring a live stream · ✅ Done

As a broadcaster, I want to create a new live stream with a title, a description and a
visibility, so that I can prepare it before starting the broadcast.

- **Given**: an authenticated broadcaster
- **When**: they create a stream (title, description, public/private)
- **Then**: the stream is persisted in the database with the status "inactive", a unique
  identifier is generated and the broadcaster gets the stream's source URL.

### STR-70 — HLS engine: segmentation and manifest generation · ✅ Done

As the backend, I want to segment the incoming audio stream into ~10-second `.ts` files and
generate a continuously updated `.m3u8` manifest, so that HLS playback by clients is possible.

- **Given**: a broadcaster sends an AAC audio stream over HTTP multipart
- **When**: the backend receives the stream
- **Then**: `.ts` segments are generated every 10 seconds, the `.m3u8` manifest is updated with
  the new segments, and a listener can fetch the manifest and start playback.

### STR-77 — Starting and stopping the stream (broadcaster) · ✅ Done

As a **broadcaster**, I want to **start** then **stop** my live stream, so that I can move a
prepared stream (`idle`) into broadcast (`live`), then end it cleanly (`ended`) while warning
listeners.

- **Given**: an authenticated broadcaster, owner of an `idle` stream, with no other stream
  already live
- **When**: they start the stream (`PATCH /api/streams/{id}/start`)
- **Then**: the status becomes `live`, `started_at` is set, a broadcast session is recorded in
  memory (a cancellable goroutine), and the stream becomes visible in the list of live streams.

- **Given**: a broadcaster who owns a `live` stream
- **When**: they stop the stream (`PATCH /api/streams/{id}/stop`)
- **Then**: the status becomes `ended`, `ended_at` is set, the session goroutine is released (no
  leak), and subscribed listeners receive an `ended` event in real time (SSE).

Additional criteria:

- **Only one `live` stream at a time per broadcaster**: a `start` is refused (409) if the
  broadcaster already has a stream live, or if the stream is not `idle`.
- **Owner-only**: only the owner (`broadcaster` role) can `start`/`stop` (404 otherwise); `stop`
  on a non-`live` stream → 409; `ended` is terminal.
- **Real-time notification**: `GET /api/streams/{id}/events` exposes an SSE stream.
- **Clean concurrency**: each session is cancelled through a `context.Context` on `stop` and on
  server shutdown; the absence of goroutine leaks is checked by a test.

### STR-87 — Scalability: handling N simultaneous listeners · ✅ Done

As the system, I want to support at least 50 simultaneous listeners on the same stream, so that
the Go streaming engine's scalability is proven.

- **Given**: an active HLS stream
- **When**: 50 HTTP clients simulate fetching the manifest and the segments
- **Then**: p95 latency stays under 300 ms, memory consumption stays under 2 MB per connection
  and no goroutine leak is detected via pprof.

---

## 4. Mobile Listener Experience (Flutter)

### US-04-01 (STR-107) — Discovering and listing active streams · ✅ Done · 2 pts

As a listener (or an anonymous visitor), I want to see the list of live streams, so that I can
easily join a broadcast that interests me.

- **Given**: active public streams exist
- **When**: I open the home screen
- **Then**: the list of active streams is shown with title, listener count and broadcast
  duration — it refreshes automatically every 10 seconds.

*Dependencies: US-03-01, US-02-02*

### US-04-02 (STR-108) — HLS audio player (play/pause/volume) · ✅ Done · 4 pts

As a listener, I want to listen to a live HLS stream with playback controls, so that I can enjoy
a smooth audio experience.

- **Given**: a joined active stream
- **When**: the player opens
- **Then**: playback starts automatically in under 3 seconds, the play/pause controls and the
  volume setting work, the stream's title is shown and the rebuffering rate is under 2%.

*Dependencies: US-03-02, US-04-01*

> ⚠️ The **in-app volume control was not delivered**: volume is delegated to the hardware
> buttons. This criterion from the brief remains open, tracked in STR-244.

### US-04-03 (STR-109) — Background audio playback · ✅ Done · 3 pts

As a listener, I want playback to continue when I leave the application, so that I can use my
phone freely while listening.

- **Given**: a stream currently being listened to
- **When**: the user presses the Home button
- **Then**: playback continues without interruption and the controls appear in the notification
  bar and on the lock screen (iOS and Android).

*Dependencies: US-04-02*

### US-04-04 (STR-110) — Handling interruptions · ✅ Done · 2 pts

As a listener, I want playback to pause during an incoming call and resume automatically
afterwards, so that I do not miss any content.

- **Given**: a stream playing in the background
- **When**: an incoming phone call is received
- **Then**: playback pauses automatically — and once the call ends, playback resumes from the
  live stream's current point.

*Dependencies: US-04-03*

### US-04-05 (STR-111) — Adding a stream to favourites · ✅ Done · 1 pt

As a logged-in user, I want to add a stream to my favourites, so that I can easily find it again
the next time it broadcasts.

- **Given**: a logged-in user on a stream's page
- **When**: they tap the favourites icon
- **Then**: the stream is added to their favourites list, the icon changes state — and the
  stream appears in their Favourites tab.

*Dependencies: US-04-01, US-02-02*

---

## 5. On-Demand Audio Library

### US-05-01 (STR-130) — Uploading an audio track · ✅ Done · 3 pts

As a broadcaster or a user, I want to upload an audio file (MP3/AAC/OGG), so that I can add it to
my personal library.

- **Given**: a logged-in user
- **When**: they select an audio file of at most 50 MB in MP3/AAC/OGG format
- **Then**: the file is uploaded, its MIME type is validated server-side, it is stored outside
  the web-served directory and referenced in the database with its metadata (title, duration,
  size).

*Dependencies: US-02-02, US-01-05*

### US-05-02 (STR-131) — Creating and managing playlists · ✅ Done · 2 pts

As a logged-in user, I want to create, rename and delete my playlists, so that I can organise my
personal music library.

- **Given**: a logged-in user
- **When**: they create a playlist with a name
- **Then**: the playlist is created empty and appears in their list — they can rename or delete
  it at any time, with confirmation before deletion.

*Dependencies: US-02-02, US-01-05*

### US-05-03 (STR-132) — Adding and reordering tracks · ✅ Done · 3 pts

As a user, I want to add, remove and reorder a playlist's tracks, so that I can build a
personalised listening queue.

- **Given**: an existing playlist
- **When**: the user adds a track or changes its order by drag-and-drop
- **Then**: the change is persisted, the playlist shows the new order and the queue is updated.

*Dependencies: US-05-01, US-05-02*

### US-05-04 (STR-133) — Playing a playlist with a queue · ✅ Done · 3 pts

As a user, I want to play my playlist with automatic advance to the next track, so that I can
enjoy continuous listening with no intervention.

- **Given**: a playlist with 3 or more tracks
- **When**: the user starts playback
- **Then**: tracks play one after another automatically, the queue is visible, the user can jump
  to any track — playback continues in the background.

*Dependencies: US-05-03, US-04-03*

### US-05-05 (STR-134) — Shuffle and Repeat modes · ✅ Done · 1 pt

As a user, I want to turn on shuffle playback or repetition (repeat track / repeat playlist), so
that I can vary my listening experience.

- **Given**: a playlist currently playing
- **When**: the user turns on shuffle
- **Then**: the playback order becomes random — and with repeat-one, the current track repeats
  indefinitely.

*Dependencies: US-05-04*

---

## 6. Broadcaster Dashboard

### US-06-01 (STR-153) — Starting and stopping a stream from the dashboard · ✅ Done · 4 pts

As a broadcaster, I want to start and stop my stream from a simplified interface, so that I can
control my broadcast without technical complexity.

- **Given**: a broadcaster on their dashboard
- **When**: they tap **"Démarrer la diffusion"** (Start broadcasting)
- **Then**: the application starts sending the audio stream to the backend, the stream's status
  becomes **"En direct"** (Live) and the listener count is shown in real time.

*Dependencies: US-03-03, US-02-04*

### US-06-02 (STR-154) — Real-time broadcast statistics · ✅ Done · 2 pts

As a broadcaster, I want to see my stream's statistics in real time (connected listeners,
duration, disconnections), so that I can gauge my broadcast's audience.

- **Given**: an active stream
- **When**: I open my broadcaster dashboard
- **Then**: the number of connected listeners is shown and updated every 5 seconds, along with
  the total broadcast duration.

*Dependencies: US-06-01, US-03-02*

> ⚠️ The listener count is an **estimate**: HLS has no persistent connection. See
> [ADR 025](../adr/025-statistiques-daudience-en-temps-reel.md).

---

## 7. Observability & Supervision

### US-07-01 (STR-163) — Structured JSON logs · ✅ Done · 2 pts

As an SRE, I want every Go backend log to be emitted in structured JSON format, so that it can be
indexed automatically in Loki and analysed by third-party tools.

- **Given**: the Go application running
- **When**: an HTTP request is processed or an error occurs
- **Then**: a JSON log is emitted with the fields timestamp, level, message, trace_id, service,
  environment — no `fmt.Println()` exists in production.

*Dependencies: US-01-02*

### US-07-02 (STR-164) — OpenTelemetry instrumentation · ✅ Done · 4 pts

As a developer, I want to instrument the Go backend with OpenTelemetry, so that I can trace a
request's path from the mobile app all the way to the database.

- **Given**: the Go OTEL SDK configured
- **When**: a request reaches the API
- **Then**: a span is created for each HTTP handler, SQL query spans are recorded, the trace_id
  is propagated in the headers — and the full trace (mobile → API → DB) is visible in
  Tempo/Grafana.

*Dependencies: US-07-01, US-01-02*

> ⚠️ **Partially met criterion.** The trace starts at the server: no `traceparent` is emitted by
> the Flutter client. The `API → DB` leg is delivered, the `mobile →` leg is not. See
> [ADR 020](../adr/020-traces-opentelemetry-otlp-tempo.md) and STR-244.

### US-07-03 (STR-165) — Prometheus metrics + API & Infra panels · ✅ Done · 3 pts

As an SRE, I want to expose HTTP and infrastructure metrics through Prometheus, so that I can
visualise them in the Grafana API Backend and Infrastructure panels.

- **Given**: the Go application started
- **When**: Prometheus scrapes `/metrics` every 15 seconds
- **Then**: the `http_requests_total`, `http_request_duration_seconds` (p50/p95/p99),
  `go_goroutines` and `go_memstats_heap_alloc_bytes` metrics are collected and visible in
  Grafana.

*Dependencies: US-07-01, US-01-02*

### US-07-04 (STR-166) — Grafana Live Streaming panel dashboard · ✅ Done · 3 pts

As an SRE, I want a dashboard dedicated to live streaming, so that I can see in real time the
number of active streams, connected listeners, HLS latency and the rebuffering rate.

- **Given**: at least one active stream and connected listeners
- **When**: I view Panel 1 in Grafana
- **Then**: the gauges show the number of active streams, listeners connected per stream, p95
  HLS latency and the error rate on `.ts` segments — with real data, not fixtures.

*Dependencies: US-07-03, US-03-02*

### US-07-05 (STR-167) — Logs & Errors panel + Alerts · ✅ Done · 3 pts

As an SRE, I want to view logs in real time in Grafana and configure alerts on critical
thresholds, so that I am notified proactively of incidents.

- **Given**: JSON logs indexed in Loki and traces in Tempo
- **When**: I view Panel 4
- **Then**: logs filterable by level (info/warn/error) and by trace_id are visible — and an
  alert fires if the HTTP 5xx error rate exceeds 5% over 5 minutes.

*Dependencies: US-07-01, US-07-02, US-07-03*

---

## 8. Administrator Dashboard

### US-08-01 (STR-191) — Listing, searching and managing users · ✅ Done · 3 pts

As an administrator, I want to view and manage the complete list of users, so that I can oversee
the community.

- **Given**: an administrator logged in at `/admin`
- **When**: they search for a user by name or filter by role
- **Then**: the filtered list is shown — they can activate, deactivate or delete an account with
  confirmation.

*Dependencies: US-02-02, US-02-04*

### US-08-02 (STR-192) — Supervising and interrupting active streams · ✅ Done · 2 pts

As an administrator, I want to see every active stream and be able to interrupt one if needed, so
that I can moderate the platform.

- **Given**: an administrator on the dashboard
- **When**: they select an active stream and click **"Interrompre"** (Interrupt)
- **Then**: the stream is stopped immediately, listeners receive an end-of-broadcast
  notification and an audit log entry is recorded.

*Dependencies: US-03-03, US-08-01*

---

## 9. Bonus features

The brief scores these features out of 5 points, on top of the 15 for the core scope.

### US-09-01 (STR-200) — Live chat between listeners (WebSocket) · ⬜ Backlog · 5 pts

As a listener on a stream, I want to send and receive messages in real time, so that I can
interact with the community during the broadcast.

- **Given**: several listeners connected to the same stream
- **When**: one of them sends a text message
- **Then**: every listener receives the message in under 500 ms over WebSocket — the broadcaster
  can delete a message or ban a user from the chat.

*Dependencies: US-03-02, US-02-02*

### US-09-02 (STR-201) — Offline mode (playlist caching) · 🔵 In Review · 5 pts

As a user, I want to make a playlist available offline, so that I can listen to my tracks without
internet access.

- **Given**: a playlist with tracks
- **When**: the user turns on offline mode for that playlist
- **Then**: the audio files are downloaded and cached locally — the playlist is accessible and
  playable without a network, with a visual indication of the offline state.

*Dependencies: US-05-04*

### US-09-03 (STR-202) — Kubernetes deployment · ⬜ Backlog · 5 pts

As a DevOps engineer, I want to deploy StreamPulse on a Kubernetes cluster with resource
management, so that I can demonstrate production-grade cloud-native infrastructure.

- **Given**: an available K8s cluster (Minikube or cloud)
- **When**: I apply the kubectl manifests
- **Then**: the Go API, PostgreSQL and the OTEL stack are deployed with configured resource
  limits/requests, a HorizontalPodAutoscaler is active and the application responds on its
  endpoint.

*Dependencies: US-01-03*

### US-09-04 (STR-203) — Simple recommendation algorithm · ⬜ Backlog · 4 pts

As a user, I want to see recommended streams and playlists on my home page, so that I can
discover content matching my taste.

- **Given**: a user with a listening history
- **When**: they open the home page
- **Then**: a **"Recommandé pour vous"** (Recommended for you) section shows 5 streams or
  playlists based on their most-listened categories (simplified collaborative filtering or
  content-based).

*Dependencies: US-04-02, US-05-04*

### US-09-05 (STR-204) — On-the-fly transcoding (FFmpeg) · ✅ Done · 4 pts

As the system, I want to transcode non-AAC audio formats on the fly with FFmpeg, so that I can
accept any incoming format (MP3, OGG, WAV) for HLS broadcasting.

- **Given**: a broadcaster sending an MP3 stream
- **When**: the backend receives the stream
- **Then**: FFmpeg transcodes the stream to AAC on the fly, the result is segmented into HLS and
  listeners receive a clean AAC stream — the added latency from transcoding is under 2 seconds.

*Dependencies: US-03-02*

> ⚠️ This transcoding covers **ingest** (normalising the incoming format), not adapting the
> bitrate to the listener's bandwidth. The brief, for its part, asks for the second. See
> [ADR 030](../adr/030-transcodage-a-la-volee-des-formats-dingest.md).

---

## Mapping the unnumbered epics

⚠️ **Proposal, to be confirmed by the team.** These mappings are inferred from what the
dependencies declared in Linear mean; no written decision fixes them.

| Number cited as a dependency | Likely epic | Ticket |
|---|---|---|
| US-01-02 | Setting up Docker Compose | STR-11 |
| US-01-03 | GitHub Actions CI/CD pipeline | STR-17 |
| US-01-05 | PostgreSQL database initialisation | STR-28 |
| US-01-06 | Flutter project setup | STR-92 ✅ *(confirmed by the title)* |
| US-02-02 | Secure login with JWT | STR-38 |
| US-02-04 | Requesting and activating the Broadcaster role | STR-49 |
| US-03-01 | Creating and configuring a live stream | STR-64 |
| US-03-02 | HLS engine: segmentation and manifest | STR-70 |
| US-03-03 | Starting and stopping the stream | STR-77 |

Numbers `US-01-01` and `US-01-04` are not cited by any dependency; they most likely correspond to
STR-5 (Git repository) and STR-23 (12-Factor), with no way to tell which is which.

---

## What this document does not cover

- Each story's **sub-tasks** (about a hundred `STR-NNN` tickets with no user-facing statement):
  they describe implementation steps, not user expectations.
- The **fix tickets** opened after the compliance audit (STR-232 to STR-245): they live in a
  separate Linear project and are not user stories.
