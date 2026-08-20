# Architecture decisions — index

> 🇫🇷 **Version française : [docs/README.md § Index complet des ADR](../README.md)**
> and the full records in [`docs/adr/`](../adr/).

This page summarises **every** architecture decision record in one line of
context, one of decision, and one of consequence. It exists because the full
records are written in French and total roughly 44 000 words — translating them
all was judged a worse use of effort than making all of them *findable* and
*understandable* in English.

**What this page is not.** It is not a substitute for the records. Each record
carries the alternatives that were rejected and why, which is the part that
actually justifies a decision. If a decision matters to you, read the record —
the code snippets, tables and diagrams inside are largely language-neutral.

The bilingual scope, and why it stops here, is stated in
[docs/README.md](../README.md#périmètre-bilingue).

---

## Foundations

**ADR 001 — Observability stack: LGTM.** *Context:* the project needs logs,
metrics and traces without a licence budget. *Decision:* adopt Loki, Grafana,
Tempo and Prometheus. *Consequence:* one vendor, OpenTelemetry-compatible, and
far less memory than an ELK stack since Loki indexes labels only.

**ADR 002 — Docker Compose for development.** *Context:* every developer needs
the same environment. *Decision:* Compose v2 for local orchestration, and a
multi-stage Dockerfile for the production image. *Consequence:* one command
starts everything; the final image stays under 30 MB.

**ADR 003 — GitHub Actions and GHCR.** *Context:* CI/CD had to live where the
code already is. *Decision:* GitHub Actions, with GitHub Container Registry for
images. *Consequence:* no third-party CI to operate, at the cost of coupling the
pipeline to GitHub.

**ADR 004 — 12-Factor configuration through Viper.** *Context:* no value may be
hard-coded. *Decision:* centralise loading in `internal/config`, reading `.env`
in development and the environment in production. *Consequence:* the API
**refuses to start** when a required variable is missing — failure is loud and
immediate rather than latent.

**ADR 037 — Database initialisation.** *Context:* schema, migrations and seed
data needed a single owner. *Decision:* SQL migrations applied at startup, seed
only in development. *Consequence:* an ORM was explicitly rejected; the schema
is written by hand and read by sqlc.

**ADR 007 — Database access with sqlc.** *Context:* raw SQL is precise but
untyped. *Decision:* write SQL, generate typed Go from it. *Consequence:*
queries are checked against the real schema at generation time; the generated
code is never edited.

**ADR 008 — Handler / service / repository layering.** *Context:* the backend
needed a shape that survives growth. *Decision:* three layers per domain, with
narrow interfaces declared by the consumer. *Consequence:* handlers are tested
against stubs, services against in-memory fakes.

## Authentication and accounts

**ADR 006 — JWT authentication.** *Context:* sessions must survive an app
restart without keeping a password. *Decision:* a 15-minute HS256 access token,
plus a refresh token stored **hashed** and rotated on every use. *Consequence:*
a stolen refresh token stops working at the next legitimate renewal; an access
token stays valid until it expires.

**ADR 009 — Authentication on the Flutter side.** *Context:* tokens must not sit
in plain storage. *Decision:* Keychain and EncryptedSharedPreferences, with a
**serialised** refresh — many parallel 401s trigger a single renewal.
*Consequence:* logout purges local storage even when the network call fails.

**ADR 010 — Password reset, backend.** *Context:* a reset link is a credential.
*Decision:* store only the token's hash, single use, short-lived, and answer
identically whether the address exists or not. *Consequence:* the endpoint
cannot be used to discover who has an account.

**ADR 011 — Password reset, Flutter.** *Context:* the link must reopen the app.
*Decision:* a custom-scheme deep link. *Consequence:* the flow works without a
web page, at the cost of platform-specific configuration.

**ADR 038 — User profile.** *Context:* preferences do not belong on the
identity row. *Decision:* a dedicated `profiles` table, one-to-one with `users`,
created by a trigger. *Consequence:* a profile exists from the moment an account
does, so reads never have to handle its absence.

**ADR 014 — Requesting the broadcaster role.** *Context:* not every account may
broadcast. *Decision:* an explicit request, reviewed by an administrator, that
promotes the account within a single transaction. *Consequence:* a review
decision and a role change can never disagree.

## Streaming

**ADR 013 — The streaming domain.** *Context:* streams have a lifecycle, an
owner and secrets. *Decision:* one domain owning creation, visibility, the
`stream_key` and live sessions, with **one live stream per broadcaster**.
*Consequence:* the constraint is enforced by a partial unique index, not by
application code.

**ADR 015 — HLS engine, ffmpeg segmentation.** *Context:* browsers and mobile
players expect HLS. *Decision:* one ffmpeg process per live session, copying
AAC into ~10 s `.ts` segments with a sliding manifest. *Consequence:* no
transcoding cost on the nominal path; the process is killed and its directory
cleaned on stop.

**ADR 030 — On-the-fly ingest transcoding.** *Context:* broadcasters do not all
push AAC. *Decision:* insert a second ffmpeg **only** when the content type is
not AAC. *Consequence:* the AAC path pays neither a process nor a re-encode;
undecodable input returns 415 rather than 500.

**ADR 027 — Microphone capture and AAC push.** *Context:* broadcasting from a
phone had to be possible without external software. *Decision:* capture on
device and push AAC/ADTS straight to the ingest endpoint. *Consequence:* the
phone becomes a complete broadcasting station.

**ADR 028 — Rotating the stream key.** *Context:* a leaked key must be
revocable. *Decision:* rotation replaces the key and invalidates the old one,
and is **refused while the stream is live**. *Consequence:* rotation cannot
break a broadcast in progress.

**ADR 016 — Scalability, load testing and the HLS limiter.** *Context:* the
brief asks for evidence, not confidence. *Decision:* a repeatable load test and
a concurrency cap on HLS requests. *Consequence:* past the cap the server
answers 503 with `Retry-After` immediately, rather than queueing and degrading
for everyone.

**ADR 025 — Real-time audience statistics.** *Context:* HLS holds no persistent
connection. *Decision:* estimate listeners from the playlist request rate.
*Consequence:* the order of magnitude is right and an exact count does not
exist — which the interface says plainly.

## Listening and library

**ADR 023 — Mobile HLS audio player.** *Context:* playback must survive
navigation. *Decision:* a single app-level player behind an abstraction the
controller depends on. *Consequence:* the player is testable with a fake, and
playback does not stop when the screen changes.

**ADR 031 — Background playback.** *Context:* audio must continue when the
screen locks. *Decision:* `audio_service`, with a system notification and its
controls. *Consequence:* native declarations are required on both platforms,
and the behaviour can only be tested on a device.

**ADR 033 — Handling audio interruptions.** *Context:* a call or a notification
must not leave playback in an inconsistent state. *Decision:* a **pure,
testable** interruption policy — pause and resume for calls, duck for
notifications, pause without resume when headphones are unplugged.
*Consequence:* the rule is unit-tested rather than observed by hand.

**ADR 026 — The playlists domain.** *Context:* playlists are personal.
*Decision:* ownership filtered in SQL, and a third party's playlist returns
**404** rather than 403. *Consequence:* the API never reveals that a resource it
refuses exists.

**ADR 029 — Playlist tracks: add, remove, reorder.** *Context:* reordering
rewrites every position, so intermediate states necessarily contain duplicates.
*Decision:* a **deferred** unique constraint, checked at commit, with all
mutations inside a transaction. *Consequence:* `ON CONFLICT` must name its
columns — a deferred constraint cannot arbitrate.

**ADR 032 — The track domain and audio upload.** *Context:* an uploaded file is
untrusted input. *Decision:* **sniff** the MIME type from the content, store
outside any served directory under a generated name, and cap both file and
account size. *Consequence:* a PDF renamed `.mp3` is rejected; the client's file
name never reaches the filesystem.

**ADR 034 — Playing a playlist with a queue.** *Context:* the player must
chain tracks. *Decision:* delegate chaining to the native player and follow its
index, rather than keeping a second source of truth. *Consequence:* a skip from
the system notification travels the same path as a tap in the app.

**ADR 035 — Shuffle and repeat.** *Context:* a shuffled order must be stable.
*Decision:* let the native player draw the order, and re-apply it on
**involuntary** reloads. *Consequence:* a token expiry no longer reshuffles the
queue every fifteen minutes.

## Administration

**ADR 017 — Admin dashboard, user management.** *Context:* administration must
not be able to lock itself out. *Decision:* search, filtering, deactivation and
deletion, with two guards — no self-action, and never the last active
administrator. *Consequence:* both return 409 with an explicit message.

**ADR 039 — Admin supervision and audit log.** *Context:* moderation must leave
a trace. *Decision:* interrupt any live stream without an ownership check, and
record it. *Consequence:* `actor_id` is set to NULL when the administrator's
account is deleted — the fact survives, the person does not.

**ADR 024 — Broadcaster dashboard.** *Context:* a stream can stop without its
owner acting. *Decision:* dedicated start and stop endpoints, and a server-sent
event stream the dashboard subscribes to. *Consequence:* the interface reflects
reality rather than the last action taken.

## Observability

**ADR 018 — Structured logs, zerolog and Loki.** *Context:* text logs are not
queryable. *Decision:* one JSON line per request, correlated by `request_id`,
with the `stream_key` redacted from paths. *Consequence:* `log.Printf` is banned
project-wide.

**ADR 019 — Prometheus metrics and cardinality.** *Context:* an unbounded label
kills a metrics store. *Decision:* label paths with the **router pattern**
rather than the URL, and keep methods to an allowlist. *Consequence:* there is
no table to keep in sync, and cardinality is bounded by construction.

**ADR 020 — OpenTelemetry traces to Tempo.** *Context:* a slow request must be
explainable. *Decision:* OTLP export, one span per SQL query — without the
arguments — and `trace_id` in every log line. *Consequence:* traces are disabled
by default locally, so `go run` needs no collector.

**ADR 021 — Provisioned Grafana alerting.** *Context:* an alert configured by
hand is lost with its container. *Decision:* declare contact points, policies
and rules as code. *Consequence:* the truth lives in git and the UI is
read-only.

**ADR 022 — Streaming business metrics.** *Context:* a technical 500 and a
listener dropping out are not the same event. *Decision:* separate business
metrics, and **delete** per-stream series when a stream ends. *Consequence:*
cardinality does not grow with every broadcast.

## Contracts and cross-cutting concerns

**ADR 012 — OpenAPI as the source of truth.** *Context:* a client and a server
drift. *Decision:* the specification is the contract; the Dart client is
generated from it. *Consequence:* a route change without a spec change is a bug,
and the spec is not published in production.

**ADR 005 — Flutter Clean Architecture.** *Context:* the mobile code needed a
shape. *Decision:* three layers per feature, entities free of any infrastructure
import. *Consequence:* superseded on state management by ADR 036.

**ADR 036 — `provider` rather than Riverpod.** *Context:* the course forbids
Riverpod. *Decision:* `provider` with `ChangeNotifier`, and the constraint
written down rather than hidden. *Consequence:* selective invalidation costs
more; the record says what that costs and how it is mitigated.

**ADR 040 — Mobile distribution.** *Context:* the app was signed with the debug
key and built nowhere. *Decision:* release signing that **degrades** loudly when
the key is absent, and Android artefacts attached to each GitHub release.
*Consequence:* iOS is not distributed — TestFlight requires a paid Apple
Developer account the team does not have, and that absence is stated rather than
faked.

> ADR 040 lands with the mobile distribution change; it is listed here because
> this index is meant to stay complete.
